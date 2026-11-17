package peer

import (
	"context"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"strings"

	"github.com/TomasPetrik/vpn/backend/internal/config"
	"github.com/google/uuid"
)

var ErrNotFound = errors.New("not_found")
var ErrInvalidKey = errors.New("invalid_public_key")

type Service struct {
	DB  *sql.DB
	Cfg *config.Config
}

type ConfigResponse struct {
	PeerID    string         `json:"peer_id"`
	Server    map[string]any `json:"server"`
	Interface map[string]any `json:"interface"`
	Peer      map[string]any `json:"peer"`
	Transport map[string]any `json:"transport"`
}

func (s *Service) EnsureServer(ctx context.Context) error {
	var n int
	if err := s.DB.QueryRowContext(ctx, `SELECT COUNT(*) FROM vpn_servers WHERE id = ?`, s.Cfg.ServerID).Scan(&n); err != nil {
		return err
	}
	ips, err := json.Marshal(s.Cfg.ServerPublicIPs)
	if err != nil {
		return err
	}
	if n == 0 {
		_, err = s.DB.ExecContext(ctx, `
			INSERT INTO vpn_servers (
				id, name, country_code, city, public_host, public_ips,
				wg_interface, wg_public_key, tunnel_cidr, is_active
			) VALUES (?, ?, ?, NULLIF(?, ''), ?, ?, ?, ?, ?, 1)`,
			s.Cfg.ServerID, s.Cfg.ServerName, s.Cfg.ServerCountry, s.Cfg.ServerCity,
			strings.TrimPrefix(strings.TrimPrefix(s.Cfg.PublicBaseURL, "https://"), "http://"),
			ips, s.Cfg.WGInterface, s.Cfg.WGPublicKey, s.Cfg.WGTunnelCIDR,
		)
		return err
	}
	_, err = s.DB.ExecContext(ctx, `
		UPDATE vpn_servers SET
			name = ?, country_code = ?, city = NULLIF(?, ''),
			public_host = ?, public_ips = ?, wg_interface = ?,
			wg_public_key = ?, tunnel_cidr = ?, is_active = 1
		WHERE id = ?`,
		s.Cfg.ServerName, s.Cfg.ServerCountry, s.Cfg.ServerCity,
		strings.TrimPrefix(strings.TrimPrefix(s.Cfg.PublicBaseURL, "https://"), "http://"),
		ips, s.Cfg.WGInterface, s.Cfg.WGPublicKey, s.Cfg.WGTunnelCIDR, s.Cfg.ServerID,
	)
	return err
}

func (s *Service) Upsert(ctx context.Context, deviceID, publicKey string) (ConfigResponse, error) {
	key, err := normalizePublicKey(publicKey)
	if err != nil {
		return ConfigResponse{}, err
	}
	if err := s.EnsureServer(ctx); err != nil {
		return ConfigResponse{}, err
	}

	tx, err := s.DB.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		return ConfigResponse{}, err
	}
	defer func() { _ = tx.Rollback() }()

	var peerID string
	var tunnelIP uint32
	err = tx.QueryRowContext(ctx, `
		SELECT id, tunnel_ipv4 FROM wireguard_peers
		WHERE device_id = ? AND server_id = ?`, deviceID, s.Cfg.ServerID).
		Scan(&peerID, &tunnelIP)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return ConfigResponse{}, err
	}

	if peerID == "" {
		tunnelIP, err = allocateIPv4(ctx, tx, s.Cfg.ServerID, s.Cfg.WGTunnelCIDR)
		if err != nil {
			return ConfigResponse{}, err
		}
		peerID = uuid.Must(uuid.NewV7()).String()
		_, err = tx.ExecContext(ctx, `
			INSERT INTO wireguard_peers (id, device_id, server_id, public_key, tunnel_ipv4)
			VALUES (?, ?, ?, ?, ?)`, peerID, deviceID, s.Cfg.ServerID, key, tunnelIP)
		if err != nil {
			return ConfigResponse{}, err
		}
	} else {
		_, err = tx.ExecContext(ctx, `
			UPDATE wireguard_peers SET public_key = ?, updated_at = UTC_TIMESTAMP(6)
			WHERE id = ?`, key, peerID)
		if err != nil {
			return ConfigResponse{}, err
		}
	}

	if err := tx.Commit(); err != nil {
		return ConfigResponse{}, err
	}
	return s.buildConfig(peerID, tunnelIP), nil
}

func (s *Service) Get(ctx context.Context, deviceID string) (ConfigResponse, error) {
	var peerID string
	var tunnelIP uint32
	err := s.DB.QueryRowContext(ctx, `
		SELECT id, tunnel_ipv4 FROM wireguard_peers
		WHERE device_id = ? AND server_id = ?`, deviceID, s.Cfg.ServerID).
		Scan(&peerID, &tunnelIP)
	if errors.Is(err, sql.ErrNoRows) {
		return ConfigResponse{}, ErrNotFound
	}
	if err != nil {
		return ConfigResponse{}, err
	}
	return s.buildConfig(peerID, tunnelIP), nil
}

func (s *Service) buildConfig(peerID string, tunnelIP uint32) ConfigResponse {
	ip := net.IPv4(byte(tunnelIP>>24), byte(tunnelIP>>16), byte(tunnelIP>>8), byte(tunnelIP)).String()
	excluded := make([]string, 0, len(s.Cfg.ServerPublicIPs))
	for _, p := range s.Cfg.ServerPublicIPs {
		excluded = append(excluded, p+"/32")
	}
	city := any(nil)
	if s.Cfg.ServerCity != "" {
		city = s.Cfg.ServerCity
	}
	return ConfigResponse{
		PeerID: peerID,
		Server: map[string]any{
			"id":           s.Cfg.ServerID,
			"name":         s.Cfg.ServerName,
			"country_code": s.Cfg.ServerCountry,
			"city":         city,
		},
		Interface: map[string]any{
			"addresses": []string{ip + "/32"},
			"dns":       s.Cfg.VPNDNS,
			"mtu":       s.Cfg.VPNMTU,
		},
		Peer: map[string]any{
			"public_key":            s.Cfg.WGPublicKey,
			"allowed_ips":           []string{"0.0.0.0/0", "::/0"},
			"excluded_ips":          excluded,
			"persistent_keepalive":  25,
		},
		Transport: map[string]any{
			"type":        "wstunnel",
			"url":         s.Cfg.WstunnelURL,
			"path_prefix": s.Cfg.WstunnelPathPref,
			"remote":      s.Cfg.WGRemote,
			"server_ips":  s.Cfg.ServerPublicIPs,
		},
	}
}

func normalizePublicKey(raw string) (string, error) {
	key := strings.TrimSpace(raw)
	decoded, err := base64.StdEncoding.DecodeString(key)
	if err != nil || len(decoded) != 32 {
		return "", ErrInvalidKey
	}
	return base64.StdEncoding.EncodeToString(decoded), nil
}

func allocateIPv4(ctx context.Context, tx *sql.Tx, serverID, cidr string) (uint32, error) {
	_, network, err := net.ParseCIDR(cidr)
	if err != nil {
		return 0, fmt.Errorf("invalid tunnel cidr: %w", err)
	}
	ones, bits := network.Mask.Size()
	if bits != 32 {
		return 0, fmt.Errorf("only IPv4 tunnel cidr supported")
	}
	base := ipv4ToUint32(network.IP.To4())
	// host 0 = network, 1 = server; clients start at 2
	start := base + 2
	maxHosts := uint32(1) << uint(32-ones)
	end := base + maxHosts - 2 // reserve broadcast

	rows, err := tx.QueryContext(ctx, `SELECT tunnel_ipv4 FROM wireguard_peers WHERE server_id = ?`, serverID)
	if err != nil {
		return 0, err
	}
	defer rows.Close()
	used := map[uint32]struct{}{}
	for rows.Next() {
		var v uint32
		if err := rows.Scan(&v); err != nil {
			return 0, err
		}
		used[v] = struct{}{}
	}
	if err := rows.Err(); err != nil {
		return 0, err
	}
	for ip := start; ip <= end; ip++ {
		if _, ok := used[ip]; !ok {
			return ip, nil
		}
	}
	return 0, fmt.Errorf("tunnel address pool exhausted")
}

func ipv4ToUint32(ip net.IP) uint32 {
	ip = ip.To4()
	return uint32(ip[0])<<24 | uint32(ip[1])<<16 | uint32(ip[2])<<8 | uint32(ip[3])
}
