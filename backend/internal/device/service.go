package device

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
)

type Service struct {
	DB      *sql.DB
	HMACKey []byte
	// CountryOf maps a public IP to ISO country code; may be nil.
	CountryOf func(ip string) string
}

type RegisterRequest struct {
	InstallationID  string
	DeviceIdentifier *string
	Platform        string
	Manufacturer    string
	Model           string
	OSVersion       string
	AppVersion      string
	AppBuild        int
	BearerToken     string
}

type RegisterResult struct {
	UserID      string `json:"user_id"`
	DeviceID    string `json:"device_id"`
	DeviceToken string `json:"device_token,omitempty"`
	Created     bool   `json:"created"`
}

type Device struct {
	ID     string
	UserID string
	Status string
}

func (s *Service) Register(ctx context.Context, req RegisterRequest) (RegisterResult, error) {
	req.Platform = strings.ToLower(strings.TrimSpace(req.Platform))
	if req.Platform != "android" && req.Platform != "ios" {
		return RegisterResult{}, fmt.Errorf("invalid platform")
	}
	if _, err := uuid.Parse(req.InstallationID); err != nil {
		return RegisterResult{}, fmt.Errorf("invalid installation_id")
	}

	var idHash []byte
	if req.DeviceIdentifier != nil {
		id := strings.TrimSpace(*req.DeviceIdentifier)
		if id != "" {
			idHash = IdentifierHash(s.HMACKey, req.Platform, id)
		}
	}

	for attempt := 0; attempt < 2; attempt++ {
		res, err := s.registerOnce(ctx, req, idHash)
		if err == nil {
			return res, nil
		}
		if isRetryable(err) && attempt == 0 {
			continue
		}
		return RegisterResult{}, err
	}
	return RegisterResult{}, fmt.Errorf("registration failed")
}

func (s *Service) registerOnce(ctx context.Context, req RegisterRequest, idHash []byte) (RegisterResult, error) {
	tx, err := s.DB.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelReadCommitted})
	if err != nil {
		return RegisterResult{}, err
	}
	defer func() { _ = tx.Rollback() }()

	var (
		deviceID, userID, status string
		tokenHash                []byte
	)

	// 1) valid bearer token
	if req.BearerToken != "" {
		th := HashToken(req.BearerToken)
		err = tx.QueryRowContext(ctx, `
			SELECT id, user_id, status, token_hash FROM devices WHERE token_hash = ?`, th).
			Scan(&deviceID, &userID, &status, &tokenHash)
		if err != nil && !errors.Is(err, sql.ErrNoRows) {
			return RegisterResult{}, err
		}
	}

	// 2) identifier hash
	if deviceID == "" && idHash != nil {
		err = tx.QueryRowContext(ctx, `
			SELECT id, user_id, status, token_hash FROM devices
			WHERE platform = ? AND identifier_hash = ?`, req.Platform, idHash).
			Scan(&deviceID, &userID, &status, &tokenHash)
		if err != nil && !errors.Is(err, sql.ErrNoRows) {
			return RegisterResult{}, err
		}
	}

	// 3) installation_id
	if deviceID == "" {
		err = tx.QueryRowContext(ctx, `
			SELECT id, user_id, status, token_hash FROM devices WHERE installation_id = ?`,
			req.InstallationID).Scan(&deviceID, &userID, &status, &tokenHash)
		if err != nil && !errors.Is(err, sql.ErrNoRows) {
			return RegisterResult{}, err
		}
	}

	now := time.Now().UTC()
	if deviceID != "" {
		if status == "blocked" {
			return RegisterResult{}, fmt.Errorf("device_blocked")
		}
		issueToken := req.BearerToken == "" || !hmacEqual(tokenHash, HashToken(req.BearerToken))
		var plain string
		var newHash []byte
		if issueToken {
			plain, newHash, err = NewToken()
			if err != nil {
				return RegisterResult{}, err
			}
		} else {
			newHash = tokenHash
		}
		_, err = tx.ExecContext(ctx, `
			UPDATE devices SET
				manufacturer = COALESCE(NULLIF(?, ''), manufacturer),
				model = COALESCE(NULLIF(?, ''), model),
				os_version = COALESCE(NULLIF(?, ''), os_version),
				app_version = COALESCE(NULLIF(?, ''), app_version),
				app_build = ?,
				identifier_hash = COALESCE(identifier_hash, ?),
				token_hash = ?,
				last_seen_at = ?,
				updated_at = ?
			WHERE id = ?`,
			req.Manufacturer, req.Model, req.OSVersion, req.AppVersion, nullInt(req.AppBuild),
			nullableBytes(idHash), newHash, now, now, deviceID)
		if err != nil {
			return RegisterResult{}, err
		}
		if err := tx.Commit(); err != nil {
			return RegisterResult{}, err
		}
		out := RegisterResult{UserID: userID, DeviceID: deviceID, Created: false}
		if issueToken {
			out.DeviceToken = plain
		}
		return out, nil
	}

	userID = uuid.Must(uuid.NewV7()).String()
	deviceID = uuid.Must(uuid.NewV7()).String()
	plain, newHash, err := NewToken()
	if err != nil {
		return RegisterResult{}, err
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO users (id, status) VALUES (?, 'active')`, userID)
	if err != nil {
		return RegisterResult{}, err
	}
	_, err = tx.ExecContext(ctx, `
		INSERT INTO devices (
			id, user_id, platform, installation_id, identifier_hash, token_hash,
			manufacturer, model, os_version, app_version, app_build, status, last_seen_at
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', ?)`,
		deviceID, userID, req.Platform, req.InstallationID, nullableBytes(idHash), newHash,
		nullStr(req.Manufacturer), nullStr(req.Model), nullStr(req.OSVersion), nullStr(req.AppVersion),
		nullInt(req.AppBuild), now)
	if err != nil {
		return RegisterResult{}, err
	}
	if err := tx.Commit(); err != nil {
		return RegisterResult{}, err
	}
	return RegisterResult{UserID: userID, DeviceID: deviceID, DeviceToken: plain, Created: true}, nil
}

func (s *Service) Authenticate(ctx context.Context, bearer string) (Device, error) {
	if bearer == "" {
		return Device{}, fmt.Errorf("invalid_token")
	}
	th := HashToken(bearer)
	var d Device
	err := s.DB.QueryRowContext(ctx, `
		SELECT id, user_id, status FROM devices WHERE token_hash = ?`, th).
		Scan(&d.ID, &d.UserID, &d.Status)
	if errors.Is(err, sql.ErrNoRows) {
		return Device{}, fmt.Errorf("invalid_token")
	}
	if err != nil {
		return Device{}, err
	}
	if d.Status == "blocked" {
		return Device{}, fmt.Errorf("device_blocked")
	}
	return d, nil
}

func (s *Service) TouchBuild(ctx context.Context, deviceID string, build int, version string) {
	s.TouchSeen(ctx, deviceID, build, version, "", "")
}

// TouchSeen updates last_seen / app metadata and optional client geo.
func (s *Service) TouchSeen(ctx context.Context, deviceID string, build int, version, clientIP, country string) {
	if deviceID == "" {
		return
	}
	if country == "" && clientIP != "" && s.CountryOf != nil {
		country = s.CountryOf(clientIP)
	}
	_, _ = s.DB.ExecContext(ctx, `
		UPDATE devices SET
			app_build = CASE WHEN ? > 0 THEN ? ELSE app_build END,
			app_version = COALESCE(NULLIF(?, ''), app_version),
			last_seen_at = UTC_TIMESTAMP(6),
			last_client_ip = COALESCE(NULLIF(?, ''), last_client_ip),
			last_client_country = COALESCE(NULLIF(?, ''), last_client_country),
			updated_at = UTC_TIMESTAMP(6)
		WHERE id = ?`,
		build, build, version, clientIP, country, deviceID)
}

func isRetryable(err error) bool {
	msg := err.Error()
	return strings.Contains(msg, "Duplicate") || strings.Contains(msg, "1062") || strings.Contains(msg, "1213")
}

func hmacEqual(a, b []byte) bool {
	if len(a) != len(b) {
		return false
	}
	var v byte
	for i := range a {
		v |= a[i] ^ b[i]
	}
	return v == 0
}

func nullStr(s string) any {
	if s == "" {
		return nil
	}
	return s
}

func nullInt(n int) any {
	if n <= 0 {
		return nil
	}
	return n
}

func nullableBytes(b []byte) any {
	if len(b) == 0 {
		return nil
	}
	return b
}
