package usage

import (
	"context"
	"database/sql"
	"fmt"
	"math"
	"time"
)

// sampleIntervalSec is the peer stats poll period used to turn deltas into MBps.
const sampleIntervalSec = 15.0

// Speed is throughput summary over a range (megabytes per second).
type Speed struct {
	Range               string  `json:"range"`
	DownloadMBps        float64 `json:"download_MBps"`
	UploadMBps          float64 `json:"upload_MBps"`
	ActiveDownloadMBps  float64 `json:"active_download_MBps"`
	ActiveUploadMBps    float64 `json:"active_upload_MBps"`
	MaxDownloadMBps     float64 `json:"max_download_MBps"`
	MaxUploadMBps       float64 `json:"max_upload_MBps"`
	CurrentDownloadMBps float64 `json:"current_download_MBps"`
	CurrentUploadMBps   float64 `json:"current_upload_MBps"`
	SampleSeconds       float64 `json:"sample_seconds"`
	ActiveDownSeconds   float64 `json:"active_download_seconds"`
	ActiveUpSeconds     float64 `json:"active_upload_seconds"`
	TotalRxBytes        uint64  `json:"total_rx_bytes"`
	TotalTxBytes        uint64  `json:"total_tx_bytes"`
}

// SpeedPoint is one chart bucket with avg and peak MBps.
type SpeedPoint struct {
	Date        string  `json:"date"`
	Label       string  `json:"label"`
	AvgDownMBps float64 `json:"avg_down_MBps"`
	AvgUpMBps   float64 `json:"avg_up_MBps"`
	MaxDownMBps float64 `json:"max_down_MBps"`
	MaxUpMBps   float64 `json:"max_up_MBps"`
}

// LoadSpeed computes wall-clock/active averages, peak sample rates, and latest sample rate.
// deviceID empty = fleet-wide.
func LoadSpeed(ctx context.Context, db *sql.DB, deviceID, rangeKey string, now time.Time) (Speed, error) {
	ar := ParseRange(rangeKey, now)
	out := Speed{Range: ar.Key}

	peerFilter := ""
	args := []any{ar.Since, ar.Until}
	if deviceID != "" {
		peerFilter = " AND p.device_id = ?"
		args = append(args, deviceID)
	}

	sumQ := fmt.Sprintf(`
		SELECT COALESCE(SUM(s.rx_delta),0), COALESCE(SUM(s.tx_delta),0)
		FROM peer_stats_samples s
		JOIN wireguard_peers p ON p.id = s.peer_id
		WHERE s.sampled_at >= ? AND s.sampled_at < ?%s`, peerFilter)
	if err := db.QueryRowContext(ctx, sumQ, args...).Scan(&out.TotalRxBytes, &out.TotalTxBytes); err != nil {
		return out, err
	}

	windowSec := ar.Until.Sub(ar.Since).Seconds()
	if windowSec < 1 {
		windowSec = 1
	}
	out.SampleSeconds = windowSec
	out.DownloadMBps = bytesToMBps(out.TotalRxBytes, windowSec)
	out.UploadMBps = bytesToMBps(out.TotalTxBytes, windowSec)

	activeQ := fmt.Sprintf(`
		SELECT
			COALESCE(SUM(CASE WHEN s.rx_delta > 0 THEN ? ELSE 0 END), 0),
			COALESCE(SUM(CASE WHEN s.tx_delta > 0 THEN ? ELSE 0 END), 0)
		FROM peer_stats_samples s
		JOIN wireguard_peers p ON p.id = s.peer_id
		WHERE s.sampled_at >= ? AND s.sampled_at < ?%s`, peerFilter)
	activeArgs := append([]any{sampleIntervalSec, sampleIntervalSec}, args...)
	var activeDown, activeUp float64
	if err := db.QueryRowContext(ctx, activeQ, activeArgs...).Scan(&activeDown, &activeUp); err != nil {
		return out, err
	}
	if activeDown > windowSec {
		activeDown = windowSec
	}
	if activeUp > windowSec {
		activeUp = windowSec
	}
	out.ActiveDownSeconds = activeDown
	out.ActiveUpSeconds = activeUp
	if activeDown > 0 {
		out.ActiveDownloadMBps = bytesToMBps(out.TotalRxBytes, activeDown)
	} else {
		out.ActiveDownloadMBps = out.DownloadMBps
	}
	if activeUp > 0 {
		out.ActiveUploadMBps = bytesToMBps(out.TotalTxBytes, activeUp)
	} else {
		out.ActiveUploadMBps = out.UploadMBps
	}

	maxQ := fmt.Sprintf(`
		SELECT
			COALESCE(MAX(s.rx_delta), 0),
			COALESCE(MAX(s.tx_delta), 0)
		FROM peer_stats_samples s
		JOIN wireguard_peers p ON p.id = s.peer_id
		WHERE s.sampled_at >= ? AND s.sampled_at < ?%s`, peerFilter)
	var maxRX, maxTX uint64
	if err := db.QueryRowContext(ctx, maxQ, args...).Scan(&maxRX, &maxTX); err != nil {
		return out, err
	}
	out.MaxDownloadMBps = bytesToMBps(maxRX, sampleIntervalSec)
	out.MaxUploadMBps = bytesToMBps(maxTX, sampleIntervalSec)

	var curRX, curTX uint64
	if deviceID != "" {
		err := db.QueryRowContext(ctx, `
			SELECT s.rx_delta, s.tx_delta
			FROM peer_stats_samples s
			JOIN wireguard_peers p ON p.id = s.peer_id
			WHERE p.device_id = ?
				AND s.sampled_at >= ? AND s.sampled_at < ?
			ORDER BY s.sampled_at DESC
			LIMIT 1`, deviceID, ar.Since, ar.Until).Scan(&curRX, &curTX)
		if err != nil && err != sql.ErrNoRows {
			return out, err
		}
	} else {
		err := db.QueryRowContext(ctx, `
			SELECT COALESCE(SUM(s.rx_delta),0), COALESCE(SUM(s.tx_delta),0)
			FROM peer_stats_samples s
			INNER JOIN (
				SELECT peer_id, MAX(sampled_at) AS mx
				FROM peer_stats_samples
				WHERE sampled_at >= GREATEST(?, UTC_TIMESTAMP(6) - INTERVAL 2 MINUTE)
					AND sampled_at < ?
				GROUP BY peer_id
			) last ON last.peer_id = s.peer_id AND last.mx = s.sampled_at`,
			ar.Since, ar.Until,
		).Scan(&curRX, &curTX)
		if err != nil {
			return out, err
		}
	}
	out.CurrentDownloadMBps = bytesToMBps(curRX, sampleIntervalSec)
	out.CurrentUploadMBps = bytesToMBps(curTX, sampleIntervalSec)

	return out, nil
}

// LoadSpeedSeries returns per-bucket average and peak MBps for charts.
func LoadSpeedSeries(ctx context.Context, db *sql.DB, deviceID, rangeKey string, now time.Time) ([]SpeedPoint, error) {
	ar := ParseRange(rangeKey, now)
	peerFilter := ""
	args := []any{ar.Since, ar.Until}
	if deviceID != "" {
		peerFilter = " AND p.device_id = ?"
		args = append(args, deviceID)
	}

	bucketExpr := "DATE_FORMAT(s.sampled_at, '%Y-%m-%d')"
	bucketSec := 24 * 3600.0
	switch {
	case ar.Hourly:
		bucketExpr = "DATE_FORMAT(s.sampled_at, '%Y-%m-%d %H:00:00')"
		bucketSec = 3600
	case ar.Monthly:
		bucketExpr = "DATE_FORMAT(s.sampled_at, '%Y-%m-01')"
		bucketSec = 30 * 24 * 3600.0
	}

	q := fmt.Sprintf(`
		SELECT CAST(%s AS CHAR) AS bucket,
			COALESCE(SUM(s.rx_delta),0), COALESCE(SUM(s.tx_delta),0),
			COALESCE(MAX(s.rx_delta),0), COALESCE(MAX(s.tx_delta),0)
		FROM peer_stats_samples s
		JOIN wireguard_peers p ON p.id = s.peer_id
		WHERE s.sampled_at >= ? AND s.sampled_at < ?%s
		GROUP BY bucket
		ORDER BY bucket`, bucketExpr, peerFilter)
	rows, err := db.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	byKey := map[string]SpeedPoint{}
	for rows.Next() {
		var key string
		var sumRX, sumTX, maxRX, maxTX uint64
		if err := rows.Scan(&key, &sumRX, &sumTX, &maxRX, &maxTX); err != nil {
			return nil, err
		}
		byKey[key] = SpeedPoint{
			Date:        key,
			Label:       labelFor(key, ar),
			AvgDownMBps: bytesToMBps(sumRX, bucketSec),
			AvgUpMBps:   bytesToMBps(sumTX, bucketSec),
			MaxDownMBps: bytesToMBps(maxRX, sampleIntervalSec),
			MaxUpMBps:   bytesToMBps(maxTX, sampleIntervalSec),
		}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	return fillSpeedBuckets(ar, byKey), nil
}

func fillSpeedBuckets(ar Range, byKey map[string]SpeedPoint) []SpeedPoint {
	out := make([]SpeedPoint, 0, 32)
	if ar.Hourly {
		for t := ar.Since; t.Before(ar.Until); t = t.Add(time.Hour) {
			key := t.Format("2006-01-02 15:00:00")
			if p, ok := byKey[key]; ok {
				out = append(out, p)
				continue
			}
			out = append(out, SpeedPoint{Date: key, Label: t.Format("15:04")})
		}
		return out
	}
	if ar.Monthly {
		for t := truncateMonth(ar.Since); t.Before(ar.Until); t = t.AddDate(0, 1, 0) {
			key := t.Format("2006-01-02")
			if p, ok := byKey[key]; ok {
				out = append(out, p)
				continue
			}
			out = append(out, SpeedPoint{Date: key, Label: t.Format("Jan")})
		}
		return out
	}
	for t := truncateDay(ar.Since); t.Before(ar.Until); t = t.AddDate(0, 0, 1) {
		key := t.Format("2006-01-02")
		if p, ok := byKey[key]; ok {
			out = append(out, p)
			continue
		}
		out = append(out, SpeedPoint{Date: key, Label: t.Weekday().String()[:3]})
	}
	return out
}

// bytesToMBps converts transferred bytes over a duration into megabytes/second (SI: 1 MB = 1e6 bytes).
func bytesToMBps(bytes uint64, seconds float64) float64 {
	if seconds <= 0 {
		return 0
	}
	mbps := float64(bytes) / seconds / 1_000_000.0
	return math.Round(mbps*100) / 100
}

// FormatMBps for admin templates.
func FormatMBps(v float64) string {
	if v <= 0 {
		return "0"
	}
	if v < 0.1 {
		return fmt.Sprintf("%.2f", v)
	}
	return fmt.Sprintf("%.1f", v)
}
