package admin

import (
	"database/sql"
	"html/template"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/TomasPetrik/vpn/backend/internal/appupdate"
	"github.com/TomasPetrik/vpn/backend/internal/config"
)

type Handler struct {
	Store   *Store
	DB      *sql.DB
	Updates *appupdate.Service
	Tmpl    *template.Template
	Cfg     *config.Config
}

func (h *Handler) LoginForm(w http.ResponseWriter, r *http.Request) {
	_ = h.Tmpl.ExecuteTemplate(w, "login.html", map[string]any{"Error": ""})
}

func (h *Handler) LoginSubmit(w http.ResponseWriter, r *http.Request) {
	_ = r.ParseForm()
	username := strings.TrimSpace(r.Form.Get("username"))
	password := r.Form.Get("password")
	adminID, err := h.Store.Authenticate(username, password)
	if err != nil {
		w.WriteHeader(http.StatusUnauthorized)
		_ = h.Tmpl.ExecuteTemplate(w, "login.html", map[string]any{"Error": "Invalid credentials"})
		return
	}
	cookie, csrf, err := h.Store.CreateSession(adminID, httpapiClientIP(r), r.UserAgent())
	if err != nil {
		http.Error(w, "session error", 500)
		return
	}
	secure := isHTTPS(r)
	http.SetCookie(w, &http.Cookie{
		Name:     "__Host-vpn_admin",
		Value:    cookie,
		Path:     "/",
		HttpOnly: true,
		Secure:   true, // __Host- requires Secure
		SameSite: http.SameSiteStrictMode,
		MaxAge:   int((12 * time.Hour).Seconds()),
	})
	// Non-Host fallback for local HTTP; Secure whenever the request is HTTPS.
	http.SetCookie(w, &http.Cookie{
		Name:     "vpn_admin",
		Value:    cookie,
		Path:     "/",
		HttpOnly: true,
		Secure:   secure,
		SameSite: http.SameSiteStrictMode,
		MaxAge:   int((12 * time.Hour).Seconds()),
	})
	_ = csrf
	http.Redirect(w, r, "/admin", http.StatusSeeOther)
}

func (h *Handler) Logout(w http.ResponseWriter, r *http.Request) {
	if c := readSessionCookie(r); c != "" {
		h.Store.DeleteSession(c)
	}
	http.SetCookie(w, &http.Cookie{Name: "__Host-vpn_admin", Value: "", Path: "/", MaxAge: -1})
	http.SetCookie(w, &http.Cookie{Name: "vpn_admin", Value: "", Path: "/", MaxAge: -1})
	http.Redirect(w, r, "/admin/login", http.StatusSeeOther)
}

func (h *Handler) RequireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		c := readSessionCookie(r)
		if c == "" {
			http.Redirect(w, r, "/admin/login", http.StatusSeeOther)
			return
		}
		adminID, csrf, err := h.Store.Session(c)
		if err != nil {
			http.Redirect(w, r, "/admin/login", http.StatusSeeOther)
			return
		}
		ctx := r.Context()
		ctx = withAdmin(ctx, adminID, csrf)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func (h *Handler) Dashboard(w http.ResponseWriter, r *http.Request) {
	var users, devices int
	_ = h.DB.QueryRow(`SELECT COUNT(*) FROM users`).Scan(&users)
	_ = h.DB.QueryRow(`SELECT COUNT(*) FROM devices`).Scan(&devices)
	_ = h.Tmpl.ExecuteTemplate(w, "dashboard.html", map[string]any{
		"Users": users, "Devices": devices, "CSRF": csrfFrom(r),
	})
}

func (h *Handler) Users(w http.ResponseWriter, r *http.Request) {
	rows, err := h.DB.Query(`
		SELECT u.id, u.status, u.created_at, COUNT(d.id)
		FROM users u LEFT JOIN devices d ON d.user_id = u.id
		GROUP BY u.id ORDER BY u.created_at DESC LIMIT 200`)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	defer rows.Close()
	type row struct {
		ID, Status, Created string
		Devices             int
	}
	var list []row
	for rows.Next() {
		var x row
		var created time.Time
		if err := rows.Scan(&x.ID, &x.Status, &created, &x.Devices); err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		x.Created = created.Format(time.RFC3339)
		list = append(list, x)
	}
	_ = h.Tmpl.ExecuteTemplate(w, "users.html", map[string]any{"Users": list, "CSRF": csrfFrom(r)})
}

func (h *Handler) Devices(w http.ResponseWriter, r *http.Request) {
	rows, err := h.DB.Query(`
		SELECT d.id, d.platform, COALESCE(d.model,''), COALESCE(d.os_version,''),
			COALESCE(d.app_version,''), COALESCE(d.app_build,0), COALESCE(d.last_seen_at, d.created_at),
			(SELECT COUNT(*) FROM wireguard_peers p WHERE p.device_id = d.id) AS peer_count
		FROM devices d ORDER BY d.created_at DESC LIMIT 200`)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	defer rows.Close()
	type row struct {
		ID, Platform, Model, OS, AppVersion, LastSeen string
		Build, PeerCount                              int
	}
	var list []row
	for rows.Next() {
		var x row
		var last time.Time
		if err := rows.Scan(&x.ID, &x.Platform, &x.Model, &x.OS, &x.AppVersion, &x.Build, &last, &x.PeerCount); err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		x.LastSeen = last.Format(time.RFC3339)
		list = append(list, x)
	}
	_ = h.Tmpl.ExecuteTemplate(w, "devices.html", map[string]any{"Devices": list, "CSRF": csrfFrom(r)})
}

func (h *Handler) AppVersionsGet(w http.ResponseWriter, r *http.Request) {
	android := h.Updates.Policy("android")
	ios := h.Updates.Policy("ios")
	_ = h.Tmpl.ExecuteTemplate(w, "app_versions.html", map[string]any{
		"Android": android, "IOS": ios, "CSRF": csrfFrom(r), "Flash": "",
	})
}

func (h *Handler) AppVersionsPost(w http.ResponseWriter, r *http.Request) {
	_ = r.ParseForm()
	if r.Form.Get("csrf") != csrfFrom(r) {
		http.Error(w, "csrf", 403)
		return
	}
	platform := r.Form.Get("platform")
	minBuild, _ := strconv.Atoi(r.Form.Get("min_supported_build"))
	latest, _ := strconv.Atoi(r.Form.Get("latest_build"))
	url := r.Form.Get("update_url")
	message := r.Form.Get("message")
	if latest < minBuild {
		http.Error(w, "latest_build must be >= min_supported_build", 400)
		return
	}
	blocked, _ := h.Updates.CountBlocked(r.Context(), platform, minBuild)
	if r.Form.Get("confirm") != "1" {
		_ = h.Tmpl.ExecuteTemplate(w, "app_versions_confirm.html", map[string]any{
			"Platform": platform, "Min": minBuild, "Latest": latest,
			"URL": url, "Message": message, "Blocked": blocked, "CSRF": csrfFrom(r),
		})
		return
	}
	adminID := adminIDFrom(r)
	if err := h.Updates.Set(r.Context(), platform, minBuild, latest, url, message, adminID); err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	http.Redirect(w, r, "/admin/app-versions", http.StatusSeeOther)
}

func readSessionCookie(r *http.Request) string {
	if c, err := r.Cookie("__Host-vpn_admin"); err == nil && c.Value != "" {
		return c.Value
	}
	if c, err := r.Cookie("vpn_admin"); err == nil {
		return c.Value
	}
	return ""
}

func isHTTPS(r *http.Request) bool {
	if r.TLS != nil {
		return true
	}
	return strings.EqualFold(r.Header.Get("X-Forwarded-Proto"), "https")
}

func httpapiClientIP(r *http.Request) string {
	host := r.RemoteAddr
	if i := strings.LastIndex(host, ":"); i > 0 {
		return host[:i]
	}
	return host
}
