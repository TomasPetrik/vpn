package peer

import (
	"context"
	"database/sql"
	"log/slog"
	"time"
)

// SyncStats copies live WireGuard peer counters from the kernel into MySQL,
// records deltas into peer_stats_samples, and bumps handshake_count when the
// kernel last-handshake timestamp moves.
func (s *Service) SyncStats(ctx context.Context) (int, error) {
	if s.WG == nil {
		return 0, nil
	}
	stats, err := s.WG.PeerStats()
	if err != nil {
		return 0, err
	}
	now := time.Now().UTC()
	updated := 0
	for _, st := range stats {
		var (
			peerID                                    string
			prevRX, prevTX                            uint64
			prevHS                                    sql.NullTime
			handshakeCount                            uint64
		)
		err := s.DB.QueryRowContext(ctx, `
			SELECT id, rx_bytes, tx_bytes, last_handshake_at, handshake_count
			FROM wireguard_peers
			WHERE public_key = ? AND server_id = ?`,
			st.PublicKey, s.Cfg.ServerID,
		).Scan(&peerID, &prevRX, &prevTX, &prevHS, &handshakeCount)
		if err == sql.ErrNoRows {
			continue
		}
		if err != nil {
			return updated, err
		}

		rxDelta := deltaBytes(prevRX, st.RxBytes)
		txDelta := deltaBytes(prevTX, st.TxBytes)
		hsDelta := uint8(0)
		var hs any
		if st.HasHandshake {
			hs = st.LastHandshake
			if !prevHS.Valid || !prevHS.Time.Equal(st.LastHandshake) {
				hsDelta = 1
				handshakeCount++
			}
		} else {
			hs = nil
		}

		_, err = s.DB.ExecContext(ctx, `
			UPDATE wireguard_peers
			SET rx_bytes = ?, tx_bytes = ?,
				last_handshake_at = COALESCE(?, last_handshake_at),
				handshake_count = ?,
				stats_updated_at = ?
			WHERE id = ?`,
			st.RxBytes, st.TxBytes, hs, handshakeCount, now, peerID,
		)
		if err != nil {
			return updated, err
		}

		_, err = s.DB.ExecContext(ctx, `
			INSERT INTO peer_stats_samples
				(peer_id, sampled_at, rx_bytes, tx_bytes, rx_delta, tx_delta, handshake_delta)
			VALUES (?, ?, ?, ?, ?, ?, ?)`,
			peerID, now, st.RxBytes, st.TxBytes, rxDelta, txDelta, hsDelta,
		)
		if err != nil {
			return updated, err
		}
		updated++
	}

	_, _ = s.DB.ExecContext(ctx, `
		DELETE FROM peer_stats_samples
		WHERE sampled_at < UTC_TIMESTAMP(6) - INTERVAL 30 DAY`)

	return updated, nil
}

func deltaBytes(prev, cur uint64) uint64 {
	if cur >= prev {
		return cur - prev
	}
	// Counter reset (interface bounce) — treat current as the delta.
	return cur
}

// StartStatsLoop periodically syncs peer stats until ctx is cancelled.
func (s *Service) StartStatsLoop(ctx context.Context, log *slog.Logger, every time.Duration) {
	if every <= 0 {
		every = 15 * time.Second
	}
	go func() {
		t := time.NewTicker(every)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				n, err := s.SyncStats(ctx)
				if err != nil {
					log.Warn("peer stats sync", "err", err)
					continue
				}
				if n > 0 {
					log.Debug("peer stats sync", "peers", n)
				}
			}
		}
	}()
}
