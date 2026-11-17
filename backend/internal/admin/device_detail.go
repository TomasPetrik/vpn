package admin

import (
	"database/sql"
	"errors"
	"fmt"
	"net"
	"net/http"
	"time"
)

type deviceDetailView struct {
	ID, UserID, Platform, Status          string
	Manufacturer, Model, OSVersion        string
	AppVersion, InstallationID            string
	AppBuild                              int
	LastSeen, CreatedAt, UpdatedAt        string
	HasPeer                               bool
	PeerID, PeerPublicKey, TunnelIPv4     string
	ServerName, ServerID, WGInterface     string
	LastHandshake, StatsUpdated, PeerCreated string
	RxBytes, TxBytes, RxHuman, TxHuman    string
	TotalHuman                            string
	Note                                  string
}

func (h *Handler) DeviceDetail(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if id == "" {
		http.NotFound(w, r)
		return
	}

	var (
		d                             deviceDetailView
		lastSeen                      sql.NullTime
		created, updated              time.Time
		manufacturer, model, osVer    sql.NullString
		appVersion, installationID    sql.NullString
		appBuild                      sql.NullInt64
	)
	err := h.DB.QueryRow(`
		SELECT id, user_id, platform, status,
			manufacturer, model, os_version, app_version, app_build,
			installation_id, last_seen_at, created_at, updated_at
		FROM devices WHERE id = ?`, id).Scan(
		&d.ID, &d.UserID, &d.Platform, &d.Status,
		&manufacturer, &model, &osVer, &appVersion, &appBuild,
		&installationID, &lastSeen, &created, &updated,
	)
	if errors.Is(err, sql.ErrNoRows) {
		http.NotFound(w, r)
		return
	}
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	d.Manufacturer = nullString(manufacturer)
	d.Model = nullString(model)
	d.OSVersion = nullString(osVer)
	d.AppVersion = nullString(appVersion)
	d.InstallationID = nullString(installationID)
	if appBuild.Valid {
		d.AppBuild = int(appBuild.Int64)
	}
	d.CreatedAt = created.UTC().Format(time.RFC3339)
	d.UpdatedAt = updated.UTC().Format(time.RFC3339)
	if lastSeen.Valid {
		d.LastSeen = lastSeen.Time.UTC().Format(time.RFC3339)
	} else {
		d.LastSeen = "—"
	}
	d.Note = "Private WireGuard keys stay on the device. Only the client public key is stored on the server."

	var (
		peerID, pubKey, serverID, serverName, wgIface string
		tunnelIP                                     uint32
		rx, tx                                       uint64
		handshake, statsUpdated                      sql.NullTime
		peerCreated                                  time.Time
	)
	err = h.DB.QueryRow(`
		SELECT p.id, p.public_key, p.tunnel_ipv4, p.rx_bytes, p.tx_bytes,
			p.last_handshake_at, p.stats_updated_at, p.created_at,
			s.id, s.name, s.wg_interface
		FROM wireguard_peers p
		JOIN vpn_servers s ON s.id = p.server_id
		WHERE p.device_id = ?
		ORDER BY p.updated_at DESC
		LIMIT 1`, id).Scan(
		&peerID, &pubKey, &tunnelIP, &rx, &tx,
		&handshake, &statsUpdated, &peerCreated,
		&serverID, &serverName, &wgIface,
	)
	if err == nil {
		d.HasPeer = true
		d.PeerID = peerID
		d.PeerPublicKey = pubKey
		d.TunnelIPv4 = ipv4String(tunnelIP)
		d.ServerID = serverID
		d.ServerName = serverName
		d.WGInterface = wgIface
		d.RxBytes = fmt.Sprintf("%d", rx)
		d.TxBytes = fmt.Sprintf("%d", tx)
		d.RxHuman = humanBytes(rx)
		d.TxHuman = humanBytes(tx)
		d.TotalHuman = humanBytes(rx + tx)
		d.PeerCreated = peerCreated.UTC().Format(time.RFC3339)
		if handshake.Valid {
			d.LastHandshake = handshake.Time.UTC().Format(time.RFC3339)
		} else {
			d.LastHandshake = "never (tunnel not active yet)"
		}
		if statsUpdated.Valid {
			d.StatsUpdated = statsUpdated.Time.UTC().Format(time.RFC3339)
		} else {
			d.StatsUpdated = "—"
		}
	} else if !errors.Is(err, sql.ErrNoRows) {
		http.Error(w, err.Error(), 500)
		return
	}

	_ = h.Tmpl.ExecuteTemplate(w, "device_detail.html", map[string]any{
		"Device": d,
		"CSRF":   csrfFrom(r),
	})
}

func nullString(v sql.NullString) string {
	if v.Valid {
		return v.String
	}
	return ""
}

func ipv4String(v uint32) string {
	ip := net.IPv4(byte(v>>24), byte(v>>16), byte(v>>8), byte(v)).String()
	return ip + "/32"
}

func humanBytes(n uint64) string {
	const unit = 1024
	if n < unit {
		return fmt.Sprintf("%d B", n)
	}
	div, exp := uint64(unit), 0
	for v := n / unit; v >= unit; v /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.2f %ciB", float64(n)/float64(div), "KMGTPE"[exp])
}
