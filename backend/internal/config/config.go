package config

import (
	"fmt"
	"net"
	"os"
	"strconv"
	"strings"
)

type Config struct {
	HTTPAddr         string
	DatabaseDSN      string
	PublicBaseURL    string
	DeviceIDHMACKey  []byte
	WGInterface      string
	WGTunnelCIDR     string
	WGRemote         string
	WGDriver         string // "netlink" | "fake"
	WstunnelURL      string
	WstunnelPathPref string
	ServerPublicIPs  []string
	VPNDNS           []string
	VPNMTU           int
	ServerName       string
	ServerCountry    string
	ServerCity       string
	ServerID         string
	WGPublicKey      string
	GeoIPCountryDB   string
}

func Load() (Config, error) {
	c := Config{
		HTTPAddr:         getenv("HTTP_ADDR", "127.0.0.1:8090"),
		DatabaseDSN:      os.Getenv("DATABASE_DSN"),
		PublicBaseURL:    getenv("PUBLIC_BASE_URL", "https://vpn.radarcut.com"),
		WGInterface:      getenv("WG_INTERFACE", "wg1"),
		WGTunnelCIDR:     getenv("WG_TUNNEL_CIDR", "10.201.0.0/16"),
		WGRemote:         getenv("WG_REMOTE", "127.0.0.1:51821"),
		WGDriver:         getenv("WG_DRIVER", "fake"),
		WstunnelURL:      getenv("WSTUNNEL_URL", "wss://vpn.radarcut.com"),
		WstunnelPathPref: os.Getenv("WSTUNNEL_PATH_PREFIX"),
		ServerPublicIPs:  splitCSV(getenv("SERVER_PUBLIC_IPS", "72.61.158.103")),
		VPNDNS:           splitCSV(getenv("VPN_DNS", "1.1.1.1,1.0.0.1")),
		VPNMTU:           getenvInt("VPN_MTU", 1280),
		ServerName:       getenv("SERVER_NAME", "Germany"),
		ServerCountry:    getenv("SERVER_COUNTRY_CODE", "DE"),
		ServerCity:       os.Getenv("SERVER_CITY"),
		ServerID:         getenv("SERVER_ID", "01900000-0000-7000-8000-000000000001"),
		WGPublicKey:      getenv("WG_PUBLIC_KEY", "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="),
		GeoIPCountryDB:   getenv("GEOIP_COUNTRY_DB", "/var/lib/vpn-api/GeoLite2-Country.mmdb"),
	}
	key := os.Getenv("DEVICE_ID_HMAC_KEY")
	if key == "" {
		return Config{}, fmt.Errorf("DEVICE_ID_HMAC_KEY is required")
	}
	c.DeviceIDHMACKey = []byte(key)
	if c.DatabaseDSN == "" {
		return Config{}, fmt.Errorf("DATABASE_DSN is required")
	}
	for _, ip := range c.ServerPublicIPs {
		if net.ParseIP(ip) == nil {
			return Config{}, fmt.Errorf("invalid SERVER_PUBLIC_IPS entry: %q", ip)
		}
	}
	return c, nil
}

func getenv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func getenvInt(k string, def int) int {
	v := os.Getenv(k)
	if v == "" {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return def
	}
	return n
}

func splitCSV(s string) []string {
	parts := strings.Split(s, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}
