package admin

import (
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestStaticHandler(t *testing.T) {
	mux := http.NewServeMux()
	mux.Handle("GET /admin/static/", StaticHandler())
	srv := httptest.NewServer(mux)
	defer srv.Close()
	for _, path := range []string{
		"/admin/static/logo-64.png",
		"/admin/static/favicon.ico",
		"/admin/static/favicon-32.png",
		"/admin/static/apple-touch-icon.png",
	} {
		resp, err := http.Get(srv.URL + path)
		if err != nil {
			t.Fatal(err)
		}
		b, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		if resp.StatusCode != 200 || len(b) < 10 {
			t.Fatalf("%s: status=%d len=%d", path, resp.StatusCode, len(b))
		}
	}
}
