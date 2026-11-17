package admin

import (
	"database/sql"
	"fmt"
	"net/http"
	"regexp"
	"strconv"
	"strings"
)

var safeIdent = regexp.MustCompile(`^[a-zA-Z0-9_]+$`)

type dbTableInfo struct {
	Name    string
	Rows    int64
	Engine  string
	Comment string
}

type dbColumnInfo struct {
	Name       string
	Type       string
	Nullable   string
	Key        string
	Default    string
	Extra      string
	Comment    string
}

func (h *Handler) DatabaseIndex(w http.ResponseWriter, r *http.Request) {
	rows, err := h.DB.Query(`
		SELECT table_name, table_rows, engine, COALESCE(table_comment, '')
		FROM information_schema.tables
		WHERE table_schema = DATABASE()
		ORDER BY table_name`)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	defer rows.Close()

	var tables []dbTableInfo
	for rows.Next() {
		var t dbTableInfo
		var engine sql.NullString
		var approx sql.NullInt64
		if err := rows.Scan(&t.Name, &approx, &engine, &t.Comment); err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		if engine.Valid {
			t.Engine = engine.String
		}
		// Exact count for small admin DB
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

	_ = h.Tmpl.ExecuteTemplate(w, "database.html", map[string]any{
		"DBName": dbName,
		"Tables": tables,
		"CSRF":   csrfFrom(r),
	})
}

func (h *Handler) DatabaseTable(w http.ResponseWriter, r *http.Request) {
	name := strings.TrimPrefix(r.URL.Path, "/admin/database/")
	name = strings.Trim(name, "/")
	if name == "" || !safeIdent.MatchString(name) {
		http.Error(w, "invalid table", 400)
		return
	}
	if !h.tableExists(name) {
		http.Error(w, "table not found", 404)
		return
	}

	limit := 100
	if v := r.URL.Query().Get("limit"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 && n <= 500 {
			limit = n
		}
	}
	offset := 0
	if v := r.URL.Query().Get("offset"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n >= 0 {
			offset = n
		}
	}

	cols, err := h.describeTable(name)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}

	var total int64
	_ = h.DB.QueryRow(fmt.Sprintf("SELECT COUNT(*) FROM `%s`", name)).Scan(&total)

	q := fmt.Sprintf("SELECT * FROM `%s` LIMIT %d OFFSET %d", name, limit, offset)
	dataRows, err := h.DB.Query(q)
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}
	defer dataRows.Close()

	colNames, err := dataRows.Columns()
	if err != nil {
		http.Error(w, err.Error(), 500)
		return
	}

	var preview [][]string
	for dataRows.Next() {
		raw := make([]any, len(colNames))
		ptrs := make([]any, len(colNames))
		for i := range raw {
			ptrs[i] = &raw[i]
		}
		if err := dataRows.Scan(ptrs...); err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		line := make([]string, len(colNames))
		for i, v := range raw {
			line[i] = formatCell(v)
		}
		preview = append(preview, line)
	}

	_ = h.Tmpl.ExecuteTemplate(w, "database_table.html", map[string]any{
		"Table":    name,
		"Columns":  cols,
		"ColNames": colNames,
		"Rows":     preview,
		"Total":    total,
		"Limit":    limit,
		"Offset":   offset,
		"Next":     offset + limit,
		"HasMore":  int64(offset+limit) < total,
		"CSRF":     csrfFrom(r),
	})
}

func (h *Handler) tableExists(name string) bool {
	var n int
	err := h.DB.QueryRow(`
		SELECT COUNT(*) FROM information_schema.tables
		WHERE table_schema = DATABASE() AND table_name = ?`, name).Scan(&n)
	return err == nil && n == 1
}

func (h *Handler) describeTable(name string) ([]dbColumnInfo, error) {
	rows, err := h.DB.Query(`
		SELECT column_name, column_type, is_nullable, column_key,
			COALESCE(column_default, ''), extra, COALESCE(column_comment, '')
		FROM information_schema.columns
		WHERE table_schema = DATABASE() AND table_name = ?
		ORDER BY ordinal_position`, name)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []dbColumnInfo
	for rows.Next() {
		var c dbColumnInfo
		if err := rows.Scan(&c.Name, &c.Type, &c.Nullable, &c.Key, &c.Default, &c.Extra, &c.Comment); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

func formatCell(v any) string {
	if v == nil {
		return "NULL"
	}
	switch t := v.(type) {
	case []byte:
		// Hide binary hashes/tokens in preview
		if len(t) == 32 {
			return fmt.Sprintf("<binary %d bytes>", len(t))
		}
		s := string(t)
		if len(s) > 200 {
			return s[:200] + "…"
		}
		return s
	default:
		s := fmt.Sprint(t)
		if len(s) > 200 {
			return s[:200] + "…"
		}
		return s
	}
}
