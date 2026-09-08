// Package site serve a página pública do Piriquito (sobre o app e downloads)
// embutida no binário do relay. Só GET; qualquer outro caminho é 404 para não
// vazar a estrutura de assets.
package site

import (
	"embed"
	"net/http"
	"strings"
)

//go:embed assets/index.html assets/logo.svg assets/icon.svg
var assets embed.FS

// Handler devolve o roteador da página: "/" (index), "/logo.svg" e "/icon.svg".
func Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /{$}", serve("assets/index.html", "text/html; charset=utf-8", "no-cache"))
	mux.HandleFunc("GET /logo.svg", serve("assets/logo.svg", "image/svg+xml", "public, max-age=86400"))
	mux.HandleFunc("GET /icon.svg", serve("assets/icon.svg", "image/svg+xml", "public, max-age=86400"))
	mux.HandleFunc("GET /", func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, "não encontrado", http.StatusNotFound)
	})
	return mux
}

func serve(name, contentType, cache string) http.HandlerFunc {
	body, err := assets.ReadFile(name)
	if err != nil {
		panic("site: asset embutido ausente: " + name) // só acontece em build quebrado
	}
	return func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("Content-Type", contentType)
		h.Set("Cache-Control", cache)
		h.Set("X-Content-Type-Options", "nosniff")
		if strings.HasPrefix(contentType, "text/html") {
			h.Set("Content-Security-Policy", "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; connect-src 'self' https://api.github.com; frame-ancestors 'none'")
			h.Set("Referrer-Policy", "strict-origin-when-cross-origin")
		}
		_, _ = w.Write(body)
	}
}
