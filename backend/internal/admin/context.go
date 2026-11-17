package admin

import (
	"context"
	"net/http"
)

type ctxKey string

const (
	ctxAdminID ctxKey = "admin_id"
	ctxCSRF    ctxKey = "csrf"
)

func withAdmin(ctx context.Context, adminID, csrf string) context.Context {
	ctx = context.WithValue(ctx, ctxAdminID, adminID)
	ctx = context.WithValue(ctx, ctxCSRF, csrf)
	return ctx
}

func csrfFrom(r *http.Request) string {
	if v, ok := r.Context().Value(ctxCSRF).(string); ok {
		return v
	}
	return ""
}

func adminIDFrom(r *http.Request) string {
	if v, ok := r.Context().Value(ctxAdminID).(string); ok {
		return v
	}
	return ""
}
