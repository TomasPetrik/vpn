package admin

import (
	"database/sql"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"
)

type deviceListItem struct {
	ID, Platform, Model, OS, AppVersion, LastSeen string
	Build, PeerCount                              int
	Country, Created                              string
	TrafficBytes                                  uint64
	TrafficHuman                                  string
}

type userListItem struct {
	ID, Status, Created string
	Devices             int
}

// deviceListFilter controls Devices master-list sorting / filtering.
type deviceListFilter struct {
	Sort    string // created | seen | traffic
	Dir     string // asc | desc
	Country string // ISO code, "?" for unknown/empty, "" for all
}

const deviceListFilterCookie = "vpn_admin_devices_filter"

func parseDeviceListFilter(r *http.Request) deviceListFilter {
	q := r.URL.Query()
	// Prefer explicit query params (form submit / deep link). Otherwise restore
	// the last selection from a long-lived cookie so list clicks / sidebar
	// navigation keep sort, order and country forever.
	if q.Has("sort") || q.Has("dir") || q.Has("country") {
		return normalizeDeviceListFilter(deviceListFilter{
			Sort:    strings.ToLower(strings.TrimSpace(q.Get("sort"))),
			Dir:     strings.ToLower(strings.TrimSpace(q.Get("dir"))),
			Country: strings.ToUpper(strings.TrimSpace(q.Get("country"))),
		})
	}
	if c, err := r.Cookie(deviceListFilterCookie); err == nil && c.Value != "" {
		vals, err := url.ParseQuery(c.Value)
		if err == nil {
			return normalizeDeviceListFilter(deviceListFilter{
				Sort:    strings.ToLower(strings.TrimSpace(vals.Get("sort"))),
				Dir:     strings.ToLower(strings.TrimSpace(vals.Get("dir"))),
				Country: strings.ToUpper(strings.TrimSpace(vals.Get("country"))),
			})
		}
	}
	return normalizeDeviceListFilter(deviceListFilter{})
}

func normalizeDeviceListFilter(f deviceListFilter) deviceListFilter {
	switch f.Sort {
	case "created", "seen", "traffic":
	default:
		f.Sort = "created"
	}
	switch f.Dir {
	case "asc", "desc":
	default:
		f.Dir = "desc"
	}
	if f.Country == "UNKNOWN" {
		f.Country = "?"
	}
	return f
}

func persistDeviceListFilter(w http.ResponseWriter, f deviceListFilter) {
	http.SetCookie(w, &http.Cookie{
		Name:     deviceListFilterCookie,
		Value:    f.Query(),
		Path:     "/admin",
		MaxAge:   10 * 365 * 24 * 60 * 60, // ~10 years
		HttpOnly: false,
		SameSite: http.SameSiteLaxMode,
		Secure:   true,
	})
}

// resolveDeviceListFilter reads query/cookie and refreshes the persistent cookie.
func resolveDeviceListFilter(w http.ResponseWriter, r *http.Request) deviceListFilter {
	f := parseDeviceListFilter(r)
	persistDeviceListFilter(w, f)
	return f
}

func (f deviceListFilter) Query() string {
	v := url.Values{}
	v.Set("sort", f.Sort)
	v.Set("dir", f.Dir)
	if f.Country != "" {
		v.Set("country", f.Country)
	}
	return v.Encode()
}

// QueryWith merges extra params (e.g. range) onto the list filter query.
func (f deviceListFilter) QueryWith(extra url.Values) string {
	v := url.Values{}
	for k, vals := range extra {
		for _, val := range vals {
			v.Add(k, val)
		}
	}
	base, _ := url.ParseQuery(f.Query())
	for k, vals := range base {
		for _, val := range vals {
			v.Set(k, val)
		}
	}
	return v.Encode()
}

func (f deviceListFilter) IsSort(s string) bool { return f.Sort == s }
func (f deviceListFilter) IsDir(d string) bool  { return f.Dir == d }
func (f deviceListFilter) IsCountry(c string) bool {
	if c == "" {
		return f.Country == ""
	}
	return f.Country == c
}

func (h *Handler) listDevices(limit int, f deviceListFilter) ([]deviceListItem, error) {
	if limit <= 0 {
		limit = 200
	}

	orderCol := "d.created_at"
	switch f.Sort {
	case "seen":
		orderCol = "COALESCE(d.last_seen_at, d.created_at)"
	case "traffic":
		orderCol = "traffic_bytes"
	default:
		orderCol = "d.created_at"
	}
	orderDir := "DESC"
	if f.Dir == "asc" {
		orderDir = "ASC"
	}

	args := []any{}
	where := ""
	switch f.Country {
	case "":
		// all
	case "?":
		where = " WHERE d.last_client_country IS NULL OR TRIM(d.last_client_country) = '' "
	default:
		where = " WHERE UPPER(TRIM(d.last_client_country)) = ? "
		args = append(args, f.Country)
	}
	args = append(args, limit)

	q := fmt.Sprintf(`
		SELECT d.id, d.platform, COALESCE(d.model,''), COALESCE(d.os_version,''),
			COALESCE(d.app_version,''), COALESCE(d.app_build,0),
			COALESCE(d.last_seen_at, d.created_at),
			d.created_at,
			COALESCE(NULLIF(TRIM(d.last_client_country), ''), '?'),
			(SELECT COUNT(*) FROM wireguard_peers p WHERE p.device_id = d.id) AS peer_count,
			COALESCE((
				SELECT SUM(p.rx_bytes + p.tx_bytes) FROM wireguard_peers p WHERE p.device_id = d.id
			), 0) AS traffic_bytes
		FROM devices d
		%s
		ORDER BY %s %s, d.created_at DESC
		LIMIT ?`, where, orderCol, orderDir)

	rows, err := h.DB.Query(q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var list []deviceListItem
	for rows.Next() {
		var x deviceListItem
		var last, created time.Time
		if err := rows.Scan(
			&x.ID, &x.Platform, &x.Model, &x.OS, &x.AppVersion, &x.Build,
			&last, &created, &x.Country, &x.PeerCount, &x.TrafficBytes,
		); err != nil {
			return nil, err
		}
		x.LastSeen = compactTime(last)
		x.Created = compactTime(created)
		x.TrafficHuman = humanBytes(x.TrafficBytes)
		list = append(list, x)
	}
	return list, rows.Err()
}

func (h *Handler) listDeviceCountries() ([]string, error) {
	rows, err := h.DB.Query(`
		SELECT DISTINCT UPPER(TRIM(last_client_country)) AS cc
		FROM devices
		WHERE last_client_country IS NOT NULL AND TRIM(last_client_country) <> ''
		ORDER BY cc`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var cc string
		if err := rows.Scan(&cc); err != nil {
			return nil, err
		}
		out = append(out, cc)
	}
	return out, rows.Err()
}

func (h *Handler) listUsers(limit int) ([]userListItem, error) {
	if limit <= 0 {
		limit = 200
	}
	rows, err := h.DB.Query(`
		SELECT u.id, u.status, u.created_at, COUNT(d.id)
		FROM users u LEFT JOIN devices d ON d.user_id = u.id
		GROUP BY u.id ORDER BY u.created_at DESC LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var list []userListItem
	for rows.Next() {
		var x userListItem
		var created time.Time
		if err := rows.Scan(&x.ID, &x.Status, &created, &x.Devices); err != nil {
			return nil, err
		}
		x.Created = created.UTC().Format(time.RFC3339)
		list = append(list, x)
	}
	return list, rows.Err()
}

func (h *Handler) listDBTables() ([]dbTableInfo, string, error) {
	rows, err := h.DB.Query(`
		SELECT table_name, table_rows, engine, COALESCE(table_comment, '')
		FROM information_schema.tables
		WHERE table_schema = DATABASE()
		ORDER BY table_name`)
	if err != nil {
		return nil, "", err
	}
	defer rows.Close()

	var tables []dbTableInfo
	for rows.Next() {
		var t dbTableInfo
		var engine sql.NullString
		var approx sql.NullInt64
		if err := rows.Scan(&t.Name, &approx, &engine, &t.Comment); err != nil {
			return nil, "", err
		}
		if engine.Valid {
			t.Engine = engine.String
		}
		var exact int64
		q := fmt.Sprintf("SELECT COUNT(*) FROM `%s`", t.Name)
		if err := h.DB.QueryRow(q).Scan(&exact); err == nil {
			t.Rows = exact
		} else if approx.Valid {
			t.Rows = approx.Int64
		}
		tables = append(tables, t)
	}
	var dbName string
	_ = h.DB.QueryRow(`SELECT DATABASE()`).Scan(&dbName)
	return tables, dbName, rows.Err()
}
