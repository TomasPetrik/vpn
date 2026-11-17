package admin

import (
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"errors"
	"time"

	"github.com/google/uuid"
	"golang.org/x/crypto/argon2"
)

const (
	argonTime    = 3
	argonMemory  = 64 * 1024
	argonThreads = 4
	argonKeyLen  = 32
	sessionTTL   = 12 * time.Hour
	idleTTL      = 30 * time.Minute
)

type Store struct {
	DB *sql.DB
}

func (s *Store) CreateAdmin(username, password string) error {
	id := uuid.Must(uuid.NewV7()).String()
	hash, err := hashPassword(password)
	if err != nil {
		return err
	}
	_, err = s.DB.Exec(`INSERT INTO admins (id, username, password_hash) VALUES (?, ?, ?)`, id, username, hash)
	return err
}

func (s *Store) Authenticate(username, password string) (string, error) {
	var id, hash string
	var disabled sql.NullTime
	err := s.DB.QueryRow(`SELECT id, password_hash, disabled_at FROM admins WHERE username = ?`, username).
		Scan(&id, &hash, &disabled)
	if errors.Is(err, sql.ErrNoRows) {
		return "", errors.New("invalid credentials")
	}
	if err != nil {
		return "", err
	}
	if disabled.Valid {
		return "", errors.New("disabled")
	}
	if !verifyPassword(hash, password) {
		return "", errors.New("invalid credentials")
	}
	_, _ = s.DB.Exec(`UPDATE admins SET last_login_at = UTC_TIMESTAMP(6) WHERE id = ?`, id)
	return id, nil
}

func (s *Store) CreateSession(adminID, ip, ua string) (cookieValue, csrf string, err error) {
	raw := make([]byte, 32)
	if _, err = rand.Read(raw); err != nil {
		return "", "", err
	}
	cookieValue = base64.RawURLEncoding.EncodeToString(raw)
	sum := sha256.Sum256([]byte(cookieValue))
	csrfRaw := make([]byte, 32)
	if _, err = rand.Read(csrfRaw); err != nil {
		return "", "", err
	}
	csrf = base64.RawURLEncoding.EncodeToString(csrfRaw)
	expires := time.Now().UTC().Add(sessionTTL)
	_, err = s.DB.Exec(`
		INSERT INTO admin_sessions (token_hash, admin_id, csrf_token, ip, user_agent, expires_at)
		VALUES (?, ?, ?, ?, ?, ?)`, sum[:], adminID, csrf, nullStr(ip), nullStr(ua), expires)
	return cookieValue, csrf, err
}

func (s *Store) Session(cookieValue string) (adminID, csrf string, err error) {
	sum := sha256.Sum256([]byte(cookieValue))
	var expires, lastSeen time.Time
	err = s.DB.QueryRow(`
		SELECT admin_id, csrf_token, expires_at, last_seen_at FROM admin_sessions WHERE token_hash = ?`, sum[:]).
		Scan(&adminID, &csrf, &expires, &lastSeen)
	if errors.Is(err, sql.ErrNoRows) {
		return "", "", errors.New("no session")
	}
	if err != nil {
		return "", "", err
	}
	now := time.Now().UTC()
	if now.After(expires) || now.After(lastSeen.Add(idleTTL)) {
		_, _ = s.DB.Exec(`DELETE FROM admin_sessions WHERE token_hash = ?`, sum[:])
		return "", "", errors.New("expired")
	}
	_, _ = s.DB.Exec(`UPDATE admin_sessions SET last_seen_at = ? WHERE token_hash = ?`, now, sum[:])
	return adminID, csrf, nil
}

func (s *Store) DeleteSession(cookieValue string) {
	sum := sha256.Sum256([]byte(cookieValue))
	_, _ = s.DB.Exec(`DELETE FROM admin_sessions WHERE token_hash = ?`, sum[:])
}

func hashPassword(pw string) (string, error) {
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	hash := argon2.IDKey([]byte(pw), salt, argonTime, argonMemory, argonThreads, argonKeyLen)
	return "argon2id$" + base64.RawStdEncoding.EncodeToString(salt) + "$" + base64.RawStdEncoding.EncodeToString(hash), nil
}

func verifyPassword(encoded, pw string) bool {
	parts := splitDollar(encoded)
	if len(parts) != 3 || parts[0] != "argon2id" {
		return false
	}
	salt, err1 := base64.RawStdEncoding.DecodeString(parts[1])
	want, err2 := base64.RawStdEncoding.DecodeString(parts[2])
	if err1 != nil || err2 != nil {
		return false
	}
	got := argon2.IDKey([]byte(pw), salt, argonTime, argonMemory, argonThreads, argonKeyLen)
	if len(got) != len(want) {
		return false
	}
	var v byte
	for i := range got {
		v |= got[i] ^ want[i]
	}
	return v == 0
}

func splitDollar(s string) []string {
	var out []string
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] == '$' {
			out = append(out, s[start:i])
			start = i + 1
		}
	}
	out = append(out, s[start:])
	return out
}

func nullStr(s string) any {
	if s == "" {
		return nil
	}
	return s
}
