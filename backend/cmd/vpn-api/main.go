package main

import (
	"context"
	"database/sql"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/TomasPetrik/vpn/backend/internal/admin"
	"github.com/TomasPetrik/vpn/backend/internal/appupdate"
	"github.com/TomasPetrik/vpn/backend/internal/config"
	"github.com/TomasPetrik/vpn/backend/internal/db"
	"github.com/TomasPetrik/vpn/backend/internal/device"
	"github.com/TomasPetrik/vpn/backend/internal/geo"
	"github.com/TomasPetrik/vpn/backend/internal/httpapi"
	"github.com/TomasPetrik/vpn/backend/internal/maintenance"
	"github.com/TomasPetrik/vpn/backend/internal/peer"
	"github.com/TomasPetrik/vpn/backend/internal/serverinfo"
	wgpkg "github.com/TomasPetrik/vpn/backend/internal/wg"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	if len(os.Args) < 2 {
		fatal(log, "usage: vpn-api <serve|migrate|admin|maintenance>")
	}
	switch os.Args[1] {
	case "serve":
		if err := runServe(log); err != nil {
			fatal(log, err.Error())
		}
	case "migrate":
		if len(os.Args) < 3 || os.Args[2] != "up" {
			fatal(log, "usage: vpn-api migrate up")
		}
		if err := runMigrate(log); err != nil {
			fatal(log, err.Error())
		}
	case "admin":
		if len(os.Args) < 4 || os.Args[2] != "create" {
			fatal(log, "usage: vpn-api admin create <username>")
		}
		if err := runAdminCreate(log, os.Args[3]); err != nil {
			fatal(log, err.Error())
		}
	case "maintenance":
		if err := runMaintenance(log, os.Args[2:]); err != nil {
			fatal(log, err.Error())
		}
	default:
		fatal(log, "unknown command")
	}
}

func fatal(log *slog.Logger, msg string) {
	log.Error(msg)
	os.Exit(1)
}

func openDB(log *slog.Logger) (*sql.DB, config.Config) {
	cfg, err := config.Load()
	if err != nil {
		fatal(log, err.Error())
	}
	sqlDB, err := db.Open(cfg.DatabaseDSN)
	if err != nil {
		fatal(log, err.Error())
	}
	return sqlDB, cfg
}

func runMigrate(log *slog.Logger) error {
	sqlDB, _ := openDB(log)
	defer sqlDB.Close()
	if err := db.MigrateUp(sqlDB); err != nil {
		return err
	}
	log.Info("migrations applied")
	return nil
}

func runMaintenance(log *slog.Logger, args []string) error {
	if len(args) < 1 || args[0] != "merge-duplicate-models" {
		return fmt.Errorf("usage: vpn-api maintenance merge-duplicate-models [--apply]")
	}
	apply := false
	for _, a := range args[1:] {
		if a == "--apply" {
			apply = true
		}
	}
	sqlDB, cfg := openDB(log)
	defer sqlDB.Close()
	wgDriver, err := wgpkg.New(cfg.WGDriver, cfg.WGInterface)
	if err != nil {
		return fmt.Errorf("wireguard driver: %w", err)
	}
	ctx := context.Background()
	if !apply {
		log.Info("dry-run only; pass --apply to mutate")
	}
	return maintenance.MergeDuplicateModels(ctx, sqlDB, wgDriver, log, apply)
}

func runAdminCreate(log *slog.Logger, username string) error {
	sqlDB, _ := openDB(log)
	defer sqlDB.Close()
	fmt.Fprint(os.Stderr, "Admin password: ")
	pw, err := readPassword()
	if err != nil {
		return err
	}
	if len(pw) < 10 {
		return fmt.Errorf("password too short")
	}
	store := &admin.Store{DB: sqlDB}
	if err := store.CreateAdmin(username, pw); err != nil {
		return err
	}
	log.Info("admin created", "username", username)
	return nil
}

func readPassword() (string, error) {
	b := make([]byte, 0, 64)
	tmp := make([]byte, 1)
	for {
		n, err := os.Stdin.Read(tmp)
		if n > 0 {
			if tmp[0] == '\n' || tmp[0] == '\r' {
				break
			}
			b = append(b, tmp[0])
		}
		if err != nil {
			break
		}
	}
	return strings.TrimSpace(string(b)), nil
}

func runServe(log *slog.Logger) error {
	sqlDB, cfg := openDB(log)
	defer sqlDB.Close()

	tmpl, err := admin.LoadTemplates()
	if err != nil {
		return err
	}

	geoLookup := geo.Open(cfg.GeoIPCountryDB, log)
	defer geoLookup.Close()

	deviceSvc := &device.Service{
		DB: sqlDB, HMACKey: cfg.DeviceIDHMACKey,
		CountryOf: geoLookup.Country,
	}
	deviceH := &device.Handler{Service: deviceSvc, DB: sqlDB}
	updateSvc := appupdate.New(sqlDB)
	updateH := &appupdate.Handler{Service: updateSvc}
	serverH := &serverinfo.Handler{Cfg: &cfg, DB: sqlDB}
	wgDriver, err := wgpkg.New(cfg.WGDriver, cfg.WGInterface)
	if err != nil {
		return fmt.Errorf("wireguard driver: %w", err)
	}
	peerSvc := &peer.Service{DB: sqlDB, Cfg: &cfg, WG: wgDriver}
	peerH := &peer.Handler{Service: peerSvc}
	adminStore := &admin.Store{DB: sqlDB}
	adminH := &admin.Handler{Store: adminStore, DB: sqlDB, Updates: updateSvc, Tmpl: tmpl, Cfg: &cfg, Peers: peerSvc}

	if err := peerSvc.EnsureServer(context.Background()); err != nil {
		return fmt.Errorf("seed vpn server: %w", err)
	}

	statsCtx, statsCancel := context.WithCancel(context.Background())
	defer statsCancel()
	peerSvc.StartStatsLoop(statsCtx, log, 15*time.Second)
	if n, err := peerSvc.SyncStats(context.Background()); err != nil {
		log.Warn("initial peer stats sync", "err", err)
	} else {
		log.Info("initial peer stats sync", "peers", n)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		httpapi.WriteJSON(w, 200, map[string]string{"status": "ok"})
	})
	mux.HandleFunc("GET /api/v1/app/config", updateH.Config)

	regLimit := httpapi.NewIPRateLimiter(30, time.Minute)
	mux.Handle("POST /api/v1/devices/register", regLimit.Middleware(http.HandlerFunc(deviceH.Register)))

	auth := device.AuthMiddleware(deviceSvc)
	mux.Handle("GET /api/v1/me", auth(http.HandlerFunc(deviceH.Me)))
	mux.Handle("GET /api/v1/servers", auth(http.HandlerFunc(serverH.List)))
	mux.Handle("GET /api/v1/devices/me/usage", auth(http.HandlerFunc(deviceH.Usage)))
	mux.Handle("POST /api/v1/devices/me/diagnostics", auth(http.HandlerFunc(deviceH.SubmitDiagnostics)))
	mux.Handle("PUT /api/v1/devices/me/peer", auth(http.HandlerFunc(peerH.Upsert)))
	mux.Handle("GET /api/v1/devices/me/peer", auth(http.HandlerFunc(peerH.Get)))

	mux.Handle("GET /admin/static/", admin.StaticHandler())

	loginLimit := httpapi.NewIPRateLimiter(10, time.Minute)
	mux.Handle("GET /admin/login", http.HandlerFunc(adminH.LoginForm))
	mux.Handle("POST /admin/login", loginLimit.Middleware(http.HandlerFunc(adminH.LoginSubmit)))
	mux.Handle("POST /admin/logout", adminH.RequireAuth(http.HandlerFunc(adminH.Logout)))
	mux.Handle("GET /admin", adminH.RequireAuth(http.HandlerFunc(adminH.Dashboard)))
	mux.Handle("GET /admin/users", adminH.RequireAuth(http.HandlerFunc(adminH.Users)))
	mux.Handle("GET /admin/users/{id}", adminH.RequireAuth(http.HandlerFunc(adminH.UserDetail)))
	mux.Handle("GET /admin/devices", adminH.RequireAuth(http.HandlerFunc(adminH.Devices)))
	mux.Handle("GET /admin/devices/{id}", adminH.RequireAuth(http.HandlerFunc(adminH.DeviceDetail)))
	mux.Handle("GET /admin/analytics", adminH.RequireAuth(http.HandlerFunc(adminH.AnalyticsUsage)))
	mux.Handle("GET /admin/app-versions", adminH.RequireAuth(http.HandlerFunc(adminH.AppVersionsGet)))
	mux.Handle("GET /admin/app-versions/{platform}", adminH.RequireAuth(http.HandlerFunc(adminH.AppVersionsGet)))
	mux.Handle("POST /admin/app-versions", adminH.RequireAuth(http.HandlerFunc(adminH.AppVersionsPost)))
	mux.Handle("GET /admin/limits", adminH.RequireAuth(http.HandlerFunc(adminH.LimitsGet)))
	mux.Handle("POST /admin/limits", adminH.RequireAuth(http.HandlerFunc(adminH.LimitsPost)))
	mux.Handle("POST /admin/users/{id}/limits", adminH.RequireAuth(http.HandlerFunc(adminH.UserLimitsPost)))
	mux.Handle("POST /admin/devices/{id}/limits", adminH.RequireAuth(http.HandlerFunc(adminH.DeviceLimitsPost)))
	mux.Handle("GET /admin/database", adminH.RequireAuth(http.HandlerFunc(adminH.DatabaseIndex)))
	mux.Handle("GET /admin/database/{table}", adminH.RequireAuth(http.HandlerFunc(adminH.DatabaseTable)))

	var handler http.Handler = mux
	handler = appupdate.Middleware(updateSvc)(handler)
	handler = httpapi.AppHeaders(handler)
	handler = httpapi.Logging(log)(handler)
	handler = httpapi.Recover(log)(handler)
	handler = httpapi.RequestID(handler)

	srv := &http.Server{Addr: cfg.HTTPAddr, Handler: handler}
	go func() {
		log.Info("listening", "addr", cfg.HTTPAddr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Error("serve", "err", err)
			os.Exit(1)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	return srv.Shutdown(ctx)
}
