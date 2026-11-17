-- +goose Up
CREATE TABLE users (
  id          CHAR(36) CHARACTER SET ascii NOT NULL,
  status      VARCHAR(16) NOT NULL DEFAULT 'active',
  created_at  DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at  DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (id),
  CONSTRAINT users_status_chk CHECK (status IN ('active', 'blocked'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE devices (
  id               CHAR(36) CHARACTER SET ascii NOT NULL,
  user_id          CHAR(36) CHARACTER SET ascii NOT NULL,
  platform         VARCHAR(16) NOT NULL,
  installation_id  CHAR(36) CHARACTER SET ascii NOT NULL,
  identifier_hash  BINARY(32) NULL,
  token_hash       BINARY(32) NOT NULL,
  manufacturer     VARCHAR(100) NULL,
  model            VARCHAR(100) NULL,
  os_version       VARCHAR(50) NULL,
  app_version      VARCHAR(50) NULL,
  app_build        INT UNSIGNED NULL,
  status           VARCHAR(16) NOT NULL DEFAULT 'active',
  last_seen_at     DATETIME(6) NULL,
  created_at       DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at       DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (id),
  UNIQUE KEY devices_installation_uq (installation_id),
  UNIQUE KEY devices_platform_identifier_uq (platform, identifier_hash),
  UNIQUE KEY devices_token_uq (token_hash),
  KEY devices_user_idx (user_id),
  CONSTRAINT devices_user_fk FOREIGN KEY (user_id) REFERENCES users (id),
  CONSTRAINT devices_platform_chk CHECK (platform IN ('android', 'ios')),
  CONSTRAINT devices_status_chk CHECK (status IN ('active', 'blocked'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE vpn_servers (
  id             CHAR(36) CHARACTER SET ascii NOT NULL,
  name           VARCHAR(100) NOT NULL,
  country_code   CHAR(2) NULL,
  city           VARCHAR(100) NULL,
  public_host    VARCHAR(255) NOT NULL,
  public_ips     JSON NOT NULL,
  wg_interface   VARCHAR(15) NOT NULL,
  wg_public_key  CHAR(44) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  tunnel_cidr    VARCHAR(18) NOT NULL,
  is_active      BOOLEAN NOT NULL DEFAULT TRUE,
  created_at     DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at     DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE wireguard_peers (
  id                 CHAR(36) CHARACTER SET ascii NOT NULL,
  device_id          CHAR(36) CHARACTER SET ascii NOT NULL,
  server_id          CHAR(36) CHARACTER SET ascii NOT NULL,
  public_key         CHAR(44) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  tunnel_ipv4        INT UNSIGNED NOT NULL,
  last_handshake_at  DATETIME(6) NULL,
  rx_bytes           BIGINT UNSIGNED NOT NULL DEFAULT 0,
  tx_bytes           BIGINT UNSIGNED NOT NULL DEFAULT 0,
  stats_updated_at   DATETIME(6) NULL,
  created_at         DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  updated_at         DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (id),
  UNIQUE KEY wireguard_peers_device_server_uq (device_id, server_id),
  UNIQUE KEY wireguard_peers_ip_uq (server_id, tunnel_ipv4),
  UNIQUE KEY wireguard_peers_key_uq (public_key),
  CONSTRAINT wireguard_peers_device_fk FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE,
  CONSTRAINT wireguard_peers_server_fk FOREIGN KEY (server_id) REFERENCES vpn_servers (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE admins (
  id             CHAR(36) CHARACTER SET ascii NOT NULL,
  username       VARCHAR(64) NOT NULL,
  password_hash  VARCHAR(255) NOT NULL,
  disabled_at    DATETIME(6) NULL,
  last_login_at  DATETIME(6) NULL,
  created_at     DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  PRIMARY KEY (id),
  UNIQUE KEY admins_username_uq (username)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE admin_sessions (
  token_hash    BINARY(32) NOT NULL,
  admin_id      CHAR(36) CHARACTER SET ascii NOT NULL,
  csrf_token    CHAR(43) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  ip            VARCHAR(45) NULL,
  user_agent    VARCHAR(255) NULL,
  created_at    DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  last_seen_at  DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  expires_at    DATETIME(6) NOT NULL,
  PRIMARY KEY (token_hash),
  KEY admin_sessions_admin_idx (admin_id),
  CONSTRAINT admin_sessions_admin_fk FOREIGN KEY (admin_id) REFERENCES admins (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE app_update_policies (
  platform             VARCHAR(16) NOT NULL,
  min_supported_build  INT UNSIGNED NOT NULL DEFAULT 0,
  latest_build         INT UNSIGNED NOT NULL DEFAULT 0,
  update_url           VARCHAR(500) NULL,
  message              VARCHAR(500) NULL,
  updated_by           CHAR(36) CHARACTER SET ascii NULL,
  updated_at           DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (platform),
  CONSTRAINT app_update_policies_platform_chk CHECK (platform IN ('android', 'ios')),
  CONSTRAINT app_update_policies_builds_chk CHECK (latest_build >= min_supported_build),
  CONSTRAINT app_update_policies_admin_fk FOREIGN KEY (updated_by) REFERENCES admins (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO app_update_policies (platform) VALUES ('android'), ('ios');

-- +goose Down
DROP TABLE IF EXISTS app_update_policies;
DROP TABLE IF EXISTS admin_sessions;
DROP TABLE IF EXISTS admins;
DROP TABLE IF EXISTS wireguard_peers;
DROP TABLE IF EXISTS vpn_servers;
DROP TABLE IF EXISTS devices;
DROP TABLE IF EXISTS users;
