package limits

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"
)

const (
	SourceDevice = "device"
	SourceUser   = "user"
	SourcePlan   = "plan"
	SourceGlobal = "global"
	SourceNone   = "none"
)

// Caps are resolved limits. A nil pointer means unlimited.
type Caps struct {
	DownloadKbps       *uint64
	UploadKbps         *uint64
	MonthlyQuotaBytes  *uint64
	DownloadSource     string
	UploadSource       string
	MonthlyQuotaSource string
}

// Policy is one stored layer (global, plan, user, or device).
type Policy struct {
	DownloadKbps      sql.NullInt64
	UploadKbps        sql.NullInt64
	MonthlyQuotaBytes sql.NullInt64
}

// Plan is a row from plans.
type Plan struct {
	Code string
	Policy
	UpdatedAt time.Time
}

// Global is the singleton global_settings row.
type Global struct {
	Policy
	UpdatedAt time.Time
}

// Effective is resolved caps plus current-month usage.
type Effective struct {
	Caps
	PlanCode         string
	MonthlyUsedBytes uint64
}

// Resolve merges device → user → plan → global into effective caps.
func Resolve(device, user, plan, global Policy) Caps {
	out := Caps{
		DownloadSource:     SourceNone,
		UploadSource:       SourceNone,
		MonthlyQuotaSource: SourceNone,
	}
	apply := func(name string, p Policy) {
		if out.DownloadSource == SourceNone {
			if v, set := capOrNil(p.DownloadKbps); set {
				out.DownloadKbps = v
				out.DownloadSource = name
			}
		}
		if out.UploadSource == SourceNone {
			if v, set := capOrNil(p.UploadKbps); set {
				out.UploadKbps = v
				out.UploadSource = name
			}
		}
		if out.MonthlyQuotaSource == SourceNone {
			if v, set := capOrNil(p.MonthlyQuotaBytes); set {
				out.MonthlyQuotaBytes = v
				out.MonthlyQuotaSource = name
			}
		}
	}
	apply(SourceDevice, device)
	apply(SourceUser, user)
	apply(SourcePlan, plan)
	apply(SourceGlobal, global)
	return out
}

func capOrNil(n sql.NullInt64) (value *uint64, set bool) {
	if !n.Valid {
		return nil, false
	}
	if n.Int64 == 0 {
		return nil, true // explicit unlimited
	}
	v := uint64(n.Int64)
	return &v, true
}

// Store reads/writes limit policies.
type Store struct {
	DB *sql.DB
}

func (s *Store) LoadGlobal(ctx context.Context) (Global, error) {
	var g Global
	err := s.DB.QueryRowContext(ctx, `
		SELECT download_kbps, upload_kbps, monthly_quota_bytes, updated_at
		FROM global_settings WHERE id = 1`).Scan(
		&g.DownloadKbps, &g.UploadKbps, &g.MonthlyQuotaBytes, &g.UpdatedAt,
	)
	if errors.Is(err, sql.ErrNoRows) {
		_, _ = s.DB.ExecContext(ctx, `INSERT INTO global_settings (id) VALUES (1)`)
		return s.LoadGlobal(ctx)
	}
	return g, err
}

func (s *Store) SaveGlobal(ctx context.Context, p Policy) error {
	_, err := s.DB.ExecContext(ctx, `
		UPDATE global_settings
		SET download_kbps = ?, upload_kbps = ?, monthly_quota_bytes = ?
		WHERE id = 1`,
		nullIntArg(p.DownloadKbps), nullIntArg(p.UploadKbps), nullIntArg(p.MonthlyQuotaBytes),
	)
	return err
}

func (s *Store) ListPlans(ctx context.Context) ([]Plan, error) {
	rows, err := s.DB.QueryContext(ctx, `
		SELECT code, download_kbps, upload_kbps, monthly_quota_bytes, updated_at
		FROM plans ORDER BY code`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Plan
	for rows.Next() {
		var p Plan
		if err := rows.Scan(&p.Code, &p.DownloadKbps, &p.UploadKbps, &p.MonthlyQuotaBytes, &p.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

func (s *Store) LoadPlan(ctx context.Context, code string) (Plan, error) {
	var p Plan
	err := s.DB.QueryRowContext(ctx, `
		SELECT code, download_kbps, upload_kbps, monthly_quota_bytes, updated_at
		FROM plans WHERE code = ?`, code).Scan(
		&p.Code, &p.DownloadKbps, &p.UploadKbps, &p.MonthlyQuotaBytes, &p.UpdatedAt,
	)
	return p, err
}

func (s *Store) SavePlan(ctx context.Context, code string, p Policy) error {
	res, err := s.DB.ExecContext(ctx, `
		UPDATE plans
		SET download_kbps = ?, upload_kbps = ?, monthly_quota_bytes = ?
		WHERE code = ?`,
		nullIntArg(p.DownloadKbps), nullIntArg(p.UploadKbps), nullIntArg(p.MonthlyQuotaBytes), code,
	)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return fmt.Errorf("unknown plan %q", code)
	}
	return nil
}

func (s *Store) SaveUserOverrides(ctx context.Context, userID, plan string, p Policy) error {
	if plan != "free" && plan != "pro" {
		return fmt.Errorf("invalid plan %q", plan)
	}
	_, err := s.DB.ExecContext(ctx, `
		UPDATE users
		SET plan = ?, download_kbps = ?, upload_kbps = ?, monthly_quota_bytes = ?
		WHERE id = ?`,
		plan, nullIntArg(p.DownloadKbps), nullIntArg(p.UploadKbps), nullIntArg(p.MonthlyQuotaBytes), userID,
	)
	return err
}

func (s *Store) SaveDeviceOverrides(ctx context.Context, deviceID string, p Policy) error {
	_, err := s.DB.ExecContext(ctx, `
		UPDATE devices
		SET download_kbps = ?, upload_kbps = ?, monthly_quota_bytes = ?
		WHERE id = ?`,
		nullIntArg(p.DownloadKbps), nullIntArg(p.UploadKbps), nullIntArg(p.MonthlyQuotaBytes), deviceID,
	)
	return err
}

// UserPolicy returns plan code and override policy for a user.
func (s *Store) UserPolicy(ctx context.Context, userID string) (plan string, p Policy, err error) {
	err = s.DB.QueryRowContext(ctx, `
		SELECT plan, download_kbps, upload_kbps, monthly_quota_bytes
		FROM users WHERE id = ?`, userID).Scan(
		&plan, &p.DownloadKbps, &p.UploadKbps, &p.MonthlyQuotaBytes,
	)
	return
}

// DevicePolicy returns user id and override policy for a device.
func (s *Store) DevicePolicy(ctx context.Context, deviceID string) (userID string, p Policy, err error) {
	err = s.DB.QueryRowContext(ctx, `
		SELECT user_id, download_kbps, upload_kbps, monthly_quota_bytes
		FROM devices WHERE id = ?`, deviceID).Scan(
		&userID, &p.DownloadKbps, &p.UploadKbps, &p.MonthlyQuotaBytes,
	)
	return
}

// ForDevice resolves effective limits for a device and that device's month usage.
func (s *Store) ForDevice(ctx context.Context, deviceID string, now time.Time) (Effective, error) {
	userID, devPol, err := s.DevicePolicy(ctx, deviceID)
	if err != nil {
		return Effective{}, err
	}
	planCode, userPol, err := s.UserPolicy(ctx, userID)
	if err != nil {
		return Effective{}, err
	}
	plan, err := s.LoadPlan(ctx, planCode)
	if err != nil {
		return Effective{}, err
	}
	global, err := s.LoadGlobal(ctx)
	if err != nil {
		return Effective{}, err
	}
	used, err := MonthUsageForDevice(ctx, s.DB, deviceID, now)
	if err != nil {
		return Effective{}, err
	}
	return Effective{
		Caps:             Resolve(devPol, userPol, plan.Policy, global.Policy),
		PlanCode:         planCode,
		MonthlyUsedBytes: used,
	}, nil
}

// ForUser resolves effective limits ignoring device overrides, with sum of all user devices' month usage.
func (s *Store) ForUser(ctx context.Context, userID string, now time.Time) (Effective, error) {
	planCode, userPol, err := s.UserPolicy(ctx, userID)
	if err != nil {
		return Effective{}, err
	}
	plan, err := s.LoadPlan(ctx, planCode)
	if err != nil {
		return Effective{}, err
	}
	global, err := s.LoadGlobal(ctx)
	if err != nil {
		return Effective{}, err
	}
	used, err := MonthUsageForUser(ctx, s.DB, userID, now)
	if err != nil {
		return Effective{}, err
	}
	return Effective{
		Caps:             Resolve(Policy{}, userPol, plan.Policy, global.Policy),
		PlanCode:         planCode,
		MonthlyUsedBytes: used,
	}, nil
}

func nullIntArg(n sql.NullInt64) any {
	if !n.Valid {
		return nil
	}
	return n.Int64
}

// ParseFormField maps admin form values: empty→NULL inherit, "0"→unlimited, else number.
func ParseFormField(raw string) (sql.NullInt64, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return sql.NullInt64{}, nil
	}
	if strings.EqualFold(raw, "unlimited") {
		return sql.NullInt64{Int64: 0, Valid: true}, nil
	}
	n, err := strconv.ParseInt(raw, 10, 64)
	if err != nil || n < 0 {
		return sql.NullInt64{}, fmt.Errorf("invalid number %q", raw)
	}
	return sql.NullInt64{Int64: n, Valid: true}, nil
}

// FormatFormValue for editing: empty inherit, "0" unlimited, else number.
func FormatFormValue(n sql.NullInt64) string {
	if !n.Valid {
		return ""
	}
	return strconv.FormatInt(n.Int64, 10)
}

// APIValue converts an effective cap to JSON-friendly null or number.
func APIValue(v *uint64) any {
	if v == nil {
		return nil
	}
	return *v
}

// DisplayCap humanizes a resolved cap for admin templates.
func DisplayCap(v *uint64, unit string) string {
	if v == nil {
		return "Unlimited"
	}
	if unit == "bytes" {
		return HumanBytes(*v)
	}
	return fmt.Sprintf("%d %s", *v, unit)
}

// HumanBytes formats byte counts for admin/API display.
func HumanBytes(n uint64) string {
	const unit = 1024
	if n < unit {
		return fmt.Sprintf("%d B", n)
	}
	div, exp := uint64(unit), 0
	for v := n / unit; v >= unit; v /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.2f %ciB", float64(n)/float64(div), "KMGTPE"[exp])
}
