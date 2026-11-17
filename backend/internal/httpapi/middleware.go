package httpapi

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"log/slog"
	"net"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

type ctxKey string

const (
	CtxRequestID ctxKey = "request_id"
	CtxPlatform  ctxKey = "app_platform"
	CtxBuild     ctxKey = "app_build"
	CtxVersion   ctxKey = "app_version"
	CtxDeviceID  ctxKey = "device_id"
	CtxUserID    ctxKey = "user_id"
)

func RequestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get("X-Request-ID")
		if id == "" {
			id = randomID()
		}
		w.Header().Set("X-Request-ID", id)
		ctx := context.WithValue(r.Context(), CtxRequestID, id)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func Logging(log *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()
			rw := &statusWriter{ResponseWriter: w, status: 200}
			next.ServeHTTP(rw, r)
			log.Info("request",
				"method", r.Method,
				"path", r.URL.Path,
				"status", rw.status,
				"ms", time.Since(start).Milliseconds(),
				"request_id", r.Context().Value(CtxRequestID),
			)
		})
	}
}

func Recover(log *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			defer func() {
				if rec := recover(); rec != nil {
					log.Error("panic", "err", rec, "request_id", r.Context().Value(CtxRequestID))
					WriteError(w, http.StatusInternalServerError, "internal", "internal error")
				}
			}()
			next.ServeHTTP(w, r)
		})
	}
}

func AppHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		platform := strings.ToLower(strings.TrimSpace(r.Header.Get("X-App-Platform")))
		build, _ := strconv.Atoi(strings.TrimSpace(r.Header.Get("X-App-Build")))
		version := strings.TrimSpace(r.Header.Get("X-App-Version"))
		ctx := r.Context()
		ctx = context.WithValue(ctx, CtxPlatform, platform)
		ctx = context.WithValue(ctx, CtxBuild, build)
		ctx = context.WithValue(ctx, CtxVersion, version)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

type rateLimiter struct {
	mu       sync.Mutex
	hits     map[string][]time.Time
	limit    int
	window   time.Duration
}

func NewIPRateLimiter(limit int, window time.Duration) *rateLimiter {
	return &rateLimiter{hits: map[string][]time.Time{}, limit: limit, window: window}
}

func (l *rateLimiter) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ip := clientIP(r)
		now := time.Now()
		l.mu.Lock()
		cut := now.Add(-l.window)
		arr := l.hits[ip]
		kept := arr[:0]
		for _, t := range arr {
			if t.After(cut) {
				kept = append(kept, t)
			}
		}
		if len(kept) >= l.limit {
			l.hits[ip] = kept
			l.mu.Unlock()
			WriteError(w, http.StatusTooManyRequests, "rate_limited", "too many requests")
			return
		}
		l.hits[ip] = append(kept, now)
		l.mu.Unlock()
		next.ServeHTTP(w, r)
	})
}

func clientIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		host, _, _ := net.SplitHostPort(r.RemoteAddr)
		if host == "127.0.0.1" || host == "::1" {
			parts := strings.Split(xff, ",")
			return strings.TrimSpace(parts[0])
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(code int) {
	w.status = code
	w.ResponseWriter.WriteHeader(code)
}

func randomID() string {
	b := make([]byte, 8)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}
