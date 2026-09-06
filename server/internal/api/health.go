// Package api contains the HTTP handlers of the relay.
package api

import (
	"encoding/json"
	"net/http"
)

// HealthHandler answers GET /healthz with {"status":"ok"}.
func HealthHandler(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}
