package admin

import (
	"database/sql"
	"encoding/json"
	"html/template"
	"net/http"
	"time"

	"github.com/TomasPetrik/vpn/backend/internal/usage"
)

type analyticsRange struct {
	Key   string
	Label string
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

func (h *Handler) loadAnalytics(r *http.Request, deviceID string) (analyticsView, error) {
	rangeKey := r.URL.Query().Get("range")
	series, err := usage.Load(r.Context(), h.DB, deviceID, rangeKey, time.Now().UTC())
	if err != nil {
		return analyticsView{}, err
	}
	v := analyticsView{
		RangeKey: series.Range,
		Ranges: []analyticsRange{
			{Key: "24h", Label: "24h"},
			{Key: "7d", Label: "7d"},
			{Key: "30d", Label: "30d"},
		},
		TotalRX:      series.TotalRxBytes,
		TotalTX:      series.TotalTxBytes,
		Handshakes:   series.TotalHandshakes,
		TotalRXHuman: humanBytes(series.TotalRxBytes),
		TotalTXHuman: humanBytes(series.TotalTxBytes),
		TotalHuman:   humanBytes(series.TotalRxBytes + series.TotalTxBytes),
	}

	chart := make([]seriesPoint, 0, len(series.Points))
	for _, p := range series.Points {
		chart = append(chart, seriesPoint{
			Label: p.Label,
			RX:    float64(p.RxBytes) / (1024 * 1024), // MiB for chart
			TX:    float64(p.TxBytes) / (1024 * 1024),
			HS:    p.HandshakeDelta,
		})
	}
	b, _ := json.Marshal(chart)
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

func nullStrOr(ns sql.NullString, fallback string) string {
	if ns.Valid && ns.String != "" {
		return ns.String
	}
	return fallback
}
