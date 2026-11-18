package usage

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"
)

// Range describes a bounded analytics window.
type Range struct {
	Key    string
	Since  time.Time
	Until  time.Time
	Hourly bool
}

// Point is one chart bucket (hour or day).
type Point struct {
	Date            string `json:"date"`
	Label           string `json:"label"`
	RxBytes         uint64 `json:"rx_bytes"`
	TxBytes         uint64 `json:"tx_bytes"`
	HandshakeDelta  int64  `json:"handshake_delta"`
}

// Series is a zero-filled transfer timeline for a device (or all devices).
type Series struct {
	Range           string  `json:"range"`
	Points          []Point `json:"points"`
	TotalRxBytes    uint64  `json:"total_rx_bytes"`
	TotalTxBytes    uint64  `json:"total_tx_bytes"`
	TotalHandshakes int64   `json:"total_handshakes"`
}

// ParseRange maps API/admin range keys onto a UTC window ending at now.
func ParseRange(key string, now time.Time) Range {
	now = now.UTC()
	switch strings.ToLower(strings.TrimSpace(key)) {
	case "24h", "today":
		until := now.Truncate(time.Hour).Add(time.Hour)
		return Range{
			Key:    "24h",
			Since:  until.Add(-24 * time.Hour),
			Until:  until,
			Hourly: true,
		}
	case "30d":
		until := truncateDay(now).Add(24 * time.Hour)
		return Range{
			Key:   "30d",
			Since: until.Add(-30 * 24 * time.Hour),
			Until: until,
		}
	case "all":
		until := truncateDay(now).Add(24 * time.Hour)
		return Range{
			Key:   "all",
			Since: until.Add(-365 * 24 * time.Hour), // daily buckets; samples retained 365d
			Until: until,
		}
	default: // 7d
		until := truncateDay(now).Add(24 * time.Hour)
		return Range{
			Key:   "7d",
			Since: until.Add(-7 * 24 * time.Hour),
			Until: until,
		}
	}
}

// Load aggregates peer_stats_samples into a continuous series.
// When deviceID is empty, all peers are included.
func Load(ctx context.Context, db *sql.DB, deviceID, rangeKey string, now time.Time) (Series, error) {
	ar := ParseRange(rangeKey, now)
	out := Series{Range: ar.Key, Points: []Point{}}

	peerFilter := ""
	args := []any{ar.Since, ar.Until}
	if deviceID != "" {
		peerFilter = " AND p.device_id = ?"
		args = append(args, deviceID)
	}

	sumQ := fmt.Sprintf(`
		SELECT COALESCE(SUM(s.rx_delta),0), COALESCE(SUM(s.tx_delta),0), COALESCE(SUM(s.handshake_delta),0)
		FROM peer_stats_samples s
		JOIN wireguard_peers p ON p.id = s.peer_id
		WHERE s.sampled_at >= ? AND s.sampled_at < ?%s`, peerFilter)
	if err := db.QueryRowContext(ctx, sumQ, args...).Scan(
		&out.TotalRxBytes, &out.TotalTxBytes, &out.TotalHandshakes,
	); err != nil {
		return out, err
	}

	bucketExpr := "DATE_FORMAT(s.sampled_at, '%Y-%m-%d')"
	if ar.Hourly {
		bucketExpr = "DATE_FORMAT(s.sampled_at, '%Y-%m-%d %H:00:00')"
	}
	seriesQ := fmt.Sprintf(`
		SELECT CAST(%s AS CHAR) AS bucket,
			COALESCE(SUM(s.rx_delta),0), COALESCE(SUM(s.tx_delta),0), COALESCE(SUM(s.handshake_delta),0)
		FROM peer_stats_samples s
		JOIN wireguard_peers p ON p.id = s.peer_id
		WHERE s.sampled_at >= ? AND s.sampled_at < ?%s
		GROUP BY bucket
		ORDER BY bucket`, bucketExpr, peerFilter)
	rows, err := db.QueryContext(ctx, seriesQ, args...)
	if err != nil {
		return out, err
	}
	defer rows.Close()

	byKey := map[string]Point{}
	for rows.Next() {
		var key string
		var rx, tx uint64
		var hs int64
		if err := rows.Scan(&key, &rx, &tx, &hs); err != nil {
			return out, err
		}
		byKey[key] = Point{
			Date:           key,
			Label:          labelFor(key, ar.Hourly),
			RxBytes:        rx,
			TxBytes:        tx,
			HandshakeDelta: hs,
		}
	}
	if err := rows.Err(); err != nil {
		return out, err
	}

	out.Points = fillBuckets(ar, byKey)
	return out, nil
}

func fillBuckets(ar Range, byKey map[string]Point) []Point {
	out := make([]Point, 0, 32)
	if ar.Hourly {
		for t := ar.Since; t.Before(ar.Until); t = t.Add(time.Hour) {
			key := t.Format("2006-01-02 15:04:05")
			if p, ok := byKey[key]; ok {
				out = append(out, p)
				continue
			}
			// MySQL DATE_FORMAT uses "%Y-%m-%d %H:00:00"
			key = t.Format("2006-01-02 15:00:00")
			if p, ok := byKey[key]; ok {
				out = append(out, p)
				continue
			}
			out = append(out, Point{
				Date:  key,
				Label: t.Format("15:04"),
			})
		}
		return out
	}

	for t := truncateDay(ar.Since); t.Before(ar.Until); t = t.AddDate(0, 0, 1) {
		key := t.Format("2006-01-02")
		if p, ok := byKey[key]; ok {
			out = append(out, p)
			continue
		}
		out = append(out, Point{
			Date:  key,
			Label: t.Weekday().String()[:3],
		})
	}
	return out
}

func truncateDay(t time.Time) time.Time {
	t = t.UTC()
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC)
}

func labelFor(key string, hourly bool) string {
	key = strings.TrimSpace(key)
	if hourly {
		if len(key) >= 16 {
			return key[11:16]
		}
		return key
	}
	if t, err := time.ParseInLocation("2006-01-02", key, time.UTC); err == nil {
		return t.Weekday().String()[:3]
	}
	if len(key) >= 10 {
		if t, err := time.ParseInLocation("2006-01-02", key[:10], time.UTC); err == nil {
			return t.Weekday().String()[:3]
		}
		return key[5:10]
	}
	return key
}
