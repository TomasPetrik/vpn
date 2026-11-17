package serverinfo

import (
	"database/sql"
	"net/http"

	"github.com/TomasPetrik/vpn/backend/internal/config"
	"github.com/TomasPetrik/vpn/backend/internal/httpapi"
)

type Handler struct {
	Cfg *config.Config
	DB  *sql.DB
}

func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	status := "online"
	if err := h.DB.PingContext(r.Context()); err != nil {
		status = "degraded"
	}
	httpapi.WriteJSON(w, http.StatusOK, map[string]any{
		"servers": []map[string]any{{
			"id":           h.Cfg.ServerID,
			"name":         h.Cfg.ServerName,
			"country_code": h.Cfg.ServerCountry,
			"city":         nullIfEmpty(h.Cfg.ServerCity),
			"status":       status,
		}},
	})
}

func nullIfEmpty(s string) any {
	if s == "" {
		return nil
	}
	return s
}
