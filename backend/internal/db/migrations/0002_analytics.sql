-- +goose Up
ALTER TABLE devices
  ADD COLUMN last_client_ip VARCHAR(45) NULL AFTER last_seen_at,
  ADD COLUMN last_client_country CHAR(2) NULL AFTER last_client_ip;

ALTER TABLE wireguard_peers
  ADD COLUMN handshake_count BIGINT UNSIGNED NOT NULL DEFAULT 0 AFTER last_handshake_at;

CREATE TABLE peer_stats_samples (
  id               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  peer_id          CHAR(36) CHARACTER SET ascii NOT NULL,
  sampled_at       DATETIME(6) NOT NULL,
  rx_bytes         BIGINT UNSIGNED NOT NULL DEFAULT 0,
  tx_bytes         BIGINT UNSIGNED NOT NULL DEFAULT 0,
  rx_delta         BIGINT UNSIGNED NOT NULL DEFAULT 0,
  tx_delta         BIGINT UNSIGNED NOT NULL DEFAULT 0,
  handshake_delta  TINYINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  KEY peer_stats_samples_peer_time_idx (peer_id, sampled_at),
  KEY peer_stats_samples_time_idx (sampled_at),
  CONSTRAINT peer_stats_samples_peer_fk FOREIGN KEY (peer_id) REFERENCES wireguard_peers (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- +goose Down
DROP TABLE IF EXISTS peer_stats_samples;
ALTER TABLE wireguard_peers DROP COLUMN handshake_count;
ALTER TABLE devices
  DROP COLUMN last_client_country,
  DROP COLUMN last_client_ip;
