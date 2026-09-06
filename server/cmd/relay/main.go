// Command relay runs the Chatito blind relay server.
package main

import (
	"log"
	"net/http"
	"os"

	"github.com/felipemaion/chatito/server/internal/api"
)

func main() {
	addr := os.Getenv("RELAY_ADDR")
	if addr == "" {
		addr = ":8080"
	}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", api.HealthHandler)
	log.Printf("relay listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, mux))
}
