-- +goose Up
CREATE TABLE plans (
  code                  VARCHAR(32) NOT NULL,
  download_kbps         INT UNSIGNED NULL,
  upload_kbps           INT UNSIGNED NULL,
  monthly_quota_bytes   BIGINT UNSIGNED NULL,
  updated_at            DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO plans (code) VALUES ('free'), ('pro');

CREATE TABLE global_settings (
  id                    TINYINT UNSIGNED NOT NULL,
  download_kbps         INT UNSIGNED NULL,
  upload_kbps           INT UNSIGNED NULL,
  monthly_quota_bytes   BIGINT UNSIGNED NULL,
  updated_at            DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (id),
  CONSTRAINT global_settings_singleton_chk CHECK (id = 1)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO global_settings (id) VALUES (1);

ALTER TABLE users
  ADD COLUMN plan VARCHAR(32) NOT NULL DEFAULT 'free' AFTER status,
  ADD COLUMN download_kbps INT UNSIGNED NULL AFTER plan,
  ADD COLUMN upload_kbps INT UNSIGNED NULL AFTER download_kbps,
  ADD COLUMN monthly_quota_bytes BIGINT UNSIGNED NULL AFTER upload_kbps,
  ADD CONSTRAINT users_plan_fk FOREIGN KEY (plan) REFERENCES plans (code);

ALTER TABLE devices
  ADD COLUMN download_kbps INT UNSIGNED NULL AFTER status,
  ADD COLUMN upload_kbps INT UNSIGNED NULL AFTER download_kbps,
  ADD COLUMN monthly_quota_bytes BIGINT UNSIGNED NULL AFTER upload_kbps;

-- +goose Down
ALTER TABLE devices
  DROP COLUMN monthly_quota_bytes,
  DROP COLUMN upload_kbps,
  DROP COLUMN download_kbps;

ALTER TABLE users
  DROP FOREIGN KEY users_plan_fk,
  DROP COLUMN monthly_quota_bytes,
  DROP COLUMN upload_kbps,
  DROP COLUMN download_kbps,
  DROP COLUMN plan;

DROP TABLE IF EXISTS global_settings;
DROP TABLE IF EXISTS plans;
