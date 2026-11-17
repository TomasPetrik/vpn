package peer

import (
	"context"
	"log/slog"
	"time"

)

// SyncStats copies live WireGuard peer counters from the kernel into MySQL.
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
		var err error
		if st.HasHandshake {
			_, err = s.DB.ExecContext(ctx, `
				UPDATE wireguard_peers
				SET rx_bytes = ?, tx_bytes = ?,
					last_handshake_at = ?, stats_updated_at = ?
				WHERE public_key = ? AND server_id = ?`,
				st.RxBytes, st.TxBytes, st.LastHandshake, now,
				st.PublicKey, s.Cfg.ServerID,
			)
		} else {
			_, err = s.DB.ExecContext(ctx, `
				UPDATE wireguard_peers
				SET rx_bytes = ?, tx_bytes = ?, stats_updated_at = ?
				WHERE public_key = ? AND server_id = ?`,
				st.RxBytes, st.TxBytes, now,
				st.PublicKey, s.Cfg.ServerID,
			)
		}
		if err != nil {
			return updated, err
		}
		updated++
	}
	return updated, nil
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
