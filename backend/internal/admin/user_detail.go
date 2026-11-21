package admin

import (
	"database/sql"
	"errors"
	"net/http"
	"time"
)

type userDetailView struct {
	ID, Status, Created string
	DeviceCount         int
	Devices             []deviceListItem
}

func (h *Handler) UserDetail(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if id == "" {
		http.NotFound(w, r)
		return
	}

	list, err := h.listUsers(200)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}

	var (
		status  string
		created time.Time
	)
	err = h.DB.QueryRow(`SELECT status, created_at FROM users WHERE id = ?`, id).Scan(&status, &created)
	if errors.Is(err, sql.ErrNoRows) {
		http.NotFound(w, r)
		return
	}
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}

	rows, err := h.DB.Query(`
		SELECT d.id, d.platform, COALESCE(d.model,''), COALESCE(d.os_version,''),
			COALESCE(d.app_version,''), COALESCE(d.app_build,0), COALESCE(d.last_seen_at, d.created_at),
			(SELECT COUNT(*) FROM wireguard_peers p WHERE p.device_id = d.id) AS peer_count
		FROM devices d WHERE d.user_id = ?
		ORDER BY d.created_at DESC`, id)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	defer rows.Close()

	var devices []deviceListItem
	for rows.Next() {
		var x deviceListItem
		var last time.Time
		if err := rows.Scan(&x.ID, &x.Platform, &x.Model, &x.OS, &x.AppVersion, &x.Build, &last, &x.PeerCount); err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		x.LastSeen = compactTime(last)
		devices = append(devices, x)
	}

	detail := userDetailView{
		ID:          id,
		Status:      status,
		Created:     created.UTC().Format(time.RFC3339),
		DeviceCount: len(devices),
		Devices:     devices,
	}

	_ = h.Tmpl.ExecuteTemplate(w, "users.html", map[string]any{
		"Users": list, "SelectedID": id, "User": detail, "CSRF": csrfFrom(r),
	})
}
