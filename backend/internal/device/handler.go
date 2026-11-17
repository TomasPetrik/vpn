package device

import (
	"context"
	"encoding/json"
	"net/http"
	"strconv"
	"strings"

	"github.com/TomasPetrik/vpn/backend/internal/httpapi"
)

type Handler struct {
	Service *Service
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
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{
		"user_id":   u,
		"device_id": d,
	})
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
			svc.TouchBuild(r.Context(), d.ID, build, version)
			ctx := context.WithValue(r.Context(), httpapi.CtxDeviceID, d.ID)
			ctx = context.WithValue(ctx, httpapi.CtxUserID, d.UserID)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}
