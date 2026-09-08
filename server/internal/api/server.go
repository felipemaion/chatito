package api

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"time"

	"github.com/felipemaion/piriquito/server/internal/store"
)

// Notifier is told about freshly queued envelopes so it can push them over
// live connections. Implemented by the websocket hub.
type Notifier interface {
	Notify(deviceID string, envs []store.Envelope)
}

// Disconnecter is optionally implemented by a Notifier to drop the live
// connection of a device that no longer exists.
type Disconnecter interface {
	Disconnect(deviceID string)
}

// Pusher wakes a device through a push service (FCM) without any content.
type Pusher interface {
	Wake(ctx context.Context, fcmToken string) error
}

// ErrPushUnregistered is returned (wrapped) by a Pusher when the push service
// reports the token as no longer valid; the server then forgets the token.
var ErrPushUnregistered = errors.New("push token unregistered")

// Options configures a Server.
type Options struct {
	Store     *store.Store
	Notifier  Notifier         // optional
	Pusher    Pusher           // optional
	WS        http.Handler     // optional, mounted at GET /v1/ws behind auth
	Now       func() time.Time // optional, defaults to time.Now
	RateLimit func() int       // optional, requests per minute per device (default 60; <=0 disables)
	// RegisterRateLimit bounds POST /v1/devices attempts per minute per
	// client IP, to slow down invite-code brute forcing. Optional, default
	// 10; <=0 disables.
	RegisterRateLimit func() int
	Logger            *slog.Logger // optional
}

// Server holds the HTTP handlers of the relay.
type Server struct {
	store      *store.Store
	notifier   Notifier
	pusher     Pusher
	ws         http.Handler
	now        func() time.Time
	limiter    *rateLimiter
	regLimiter *rateLimiter
	log        *slog.Logger
}

const defaultRegisterRateLimit = 10

// Retention constants (docs/PROTOCOL.md §6).
const (
	EnvelopeTTL = 30 * 24 * time.Hour
	BlobTTL     = 30 * 24 * time.Hour
	InviteTTL   = 7 * 24 * time.Hour
)

// New builds a Server from options.
func New(opts Options) *Server {
	s := &Server{store: opts.Store, notifier: opts.Notifier, pusher: opts.Pusher, ws: opts.WS, now: opts.Now, log: opts.Logger}
	if s.now == nil {
		s.now = time.Now
	}
	if s.log == nil {
		s.log = slog.Default()
	}
	limit := func() int { return 60 }
	if opts.RateLimit != nil {
		limit = opts.RateLimit
	}
	s.limiter = newRateLimiter(limit, s.now)
	regLimit := func() int { return defaultRegisterRateLimit }
	if opts.RegisterRateLimit != nil {
		regLimit = opts.RegisterRateLimit
	}
	s.regLimiter = newRateLimiter(regLimit, s.now)
	return s
}

// Handler returns the routed HTTP handler.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", HealthHandler)
	mux.Handle("POST /v1/devices", s.registerRateLimited(s.h(s.register)))

	auth := func(fn handlerFunc) http.Handler { return s.authenticate(s.h(fn)) }
	mux.Handle("GET /v1/me", auth(s.me))
	mux.Handle("GET /v1/directory", auth(s.directory))
	mux.Handle("PUT /v1/devices/me/push", auth(s.setPush))
	mux.Handle("DELETE /v1/devices/{id}", auth(s.deleteDevice))
	mux.Handle("POST /v1/envelopes", auth(s.postEnvelopes))
	mux.Handle("GET /v1/envelopes", auth(s.listEnvelopes))
	mux.Handle("POST /v1/envelopes/ack", auth(s.ackEnvelopes))
	mux.Handle("POST /v1/blobs", auth(s.createBlob))
	mux.Handle("PUT /v1/blobs/{id}/chunks/{n}", auth(s.putChunk))
	mux.Handle("POST /v1/blobs/{id}/complete", auth(s.completeBlob))
	mux.Handle("GET /v1/blobs/{id}", auth(s.getBlob))
	mux.Handle("DELETE /v1/blobs/{id}", auth(s.deleteBlob))
	mux.Handle("POST /v1/admin/invites", auth(s.adminInvite))
	mux.Handle("POST /v1/admin/users/{id}/role", auth(s.adminSetRole))
	if s.ws != nil {
		mux.Handle("GET /v1/ws", s.authenticate(s.ws))
	}
	mux.HandleFunc("/v1/", func(w http.ResponseWriter, _ *http.Request) {
		writeError(w, http.StatusNotFound, CodeNotFound, "no such route")
	})
	return mux
}

// handlerFunc is a handler that returns an error instead of writing it.
type handlerFunc func(w http.ResponseWriter, r *http.Request) error

func (s *Server) h(fn handlerFunc) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := fn(w, r); err != nil {
			writeErr(w, s.log, err)
		}
	})
}

// decodeJSON reads a JSON body of at most limit bytes into v.
func decodeJSON(w http.ResponseWriter, r *http.Request, limit int64, v any) error {
	r.Body = http.MaxBytesReader(w, r.Body, limit)
	dec := json.NewDecoder(r.Body)
	if err := dec.Decode(v); err != nil {
		var mbe *http.MaxBytesError
		if errors.As(err, &mbe) {
			return err
		}
		return errorf(http.StatusBadRequest, CodeValidation, "invalid JSON body: "+err.Error())
	}
	if _, err := io.Copy(io.Discard, r.Body); err != nil {
		return err
	}
	return nil
}

func b64enc(b []byte) string { return base64.StdEncoding.EncodeToString(b) }

// ValidateIdentityKey checks a base64 X25519 public key (32 bytes).
func ValidateIdentityKey(s string) error {
	b, err := base64.StdEncoding.DecodeString(s)
	if err != nil || len(b) != 32 {
		return errorf(http.StatusBadRequest, CodeValidation, "identity_key must be 32 bytes in base64")
	}
	return nil
}

// ValidateNonce checks a base64 crypto_box nonce (24 bytes).
func ValidateNonce(s string) error {
	b, err := base64.StdEncoding.DecodeString(s)
	if err != nil || len(b) != 24 {
		return errorf(http.StatusBadRequest, CodeValidation, "nonce must be 24 bytes in base64")
	}
	return nil
}
