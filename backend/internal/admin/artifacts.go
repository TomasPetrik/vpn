package admin

import (
	"fmt"
	"os"
	"regexp"
	"strings"
)

// artifactPanel is one expandable block on the device detail page.
type artifactPanel struct {
	Title   string
	Path    string
	Role    string
	Content string
	Source  string // "generated" | "file" | "omitted"
}

func (h *Handler) buildArtifactPanels(d *deviceDetailView) []artifactPanel {
	panels := make([]artifactPanel, 0, 16)

	if d.HasPeer {
		panels = append(panels,
			artifactPanel{
				Title:   "Server peer stanza (→ " + d.WGInterface + ")",
				Path:    "generated · MySQL wireguard_peers",
				Role:    "What would be applied to the server WG interface for this device",
				Content: d.ServerPeerStanza,
				Source:  "generated",
			},
			artifactPanel{
				Title:   "Client .conf preview (device-side)",
				Path:    "generated · API config (no PrivateKey)",
				Role:    "Shape WireGuardKit will use in step 4",
				Content: d.ClientConfPreview,
				Source:  "generated",
			},
			artifactPanel{
				Title:   "API peer JSON",
				Path:    "GET/PUT /api/v1/devices/me/peer",
				Role:    "Exact response shape the app receives (secrets masked)",
				Content: d.ClientAPIJSON,
				Source:  "generated",
			},
			artifactPanel{
				Title:   "MySQL peer row",
				Path:    "wireguard_peers + vpn_servers",
				Role:    "DB source of truth for this device’s peer",
				Content: fmt.Sprintf(
					"peer_id=%s\n"+
						"device_id=%s\n"+
						"server_id=%s (%s)\n"+
						"wg_interface=%s\n"+
						"tunnel_cidr=%s\n"+
						"client_public_key=%s\n"+
						"server_public_key=%s\n"+
						"tunnel_ipv4=%s\n"+
						"last_handshake=%s\n"+
						"rx_bytes=%s (%s)\n"+
						"tx_bytes=%s (%s)\n"+
						"stats_updated=%s\n"+
						"peer_created=%s\n"+
						"wg_driver=%s\n",
					d.PeerID, d.ID, d.ServerID, d.ServerName, d.WGInterface, d.TunnelCIDR,
					d.PeerPublicKey, d.ServerPublicKey, d.TunnelIPv4,
					d.LastHandshake, d.RxBytes, d.RxHuman, d.TxBytes, d.TxHuman,
					d.StatsUpdated, d.PeerCreated, d.WGDriver,
				),
				Source: "generated",
			},
		)
	}

	panels = append(panels,
		readFilePanel(
			"WireGuard interface config (wg1)",
			"/var/lib/vpn-api/inspect/wg1.conf",
			"App WG interface only — peers are not stored in this file",
			false,
		),
		readFilePanel(
			"Live kernel config (wg show conf wg1)",
			"/var/lib/vpn-api/inspect/wg1.live.conf",
			"Snapshot of running wg1 (refreshed on vpn-api deploy)",
			false,
		),
		readFilePanel(
			"Live kernel status (wg show wg1)",
			"/var/lib/vpn-api/inspect/wg1.show.txt",
			"Handshake / transfer counters from kernel (if any)",
			false,
		),
		readFilePanel(
			"vpn-api environment",
			"/etc/vpn-api/env",
			"Runtime env for vpn-api — secrets redacted",
			true,
		),
		readFilePanel(
			"wstunnel-app restrictions",
			"/etc/wstunnel-app/restrictions.yaml",
			"UDP allowlist for app transport → 127.0.0.1:51821",
			false,
		),
		readFilePanel(
			"vpn-api systemd unit",
			"/etc/systemd/system/vpn-api.service",
			"Service definition for the API binary",
			false,
		),
		readFilePanel(
			"wstunnel-app systemd unit",
			"/etc/systemd/system/wstunnel-app.service",
			"Service definition for app wstunnel (127.0.0.1:8081)",
			false,
		),
		readFilePanel(
			"Apache vhost (vpn.radarcut.com TLS)",
			"/etc/apache2/sites-available/vpn.radarcut.com-le-ssl.conf",
			"Proxies /api, /admin, /healthz and the WS path",
			true, // may contain secret WS path
		),
		artifactPanel{
			Title:   "Owner WireGuard (wg0)",
			Path:    "/etc/wireguard/wg0.conf",
			Role:    "Owner MacBook VPN — intentionally not shown",
			Content: "# Omitted on purpose.\n# This is the owner’s personal VPN (wg0), separate from PetrikVPN (wg1).\n# Do not edit it from the app admin UI.\n",
			Source:  "omitted",
		},
		artifactPanel{
			Title:   "wstunnel path prefix secret",
			Path:    "/root/vpn-setup/wstunnel-app-path-prefix",
			Role:    "Secret URL path for WSS — value masked",
			Content: "WSTUNNEL_PATH_PREFIX=" + maskSecret(envOrCfgPathPref(h)) + "\n",
			Source:  "omitted",
		},
	)

	return panels
}

func envOrCfgPathPref(h *Handler) string {
	if h != nil && h.Cfg != nil {
		return h.Cfg.WstunnelPathPref
	}
	return ""
}

func readFilePanel(title, path, role string, redact bool) artifactPanel {
	raw, err := os.ReadFile(path)
	if err != nil {
		return artifactPanel{
			Title:   title,
			Path:    path,
			Role:    role,
			Content: "# unreadable: " + err.Error() + "\n",
			Source:  "file",
		}
	}
	content := string(raw)
	if redact {
		content = redactSecrets(content)
	}
	// Soft-mask long path-like tokens in apache/env even if redact flag set.
	if strings.Contains(path, "apache") || strings.Contains(path, "env") {
		content = redactPathLikeSegments(content)
	}
	return artifactPanel{
		Title:   title,
		Path:    path,
		Role:    role,
		Content: content,
		Source:  "file",
	}
}

var (
	envSecretLine = regexp.MustCompile(`(?m)^([A-Za-z0-9_]*?(?:KEY|SECRET|PASSWORD|TOKEN|DSN|PREFIX)[A-Za-z0-9_]*)=(.*)$`)
	// Matches /<long-token> path segments often used as wstunnel prefixes.
	longPathSeg = regexp.MustCompile(`(/[A-Za-z0-9_-]{16,})`)
)

func redactSecrets(s string) string {
	return envSecretLine.ReplaceAllStringFunc(s, func(line string) string {
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			return line
		}
		return parts[0] + "=" + maskSecret(parts[1])
	})
}

func redactPathLikeSegments(s string) string {
	return longPathSeg.ReplaceAllStringFunc(s, func(seg string) string {
		body := strings.TrimPrefix(seg, "/")
		if len(body) < 16 {
			return seg
		}
		return "/" + maskSecret(body)
	})
}
