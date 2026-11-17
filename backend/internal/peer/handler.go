package peer

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/TomasPetrik/vpn/backend/internal/httpapi"
)

type Handler struct {
	Service *Service
}

type upsertBody struct {
	PublicKey string `json:"public_key"`
}

func (h *Handler) Upsert(w http.ResponseWriter, r *http.Request) {
	deviceID, _ := r.Context().Value(httpapi.CtxDeviceID).(string)
	if deviceID == "" {
		httpapi.WriteError(w, http.StatusUnauthorized, "invalid_token", "unauthorized")
		return
	}
	var body upsertBody
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		httpapi.WriteError(w, http.StatusBadRequest, "invalid_request", "invalid json")
		return
	}
	cfg, err := h.Service.Upsert(r.Context(), deviceID, body.PublicKey)
	if err != nil {
		if errors.Is(err, ErrInvalidKey) {
			httpapi.WriteError(w, http.StatusBadRequest, "invalid_request", "invalid public_key")
			return
		}
		httpapi.WriteError(w, http.StatusInternalServerError, "internal", "peer provisioning failed")
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, cfg)
}

func (h *Handler) Get(w http.ResponseWriter, r *http.Request) {
	deviceID, _ := r.Context().Value(httpapi.CtxDeviceID).(string)
	if deviceID == "" {
		httpapi.WriteError(w, http.StatusUnauthorized, "invalid_token", "unauthorized")
		return
	}
	cfg, err := h.Service.Get(r.Context(), deviceID)
	if err != nil {
		if errors.Is(err, ErrNotFound) {
			httpapi.WriteError(w, http.StatusNotFound, "not_found", "peer not found")
			return
		}
		httpapi.WriteError(w, http.StatusInternalServerError, "internal", "peer lookup failed")
		return
	}
	httpapi.WriteJSON(w, http.StatusOK, cfg)
}
