package limits

import (
	"context"
	"database/sql"
	"time"
)

// MonthWindow returns [start, end) for the UTC calendar month containing now.
func MonthWindow(now time.Time) (time.Time, time.Time) {
	now = now.UTC()
	start := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.UTC)
	end := start.AddDate(0, 1, 0)
	return start, end
}

// MonthUsageForDevice sums rx+tx deltas for a device in the current UTC month.
func MonthUsageForDevice(ctx context.Context, db *sql.DB, deviceID string, now time.Time) (uint64, error) {
	start, end := MonthWindow(now)
	var n uint64
	err := db.QueryRowContext(ctx, `
		SELECT COALESCE(SUM(s.rx_delta + s.tx_delta), 0)
		FROM peer_stats_samples s
		JOIN wireguard_peers p ON p.id = s.peer_id
		WHERE p.device_id = ?
			AND s.sampled_at >= ? AND s.sampled_at < ?`,
		deviceID, start, end,
	).Scan(&n)
	return n, err
}

// MonthUsageForUser sums rx+tx deltas for all of a user's devices in the current UTC month.
func MonthUsageForUser(ctx context.Context, db *sql.DB, userID string, now time.Time) (uint64, error) {
	start, end := MonthWindow(now)
	var n uint64
	err := db.QueryRowContext(ctx, `
		SELECT COALESCE(SUM(s.rx_delta + s.tx_delta), 0)
		FROM peer_stats_samples s
		JOIN wireguard_peers p ON p.id = s.peer_id
		JOIN devices d ON d.id = p.device_id
		WHERE d.user_id = ?
			AND s.sampled_at >= ? AND s.sampled_at < ?`,
		userID, start, end,
	).Scan(&n)
	return n, err
}
