package appupdate

import (
	"net/http"
	"strconv"

	"github.com/TomasPetrik/vpn/backend/internal/httpapi"
)

type Handler struct {
	Service *Service
}

func (h *Handler) Config(w http.ResponseWriter, r *http.Request) {
	platform := r.URL.Query().Get("platform")
	if platform == "" {
		if p, ok := r.Context().Value(httpapi.CtxPlatform).(string); ok {
			platform = p
		}
	}
	build, _ := strconv.Atoi(r.URL.Query().Get("build"))
	if build == 0 {
		if b, ok := r.Context().Value(httpapi.CtxBuild).(int); ok {
			build = b
		}
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{
		"update": h.Service.Evaluate(platform, build),
	})
}

func Middleware(svc *Service) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			path := r.URL.Path
			if path == "/healthz" || path == "/api/v1/app/config" || path == "/api/v1/devices/register" {
				// register still checked? Spec: except /app/config and /healthz.
				// Registration also needs force upgrade so old apps cannot register.
			}
			if path == "/healthz" || path == "/api/v1/app/config" {
				next.ServeHTTP(w, r)
				return
			}
			if len(path) >= 7 && path[:7] == "/admin" {
				next.ServeHTTP(w, r)
				return
			}
			platform, _ := r.Context().Value(httpapi.CtxPlatform).(string)
			build, _ := r.Context().Value(httpapi.CtxBuild).(int)
			upd := svc.Evaluate(platform, build)
			if upd.Status == "required" {
				httpapi.WriteJSON(w, http.StatusUpgradeRequired, map[string]any{
					"error":  map[string]string{"code": "app_update_required", "message": upd.Message},
					"update": upd,
				})
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}
