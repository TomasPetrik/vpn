package admin

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"strings"
	"time"
)

type deviceDetailView struct {
	ID, UserID, Platform, Status             string
	Manufacturer, Model, OSVersion           string
	AppVersion, InstallationID               string
	AppBuild                                 int
	LastSeen, CreatedAt, UpdatedAt           string
	HasPeer                                  bool
	PeerID, PeerPublicKey, TunnelIPv4        string
	ServerName, ServerID, WGInterface        string
	ServerPublicKey, TunnelCIDR              string
	LastHandshake, StatsUpdated, PeerCreated string
	RxBytes, TxBytes, RxHuman, TxHuman       string
	TotalHuman                               string
	Note                                     string
	ServerPeerStanza                         string
	ClientConfPreview                        string
	ClientAPIJSON                            string
	WGDriver                                 string
	LastClientIP, LastClientCountry          string
	HandshakeCount                           uint64
	Panels                                   []artifactPanel
}

func (h *Handler) DeviceDetail(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if id == "" {
		http.NotFound(w, r)
		return
	}

	list, err := h.listDevices(200)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}

	d, err := h.loadDeviceDetail(r, id)
	if errors.Is(err, sql.ErrNoRows) {
		http.NotFound(w, r)
		return
	}
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}

	analytics, aerr := h.loadAnalytics(r, id)
	if aerr != nil {
		http.Error(w, aerr.Error(), 500)
		return
	}

	_ = h.Tmpl.ExecuteTemplate(w, "devices.html", map[string]any{
		"Devices": list, "SelectedID": id, "Device": d, "Analytics": analytics, "CSRF": csrfFrom(r),
	})
}

func (h *Handler) loadDeviceDetail(r *http.Request, id string) (deviceDetailView, error) {
	var (
		d                          deviceDetailView
		lastSeen                   sql.NullTime
		created, updated           time.Time
		manufacturer, model, osVer sql.NullString
		appVersion, installationID sql.NullString
		appBuild                   sql.NullInt64
	)
	var lastIP, lastCountry sql.NullString
	err := h.DB.QueryRow(`
		SELECT id, user_id, platform, status,
			manufacturer, model, os_version, app_version, app_build,
			installation_id, last_seen_at, last_client_ip, last_client_country,
			created_at, updated_at
		FROM devices WHERE id = ?`, id).Scan(
		&d.ID, &d.UserID, &d.Platform, &d.Status,
		&manufacturer, &model, &osVer, &appVersion, &appBuild,
		&installationID, &lastSeen, &lastIP, &lastCountry,
		&created, &updated,
	)
	if err != nil {
		return d, err
	}
	d.Manufacturer = nullString(manufacturer)
	d.Model = nullString(model)
	d.OSVersion = nullString(osVer)
	d.AppVersion = nullString(appVersion)
	d.InstallationID = nullString(installationID)
	d.LastClientIP = nullString(lastIP)
	d.LastClientCountry = nullString(lastCountry)
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
	d.Note = "Private WireGuard keys stay on the device. Only the client public key is stored on the server. Peers are DB + kernel (wgctrl), not per-device files."
	if h.Cfg != nil {
		d.WGDriver = h.Cfg.WGDriver
	}
	// Refresh counters from kernel before rendering so admin sees live traffic.
	if h.Peers != nil {
		if _, syncErr := h.Peers.SyncStats(r.Context()); syncErr != nil {
			// Non-fatal: page still renders last DB values.
			_ = syncErr
		}
	}

	var (
		peerID, pubKey, serverID, serverName, wgIface string
		serverPub, tunnelCIDR                         string
		tunnelIP                                      uint32
		rx, tx                                        uint64
		handshake, statsUpdated                       sql.NullTime
		peerCreated                                   time.Time
	)
	var hsCount uint64
	err = h.DB.QueryRow(`
		SELECT p.id, p.public_key, p.tunnel_ipv4, p.rx_bytes, p.tx_bytes,
			p.last_handshake_at, p.handshake_count, p.stats_updated_at, p.created_at,
			s.id, s.name, s.wg_interface, s.wg_public_key, s.tunnel_cidr
		FROM wireguard_peers p
		JOIN vpn_servers s ON s.id = p.server_id
		WHERE p.device_id = ?
		ORDER BY p.updated_at DESC
		LIMIT 1`, id).Scan(
		&peerID, &pubKey, &tunnelIP, &rx, &tx,
		&handshake, &hsCount, &statsUpdated, &peerCreated,
		&serverID, &serverName, &wgIface, &serverPub, &tunnelCIDR,
	)
	if err == nil {
		d.HasPeer = true
		d.PeerID = peerID
		d.PeerPublicKey = pubKey
		d.TunnelIPv4 = ipv4String(tunnelIP)
		d.HandshakeCount = hsCount
		d.ServerID = serverID
		d.ServerName = serverName
		d.WGInterface = wgIface
		d.ServerPublicKey = serverPub
		d.TunnelCIDR = tunnelCIDR
		d.RxBytes = fmt.Sprintf("%d", rx)
		d.TxBytes = fmt.Sprintf("%d", tx)
		d.RxHuman = humanBytes(rx)
		d.TxHuman = humanBytes(tx)
		d.TotalHuman = humanBytes(rx + tx)
		d.PeerCreated = peerCreated.UTC().Format(time.RFC3339)
		if handshake.Valid {
			d.LastHandshake = handshake.Time.UTC().Format(time.RFC3339)
		} else {
			d.LastHandshake = "never"
		}
		if statsUpdated.Valid {
			d.StatsUpdated = statsUpdated.Time.UTC().Format(time.RFC3339)
		} else {
			d.StatsUpdated = "—"
		}
		h.fillPeerConfigViews(&d, tunnelIP)
	} else if !errors.Is(err, sql.ErrNoRows) {
		return d, err
	}

	d.Panels = h.buildArtifactPanels(&d)
	return d, nil
}

func (h *Handler) fillPeerConfigViews(d *deviceDetailView, tunnelIP uint32) {
	iface := d.WGInterface
	if iface == "" && h.Cfg != nil {
		iface = h.Cfg.WGInterface
	}
	d.ServerPeerStanza = fmt.Sprintf(
		"# Not a file on disk — what would be applied to %s\n"+
			"# (wgctrl / wg set) once the WG driver is live. Today peers live in MySQL.\n"+
			"[Peer]\n"+
			"PublicKey = %s\n"+
			"AllowedIPs = %s\n",
		iface, d.PeerPublicKey, d.TunnelIPv4,
	)

	dns := []string{"1.1.1.1", "1.0.0.1"}
	mtu := 1280
	serverPub := d.ServerPublicKey
	wstunnelURL := "wss://vpn.radarcut.com"
	pathPref := ""
	remote := "127.0.0.1:51821"
	excluded := []string{}
	serverIPs := []string{}
	serverName := d.ServerName
	serverID := d.ServerID
	country := ""
	city := any(nil)

	if h.Cfg != nil {
		if len(h.Cfg.VPNDNS) > 0 {
			dns = h.Cfg.VPNDNS
		}
		mtu = h.Cfg.VPNMTU
		if h.Cfg.WGPublicKey != "" {
			serverPub = h.Cfg.WGPublicKey
		}
		wstunnelURL = h.Cfg.WstunnelURL
		pathPref = h.Cfg.WstunnelPathPref
		remote = h.Cfg.WGRemote
		serverIPs = append(serverIPs, h.Cfg.ServerPublicIPs...)
		for _, ip := range h.Cfg.ServerPublicIPs {
			excluded = append(excluded, ip+"/32")
		}
		serverName = h.Cfg.ServerName
		serverID = h.Cfg.ServerID
		country = h.Cfg.ServerCountry
		if h.Cfg.ServerCity != "" {
			city = h.Cfg.ServerCity
		}
	}

	d.ClientConfPreview = fmt.Sprintf(`# Synthetic client .conf preview (PrivateKey never leaves the phone)
# Used by WireGuardKit in step 4; Endpoint comes via wstunnel in step 5.
[Interface]
Address = %s
DNS = %s
MTU = %d
# PrivateKey = <device Keychain only>

[Peer]
PublicKey = %s
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
# Endpoint = via wstunnel → %s
`, d.TunnelIPv4, strings.Join(dns, ", "), mtu, serverPub, remote)

	api := map[string]any{
		"peer_id": d.PeerID,
		"server": map[string]any{
			"id":           serverID,
			"name":         serverName,
			"country_code": country,
			"city":         city,
		},
		"interface": map[string]any{
			"addresses": []string{d.TunnelIPv4},
			"dns":       dns,
			"mtu":       mtu,
		},
		"peer": map[string]any{
			"public_key":           serverPub,
			"allowed_ips":          []string{"0.0.0.0/0", "::/0"},
			"excluded_ips":         excluded,
			"persistent_keepalive": 25,
		},
		"transport": map[string]any{
			"type":        "wstunnel",
			"url":         wstunnelURL,
			"path_prefix": maskSecret(pathPref),
			"remote":      remote,
			"server_ips":  serverIPs,
		},
		"_note": "Same shape as GET/PUT /api/v1/devices/me/peer (path_prefix masked here).",
	}
	raw, err := json.MarshalIndent(api, "", "  ")
	if err != nil {
		d.ClientAPIJSON = err.Error()
		return
	}
	d.ClientAPIJSON = string(raw)
}

func maskSecret(s string) string {
	s = strings.TrimSpace(s)
	if s == "" {
		return "(empty)"
	}
	if len(s) <= 10 {
		return "(set, hidden)"
	}
	return s[:4] + "…" + s[len(s)-4:] + " (masked)"
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
