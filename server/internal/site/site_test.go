package site_test

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/felipemaion/piriquito/server/internal/site"
)

func get(t *testing.T, path string) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	site.Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
	return rec
}

func TestIndex(t *testing.T) {
	rec := get(t, "/")
	if rec.Code != http.StatusOK {
		t.Fatalf("GET / = %d", rec.Code)
	}
	if ct := rec.Header().Get("Content-Type"); !strings.HasPrefix(ct, "text/html") {
		t.Fatalf("content-type = %q", ct)
	}
	body := rec.Body.String()
	for _, want := range []string{"Piriquito", "Download", "github.com/felipemaion/piriquito"} {
		if !strings.Contains(body, want) {
			t.Errorf("index sem %q", want)
		}
	}
}

func TestAssets(t *testing.T) {
	for _, p := range []string{"/logo.svg", "/icon.svg"} {
		rec := get(t, p)
		if rec.Code != http.StatusOK {
			t.Fatalf("GET %s = %d", p, rec.Code)
		}
		if ct := rec.Header().Get("Content-Type"); !strings.HasPrefix(ct, "image/svg+xml") {
			t.Errorf("%s content-type = %q", p, ct)
		}
		if cc := rec.Header().Get("Cache-Control"); cc == "" {
			t.Errorf("%s sem Cache-Control", p)
		}
	}
}

func TestUnknownPathIs404(t *testing.T) {
	for _, p := range []string{"/nada", "/assets/index.html", "/index.html"} {
		if rec := get(t, p); rec.Code != http.StatusNotFound {
			t.Errorf("GET %s = %d, quer 404", p, rec.Code)
		}
	}
}

func TestOnlyGET(t *testing.T) {
	rec := httptest.NewRecorder()
	site.Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/", nil))
	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("POST / = %d, quer 405", rec.Code)
	}
}
