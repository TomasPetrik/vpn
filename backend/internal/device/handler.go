package device

import (
	"context"
	"database/sql"
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/TomasPetrik/vpn/backend/internal/httpapi"
	"github.com/TomasPetrik/vpn/backend/internal/limits"
	"github.com/TomasPetrik/vpn/backend/internal/usage"
)

type Handler struct {
	Service *Service
	DB      *sql.DB
}

type registerBody struct {
	InstallationID   string  `json:"installation_id"`
	DeviceIdentifier *string `json:"device_identifier"`
	Platform         string  `json:"platform"`
	Device           struct {
		Manufacturer     string `json:"manufacturer"`
		Model            string `json:"model"`
		OSVersion        string `json:"os_version"`
		IsPhysicalDevice bool   `json:"is_physical_device"`
	} `json:"device"`
	App struct {
		Version string `json:"version"`
		Build   string `json:"build"`
	} `json:"app"`
}

func (h *Handler) Register(w http.ResponseWriter, r *http.Request) {
	var body registerBody
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		httpapi.WriteError(w, http.StatusBadRequest, "invalid_request", "invalid json")
		return
	}
	build := 0
	if b := strings.TrimSpace(body.App.Build); b != "" {
		if n, err := strconv.Atoi(b); err == nil {
			build = n
		}
	}
	if v, ok := r.Context().Value(httpapi.CtxBuild).(int); ok && v > 0 {
		build = v
	}
	version := body.App.Version
	if v, ok := r.Context().Value(httpapi.CtxVersion).(string); ok && v != "" {
		version = v
	}

	bearer := strings.TrimSpace(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer "))

	res, err := h.Service.Register(r.Context(), RegisterRequest{
		InstallationID:   body.InstallationID,
		DeviceIdentifier: body.DeviceIdentifier,
		Platform:         body.Platform,
		Manufacturer:     body.Device.Manufacturer,
		Model:            body.Device.Model,
		OSVersion:        body.Device.OSVersion,
		AppVersion:       version,
		AppBuild:         build,
		BearerToken:      bearer,
	})
	if err != nil {
		switch err.Error() {
		case "device_blocked":
			httpapi.WriteError(w, http.StatusForbidden, "device_blocked", "device blocked")
		case "invalid platform", "invalid installation_id":
			httpapi.WriteError(w, http.StatusBadRequest, "invalid_request", err.Error())
		default:
			httpapi.WriteError(w, http.StatusInternalServerError, "internal", "registration failed")
		}
		return
	}
	h.Service.TouchSeen(r.Context(), res.DeviceID, build, version, httpapi.ClientIP(r), "")
	status := http.StatusOK
	if res.Created {
		status = http.StatusCreated
	}
	httpapi.WriteJSON(w, status, res)
}

func (h *Handler) Me(w http.ResponseWriter, r *http.Request) {
	d, ok := r.Context().Value(httpapi.CtxDeviceID).(string)
	u, ok2 := r.Context().Value(httpapi.CtxUserID).(string)
	if !ok || !ok2 {
		httpapi.WriteError(w, http.StatusUnauthorized, "invalid_token", "unauthorized")
		return
	}
	clientIP := httpapi.ClientIP(r)
	country := ""
	if h.Service != nil && h.Service.CountryOf != nil && clientIP != "" {
		country = h.Service.CountryOf(clientIP)
	}
	out := map[string]any{
		"user_id":        u,
		"device_id":      d,
		"client_ip":      clientIP,
		"client_country": country,
	}
	if h.DB != nil {
		now := time.Now().UTC()
		store := &limits.Store{DB: h.DB}
		if eff, err := store.ForDevice(r.Context(), d, now); err == nil {
			out["plan"] = eff.PlanCode
			out["limits"] = map[string]any{
				"download_kbps":        limits.APIValue(eff.DownloadKbps),
				"upload_kbps":          limits.APIValue(eff.UploadKbps),
				"monthly_quota_bytes":  limits.APIValue(eff.MonthlyQuotaBytes),
				"monthly_used_bytes":   eff.MonthlyUsedBytes,
				"download_source":      eff.DownloadSource,
				"upload_source":        eff.UploadSource,
				"monthly_quota_source": eff.MonthlyQuotaSource,
			}
		}
		if speed, err := usage.LoadSpeed(r.Context(), h.DB, d, "24h", now); err == nil {
			out["avg_speed"] = map[string]any{
				"download_MBps":         speed.DownloadMBps,
				"upload_MBps":           speed.UploadMBps,
				"active_download_MBps":  speed.ActiveDownloadMBps,
				"active_upload_MBps":    speed.ActiveUploadMBps,
				"max_download_MBps":     speed.MaxDownloadMBps,
				"max_upload_MBps":       speed.MaxUploadMBps,
				"current_download_MBps": speed.CurrentDownloadMBps,
				"current_upload_MBps":   speed.CurrentUploadMBps,
				"range":                 speed.Range,
			}
		}
	}
	httpapi.WriteJSON(w, http.StatusOK, out)
}

// Usage returns zero-filled transfer buckets for the authenticated device.
// Query: range=24h|7d|30d|all (default 7d).
func (h *Handler) Usage(w http.ResponseWriter, r *http.Request) {
	deviceID, ok := r.Context().Value(httpapi.CtxDeviceID).(string)
	if !ok || deviceID == "" {
		httpapi.WriteError(w, http.StatusUnauthorized, "invalid_token", "unauthorized")
		return
	}
	if h.DB == nil {
		httpapi.WriteError(w, http.StatusInternalServerError, "internal", "database unavailable")
		return
	}
	rangeKey := r.URL.Query().Get("range")
	series, err := usage.Load(r.Context(), h.DB, deviceID, rangeKey, time.Now().UTC())
	if err != nil {
		httpapi.WriteError(w, http.StatusInternalServerError, "internal", "usage query failed")
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, series)
}

func AuthMiddleware(svc *Service) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			bearer := strings.TrimSpace(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer "))
			d, err := svc.Authenticate(r.Context(), bearer)
			if err != nil {
				code := err.Error()
				status := http.StatusUnauthorized
				if code == "device_blocked" {
					status = http.StatusForbidden
				}
				httpapi.WriteError(w, status, code, "unauthorized")
				return
			}
			build, _ := r.Context().Value(httpapi.CtxBuild).(int)
			version, _ := r.Context().Value(httpapi.CtxVersion).(string)
			svc.TouchSeen(r.Context(), d.ID, build, version, httpapi.ClientIP(r), "")
			ctx := context.WithValue(r.Context(), httpapi.CtxDeviceID, d.ID)
			ctx = context.WithValue(ctx, httpapi.CtxUserID, d.UserID)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}
