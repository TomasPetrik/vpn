package maintenance

import (
	"context"
	"database/sql"
	"fmt"
	"log/slog"
	"strings"
	"time"

	wgpkg "github.com/TomasPetrik/vpn/backend/internal/wg"
)

// MergeDuplicateModels is a ONE-SHOT cleanup for the early PetrikVPN period when
// each physical phone was expected to appear once, but buggy registration created
// multiple device rows for the same model. It must NOT be used as ongoing policy —
// identical models from different people are valid going forward.
func MergeDuplicateModels(ctx context.Context, db *sql.DB, wg wgpkg.Driver, log *slog.Logger, apply bool) error {
	groups, err := findDuplicateModelGroups(ctx, db)
	if err != nil {
		return err
	}
	if len(groups) == 0 {
		log.Info("no duplicate (platform, model) groups found")
		return nil
	}

	log.Info("duplicate model groups", "count", len(groups), "apply", apply)
	for _, g := range groups {
		if err := mergeGroup(ctx, db, wg, log, g, apply); err != nil {
			return fmt.Errorf("merge %s/%s: %w", g.Platform, g.Model, err)
		}
	}
	return nil
}

type modelGroup struct {
	Platform string
	Model    string
}

type deviceRow struct {
	ID           string
	UserID       string
	HasIdent     bool
	Status       string
	LastSeen     sql.NullTime
	CreatedAt    time.Time
	PeerTraffic  uint64
	PeerCount    int
	PeerPubKeys  []string
}

func findDuplicateModelGroups(ctx context.Context, db *sql.DB) ([]modelGroup, error) {
	rows, err := db.QueryContext(ctx, `
		SELECT platform, model
		FROM devices
		WHERE model IS NOT NULL AND TRIM(model) <> ''
		GROUP BY platform, model
		HAVING COUNT(*) > 1
		ORDER BY platform, model`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []modelGroup
	for rows.Next() {
		var g modelGroup
		if err := rows.Scan(&g.Platform, &g.Model); err != nil {
			return nil, err
		}
		out = append(out, g)
	}
	return out, rows.Err()
}

func loadGroupDevices(ctx context.Context, db *sql.DB, g modelGroup) ([]deviceRow, error) {
	rows, err := db.QueryContext(ctx, `
		SELECT d.id, d.user_id,
			d.identifier_hash IS NOT NULL,
			d.status, d.last_seen_at, d.created_at,
			COALESCE((
				SELECT SUM(wp.rx_bytes + wp.tx_bytes) FROM wireguard_peers wp WHERE wp.device_id = d.id
			), 0) AS peer_traffic,
			COALESCE((
				SELECT COUNT(*) FROM wireguard_peers wp WHERE wp.device_id = d.id
			), 0) AS peer_count
		FROM devices d
		WHERE d.platform = ? AND d.model = ?
		ORDER BY
			d.last_seen_at IS NULL ASC,
			d.last_seen_at DESC,
			peer_traffic DESC,
			d.created_at DESC`, g.Platform, g.Model)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var devices []deviceRow
	for rows.Next() {
		var d deviceRow
		if err := rows.Scan(
			&d.ID, &d.UserID, &d.HasIdent, &d.Status, &d.LastSeen, &d.CreatedAt,
			&d.PeerTraffic, &d.PeerCount,
		); err != nil {
			return nil, err
		}
		keys, err := peerKeys(ctx, db, d.ID)
		if err != nil {
			return nil, err
		}
		d.PeerPubKeys = keys
		devices = append(devices, d)
	}
	return devices, rows.Err()
}

func peerKeys(ctx context.Context, db *sql.DB, deviceID string) ([]string, error) {
	rows, err := db.QueryContext(ctx, `
		SELECT public_key FROM wireguard_peers WHERE device_id = ?`, deviceID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var keys []string
	for rows.Next() {
		var k string
		if err := rows.Scan(&k); err != nil {
			return nil, err
		}
		keys = append(keys, k)
	}
	return keys, rows.Err()
}

func mergeGroup(ctx context.Context, db *sql.DB, wg wgpkg.Driver, log *slog.Logger, g modelGroup, apply bool) error {
	devices, err := loadGroupDevices(ctx, db, g)
	if err != nil {
		return err
	}
	if len(devices) < 2 {
		return nil
	}
	keeper := devices[0]
	losers := devices[1:]

	log.Info("merge plan",
		"platform", g.Platform,
		"model", g.Model,
		"keeper", keeper.ID,
		"keeper_last_seen", nullTime(keeper.LastSeen),
		"keeper_peer_traffic", keeper.PeerTraffic,
		"losers", len(losers),
	)
	for _, d := range losers {
		log.Info("  drop device",
			"id", d.ID,
			"last_seen", nullTime(d.LastSeen),
			"peer_traffic", d.PeerTraffic,
			"peers", strings.Join(d.PeerPubKeys, ","),
		)
	}
	if !apply {
		return nil
	}

	var removedKeys []string
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	for _, d := range losers {
		removedKeys = append(removedKeys, d.PeerPubKeys...)
		if _, err := tx.ExecContext(ctx, `DELETE FROM devices WHERE id = ?`, d.ID); err != nil {
			return fmt.Errorf("delete device %s: %w", d.ID, err)
		}
		// Drop orphan user if this was their only device.
		var remaining int
		if err := tx.QueryRowContext(ctx, `
			SELECT COUNT(*) FROM devices WHERE user_id = ?`, d.UserID).Scan(&remaining); err != nil {
			return err
		}
		if remaining == 0 {
			if _, err := tx.ExecContext(ctx, `DELETE FROM users WHERE id = ?`, d.UserID); err != nil {
				return fmt.Errorf("delete user %s: %w", d.UserID, err)
			}
			log.Info("deleted orphan user", "user_id", d.UserID)
		}
		log.Info("deleted device", "id", d.ID, "model", g.Model)
	}
	if err := tx.Commit(); err != nil {
		return err
	}

	// Remove stale WireGuard peers from the kernel after DB commit.
	for _, pk := range removedKeys {
		if wg == nil || pk == "" {
			continue
		}
		if err := wg.RemovePeer(pk); err != nil {
			log.Warn("wg RemovePeer after merge", "public_key", pk, "err", err)
		} else {
			log.Info("removed wg peer", "public_key", pk)
		}
	}
	return nil
}

func nullTime(t sql.NullTime) string {
	if !t.Valid {
		return ""
	}
	return t.Time.UTC().Format(time.RFC3339Nano)
}
