package admin

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"html/template"
	"net/http"
	"strings"
	"time"
)

type analyticsRange struct {
	Key   string
	Label string
	Since time.Time
	Hourly bool
}

type seriesPoint struct {
	Label string  `json:"label"`
	RX    float64 `json:"rx"`
	TX    float64 `json:"tx"`
	HS    int64   `json:"hs"`
}

type rankedItem struct {
	Label string
	Count int64
}

type analyticsView struct {
	RangeKey      string
	Ranges        []analyticsRange
	TotalRX       uint64
	TotalTX       uint64
	TotalRXHuman  string
	TotalTXHuman  string
	TotalHuman    string
	Handshakes    int64
	ActivePeers   int64
	Devices       int64
	SeriesJSON    template.JS
	Routes        []rankedItem
	Platforms     []rankedItem
	Versions      []rankedItem
	ClientCountry string
	ServerCountry string
	RouteLabel    string
}

func parseAnalyticsRange(r *http.Request) analyticsRange {
	key := r.URL.Query().Get("range")
	now := time.Now().UTC()
	switch key {
	case "24h":
		return analyticsRange{Key: "24h", Label: "Last 24 hours", Since: now.Add(-24 * time.Hour), Hourly: true}
	case "30d":
		return analyticsRange{Key: "30d", Label: "Last 30 days", Since: now.Add(-30 * 24 * time.Hour), Hourly: false}
	default:
		return analyticsRange{Key: "7d", Label: "Last 7 days", Since: now.Add(-7 * 24 * time.Hour), Hourly: false}
	}
}

func (h *Handler) loadAnalytics(r *http.Request, deviceID string) (analyticsView, error) {
	ar := parseAnalyticsRange(r)
	v := analyticsView{
		RangeKey: ar.Key,
		Ranges: []analyticsRange{
			{Key: "24h", Label: "24h"},
			{Key: "7d", Label: "7d"},
			{Key: "30d", Label: "30d"},
		},
	}

	peerFilter := ""
	args := []any{ar.Since}
	if deviceID != "" {
		peerFilter = " AND p.device_id = ?"
		args = append(args, deviceID)
	}

	q := fmt.Sprintf(`
		SELECT COALESCE(SUM(s.rx_delta),0), COALESCE(SUM(s.tx_delta),0), COALESCE(SUM(s.handshake_delta),0)
		FROM peer_stats_samples s
		JOIN wireguard_peers p ON p.id = s.peer_id
		WHERE s.sampled_at >= ?%s`, peerFilter)
	if err := h.DB.QueryRow(q, args...).Scan(&v.TotalRX, &v.TotalTX, &v.Handshakes); err != nil {
		return v, err
	}
	v.TotalRXHuman = humanBytes(v.TotalRX)
	v.TotalTXHuman = humanBytes(v.TotalTX)
	v.TotalHuman = humanBytes(v.TotalRX + v.TotalTX)

	bucket := "DATE(s.sampled_at)"
	labelFmt := "%Y-%m-%d"
	if ar.Hourly {
		bucket = "DATE_FORMAT(s.sampled_at, '%Y-%m-%d %H:00')"
		labelFmt = "%Y-%m-%d %H:00"
	}
	_ = labelFmt
	seriesQ := fmt.Sprintf(`
		SELECT CAST(%s AS CHAR) AS bucket,
			COALESCE(SUM(s.rx_delta),0), COALESCE(SUM(s.tx_delta),0), COALESCE(SUM(s.handshake_delta),0)
		FROM peer_stats_samples s
		JOIN wireguard_peers p ON p.id = s.peer_id
		WHERE s.sampled_at >= ?%s
		GROUP BY bucket
		ORDER BY bucket`, bucket, peerFilter)
	rows, err := h.DB.Query(seriesQ, args...)
	if err != nil {
		return v, err
	}
	defer rows.Close()
	var series []seriesPoint
	for rows.Next() {
		var label string
		var rx, tx uint64
		var hs int64
		if err := rows.Scan(&label, &rx, &tx, &hs); err != nil {
			return v, err
		}
		series = append(series, seriesPoint{
			Label: shortLabel(label, ar.Hourly),
			RX:    float64(rx) / (1024 * 1024), // MiB for chart
			TX:    float64(tx) / (1024 * 1024),
			HS:    hs,
		})
	}
	if series == nil {
		series = []seriesPoint{}
	}
	b, _ := json.Marshal(series)
	v.SeriesJSON = template.JS(b)

	activeQ := `
		SELECT COUNT(*) FROM wireguard_peers p
		WHERE p.last_handshake_at IS NOT NULL
			AND p.last_handshake_at >= UTC_TIMESTAMP(6) - INTERVAL 3 MINUTE`
	activeArgs := []any{}
	if deviceID != "" {
		activeQ += " AND p.device_id = ?"
		activeArgs = append(activeArgs, deviceID)
	}
	_ = h.DB.QueryRow(activeQ, activeArgs...).Scan(&v.ActivePeers)

	if deviceID == "" {
		_ = h.DB.QueryRow(`SELECT COUNT(*) FROM devices`).Scan(&v.Devices)
		v.Platforms, _ = h.rankedQuery(`
			SELECT COALESCE(NULLIF(platform,''), 'unknown'), COUNT(*)
			FROM devices GROUP BY 1 ORDER BY 2 DESC`)
		v.Versions, _ = h.rankedQuery(`
			SELECT COALESCE(NULLIF(app_version,''), 'unknown') AS ver, COUNT(*) AS c
			FROM devices
			GROUP BY ver
			ORDER BY c DESC
			LIMIT 8`)
		v.Routes, _ = h.rankedQuery(`
			SELECT CONCAT(
				COALESCE(NULLIF(d.last_client_country,''), '?'),
				' → ',
				COALESCE(NULLIF(s.country_code,''), '?')
			) AS route, COUNT(*) AS c
			FROM devices d
			JOIN wireguard_peers p ON p.device_id = d.id
			JOIN vpn_servers s ON s.id = p.server_id
			GROUP BY route
			ORDER BY c DESC
			LIMIT 10`)
	} else {
		v.Devices = 1
		var client, server sql.NullString
		_ = h.DB.QueryRow(`
			SELECT d.last_client_country, s.country_code
			FROM devices d
			LEFT JOIN wireguard_peers p ON p.device_id = d.id
			LEFT JOIN vpn_servers s ON s.id = p.server_id
			WHERE d.id = ?
			ORDER BY p.updated_at DESC
			LIMIT 1`, deviceID).Scan(&client, &server)
		v.ClientCountry = nullStrOr(client, "?")
		v.ServerCountry = nullStrOr(server, "?")
		v.RouteLabel = v.ClientCountry + " → " + v.ServerCountry
		var platform, version string
		_ = h.DB.QueryRow(`SELECT platform, COALESCE(app_version,'') FROM devices WHERE id = ?`, deviceID).
			Scan(&platform, &version)
		if platform != "" {
			v.Platforms = []rankedItem{{Label: platform, Count: 1}}
		}
		if version != "" {
			v.Versions = []rankedItem{{Label: version, Count: 1}}
		}
	}

	return v, nil
}

func (h *Handler) rankedQuery(q string, args ...any) ([]rankedItem, error) {
	rows, err := h.DB.Query(q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []rankedItem
	for rows.Next() {
		var it rankedItem
		if err := rows.Scan(&it.Label, &it.Count); err != nil {
			return nil, err
		}
		out = append(out, it)
	}
	return out, rows.Err()
}

func shortLabel(label string, hourly bool) string {
	label = strings.TrimSpace(label)
	if hourly {
		// "2026-11-17 14:00" → "14:00"
		if len(label) >= 16 {
			return label[11:16]
		}
		return label
	}
	// "2026-11-17" → "11-17"
	if len(label) >= 10 {
		return label[5:10]
	}
	return label
}

func nullStrOr(ns sql.NullString, fallback string) string {
	if ns.Valid && ns.String != "" {
		return ns.String
	}
	return fallback
}
