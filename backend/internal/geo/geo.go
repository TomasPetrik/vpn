package geo

import (
	"log/slog"
	"net"
	"sync"

	"github.com/oschwald/geoip2-golang"
)

// Lookup maps public IPs to ISO country codes via GeoLite2 Country.
type Lookup struct {
	mu   sync.RWMutex
	db   *geoip2.Reader
	path string
	log  *slog.Logger
}

func Open(path string, log *slog.Logger) *Lookup {
	l := &Lookup{path: path, log: log}
	if path == "" {
		return l
	}
	db, err := geoip2.Open(path)
	if err != nil {
		if log != nil {
			log.Warn("geoip unavailable", "path", path, "err", err)
		}
		return l
	}
	l.db = db
	if log != nil {
		log.Info("geoip loaded", "path", path)
	}
	return l
}

func (l *Lookup) Close() {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.db != nil {
		_ = l.db.Close()
		l.db = nil
	}
}

// Country returns ISO 3166-1 alpha-2 for ip, or "" if unknown / private / unavailable.
func (l *Lookup) Country(ipStr string) string {
	if l == nil || ipStr == "" {
		return ""
	}
	ip := net.ParseIP(ipStr)
	if ip == nil || ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() || ip.IsUnspecified() {
		return ""
	}
	l.mu.RLock()
	db := l.db
	l.mu.RUnlock()
	if db == nil {
		return ""
	}
	rec, err := db.Country(ip)
	if err != nil || rec == nil || rec.Country.IsoCode == "" {
		return ""
	}
	return rec.Country.IsoCode
}
