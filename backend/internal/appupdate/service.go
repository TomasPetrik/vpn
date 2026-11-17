package appupdate

import (
	"context"
	"database/sql"
	"sync"
)

type Policy struct {
	Platform          string
	MinSupportedBuild int
	LatestBuild       int
	UpdateURL         string
	Message           string
}

type UpdateResponse struct {
	Status            string `json:"status"` // none | recommended | required
	MinSupportedBuild int    `json:"min_supported_build"`
	LatestBuild       int    `json:"latest_build"`
	UpdateURL         string `json:"update_url,omitempty"`
	Message           string `json:"message,omitempty"`
}

type Service struct {
	DB *sql.DB

	mu    sync.RWMutex
	cache map[string]Policy
}

func New(db *sql.DB) *Service {
	s := &Service{DB: db, cache: map[string]Policy{}}
	_ = s.Reload(context.Background())
	return s
}

func (s *Service) Reload(ctx context.Context) error {
	rows, err := s.DB.QueryContext(ctx, `
		SELECT platform, min_supported_build, latest_build,
			COALESCE(update_url, ''), COALESCE(message, '')
		FROM app_update_policies`)
	if err != nil {
		return err
	}
	defer rows.Close()
	next := map[string]Policy{}
	for rows.Next() {
		var p Policy
		if err := rows.Scan(&p.Platform, &p.MinSupportedBuild, &p.LatestBuild, &p.UpdateURL, &p.Message); err != nil {
			return err
		}
		next[p.Platform] = p
	}
	s.mu.Lock()
	s.cache = next
	s.mu.Unlock()
	return rows.Err()
}

func (s *Service) Policy(platform string) Policy {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.cache[platform]
}

func (s *Service) Evaluate(platform string, build int) UpdateResponse {
	p := s.Policy(platform)
	out := UpdateResponse{
		MinSupportedBuild: p.MinSupportedBuild,
		LatestBuild:       p.LatestBuild,
		UpdateURL:         p.UpdateURL,
		Message:           p.Message,
		Status:            "none",
	}
	if platform == "" {
		platform = "unknown"
	}
	if p.MinSupportedBuild > 0 && build < p.MinSupportedBuild {
		out.Status = "required"
		if out.Message == "" {
			out.Message = "Please update PetrikVPN to keep using the VPN."
		}
		return out
	}
	if p.LatestBuild > 0 && build < p.LatestBuild {
		out.Status = "recommended"
	}
	return out
}

func (s *Service) Set(ctx context.Context, platform string, minBuild, latest int, url, message, adminID string) error {
	var updatedBy any
	if adminID != "" {
		updatedBy = adminID
	}
	_, err := s.DB.ExecContext(ctx, `
		UPDATE app_update_policies
		SET min_supported_build = ?, latest_build = ?, update_url = NULLIF(?, ''),
			message = NULLIF(?, ''), updated_by = ?
		WHERE platform = ?`, minBuild, latest, url, message, updatedBy, platform)
	if err != nil {
		return err
	}
	return s.Reload(ctx)
}

func (s *Service) CountBlocked(ctx context.Context, platform string, minBuild int) (int, error) {
	var n int
	err := s.DB.QueryRowContext(ctx, `
		SELECT COUNT(*) FROM devices
		WHERE platform = ? AND app_build IS NOT NULL AND app_build < ?`, platform, minBuild).Scan(&n)
	return n, err
}
