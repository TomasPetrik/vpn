-- +goose Up
CREATE TABLE device_diagnostics (
  id            CHAR(36) CHARACTER SET ascii NOT NULL,
  device_id     CHAR(36) CHARACTER SET ascii NOT NULL,
  created_at    DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  app_version   VARCHAR(50) NULL,
  app_build     INT UNSIGNED NULL,
  platform      VARCHAR(16) NULL,
  summary       VARCHAR(255) NULL,
  client_ip     VARCHAR(45) NULL,
  payload_json  LONGTEXT NOT NULL,
  PRIMARY KEY (id),
  KEY device_diagnostics_device_time_idx (device_id, created_at),
  CONSTRAINT device_diagnostics_device_fk FOREIGN KEY (device_id) REFERENCES devices (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- +goose Down
DROP TABLE IF EXISTS device_diagnostics;
