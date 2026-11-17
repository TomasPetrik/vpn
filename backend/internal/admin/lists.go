package admin

import (
	"database/sql"
	"fmt"
	"time"
)

type deviceListItem struct {
	ID, Platform, Model, OS, AppVersion, LastSeen string
	Build, PeerCount                              int
}

type userListItem struct {
	ID, Status, Created string
	Devices             int
}

func (h *Handler) listDevices(limit int) ([]deviceListItem, error) {
	if limit <= 0 {
		limit = 200
	}
	rows, err := h.DB.Query(`
		SELECT d.id, d.platform, COALESCE(d.model,''), COALESCE(d.os_version,''),
			COALESCE(d.app_version,''), COALESCE(d.app_build,0), COALESCE(d.last_seen_at, d.created_at),
			(SELECT COUNT(*) FROM wireguard_peers p WHERE p.device_id = d.id) AS peer_count
		FROM devices d ORDER BY d.created_at DESC LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var list []deviceListItem
	for rows.Next() {
		var x deviceListItem
		var last time.Time
		if err := rows.Scan(&x.ID, &x.Platform, &x.Model, &x.OS, &x.AppVersion, &x.Build, &last, &x.PeerCount); err != nil {
			return nil, err
		}
		x.LastSeen = last.UTC().Format(time.RFC3339)
		list = append(list, x)
	}
	return list, rows.Err()
}

func (h *Handler) listUsers(limit int) ([]userListItem, error) {
	if limit <= 0 {
		limit = 200
	}
	rows, err := h.DB.Query(`
		SELECT u.id, u.status, u.created_at, COUNT(d.id)
		FROM users u LEFT JOIN devices d ON d.user_id = u.id
		GROUP BY u.id ORDER BY u.created_at DESC LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var list []userListItem
	for rows.Next() {
		var x userListItem
		var created time.Time
		if err := rows.Scan(&x.ID, &x.Status, &created, &x.Devices); err != nil {
			return nil, err
		}
		x.Created = created.UTC().Format(time.RFC3339)
		list = append(list, x)
	}
	return list, rows.Err()
}

func (h *Handler) listDBTables() ([]dbTableInfo, string, error) {
	rows, err := h.DB.Query(`
		SELECT table_name, table_rows, engine, COALESCE(table_comment, '')
		FROM information_schema.tables
		WHERE table_schema = DATABASE()
		ORDER BY table_name`)
	if err != nil {
		return nil, "", err
	}
	defer rows.Close()

	var tables []dbTableInfo
	for rows.Next() {
		var t dbTableInfo
		var engine sql.NullString
		var approx sql.NullInt64
		if err := rows.Scan(&t.Name, &approx, &engine, &t.Comment); err != nil {
			return nil, "", err
		}
		if engine.Valid {
			t.Engine = engine.String
		}
		var exact int64
		q := fmt.Sprintf("SELECT COUNT(*) FROM `%s`", t.Name)
		if err := h.DB.QueryRow(q).Scan(&exact); err == nil {
			t.Rows = exact
		} else if approx.Valid {
			t.Rows = approx.Int64
		}
		tables = append(tables, t)
	}
	var dbName string
	_ = h.DB.QueryRow(`SELECT DATABASE()`).Scan(&dbName)
	return tables, dbName, rows.Err()
}
