package device

import (
	"encoding/json"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"

	"github.com/TomasPetrik/vpn/backend/internal/httpapi"
)

const maxDiagnosticsBytes = 256 << 10 // 256 KiB

type diagnosticsBody struct {
	Summary string          `json:"summary"`
	App     json.RawMessage `json:"app"`
	Device  json.RawMessage `json:"device"`
	VPN     json.RawMessage `json:"vpn"`
	Log     json.RawMessage `json:"log"`
	Meta    json.RawMessage `json:"meta"`
}

// SubmitDiagnostics stores a client diagnostic report for the authenticated device.
// POST /api/v1/devices/me/diagnostics
func (h *Handler) SubmitDiagnostics(w http.ResponseWriter, r *http.Request) {
	deviceID, ok := r.Context().Value(httpapi.CtxDeviceID).(string)
	if !ok || deviceID == "" {
		httpapi.WriteError(w, http.StatusUnauthorized, "invalid_token", "unauthorized")
		return
	}
	if h.DB == nil {
		httpapi.WriteError(w, http.StatusInternalServerError, "internal", "database unavailable")
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, maxDiagnosticsBytes)
	raw, err := io.ReadAll(r.Body)
	if err != nil {
		httpapi.WriteError(w, http.StatusRequestEntityTooLarge, "invalid_request", "payload too large")
		return
	}
	if len(raw) == 0 {
		httpapi.WriteError(w, http.StatusBadRequest, "invalid_request", "empty payload")
		return
	}
	if !json.Valid(raw) {
		httpapi.WriteError(w, http.StatusBadRequest, "invalid_request", "invalid json")
		return
	}

	var body diagnosticsBody
	_ = json.Unmarshal(raw, &body)

	appVersion := ""
	appBuild := 0
	platform := ""
	if v, ok := r.Context().Value(httpapi.CtxVersion).(string); ok {
		appVersion = strings.TrimSpace(v)
	}
	if b, ok := r.Context().Value(httpapi.CtxBuild).(int); ok && b > 0 {
		appBuild = b
	}
	if p := strings.TrimSpace(r.Header.Get("X-App-Platform")); p != "" {
		platform = strings.ToLower(p)
	}

	// Prefer body.app when headers are missing.
	var appObj map[string]any
	if len(body.App) > 0 {
		_ = json.Unmarshal(body.App, &appObj)
		if appVersion == "" {
			if s, ok := appObj["version"].(string); ok {
				appVersion = strings.TrimSpace(s)
			}
		}
		if appBuild == 0 {
			switch v := appObj["build"].(type) {
			case string:
				if n, err := strconv.Atoi(strings.TrimSpace(v)); err == nil {
					appBuild = n
				}
			case float64:
				appBuild = int(v)
			}
		}
	}
	var deviceObj map[string]any
	if len(body.Device) > 0 {
		_ = json.Unmarshal(body.Device, &deviceObj)
		if platform == "" {
			if s, ok := deviceObj["platform"].(string); ok {
				platform = strings.ToLower(strings.TrimSpace(s))
			}
		}
	}

	summary := strings.TrimSpace(body.Summary)
	if summary == "" {
		logCount := 0
		var logArr []json.RawMessage
		if len(body.Log) > 0 && json.Unmarshal(body.Log, &logArr) == nil {
			logCount = len(logArr)
		}
		if logCount > 0 {
			summary = "Connect log · " + strconv.Itoa(logCount) + " lines"
		} else {
			summary = "Diagnostic report"
		}
	}
	if utf8.RuneCountInString(summary) > 255 {
		summary = string([]rune(summary)[:255])
	}

	id := uuid.Must(uuid.NewV7()).String()
	created := time.Now().UTC()
	clientIP := httpapi.ClientIP(r)

	var buildArg any
	if appBuild > 0 {
		buildArg = appBuild
	}
	_, err = h.DB.ExecContext(r.Context(), `
		INSERT INTO device_diagnostics (
			id, device_id, created_at, app_version, app_build, platform, summary, client_ip, payload_json
		) VALUES (?, ?, ?, NULLIF(?, ''), ?, NULLIF(?, ''), NULLIF(?, ''), NULLIF(?, ''), ?)`,
		id, deviceID, created, appVersion, buildArg, platform, summary, clientIP, string(raw),
	)
	if err != nil {
		httpapi.WriteError(w, http.StatusInternalServerError, "internal", "failed to store diagnostics")
		return
	}

	httpapi.WriteJSON(w, http.StatusCreated, map[string]any{
		"id":         id,
		"created_at": created.Format(time.RFC3339Nano),
		"summary":    summary,
	})
}
