package api

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"strings"

	"github.com/felipemaion/chatito/server/internal/store"
)

type ctxKey int

const (
	ctxDevice ctxKey = iota
	ctxUser
)

// DeviceFrom returns the authenticated device stored in ctx by the middleware.
func DeviceFrom(ctx context.Context) (store.Device, bool) {
	d, ok := ctx.Value(ctxDevice).(store.Device)
	return d, ok
}

// UserFrom returns the authenticated user stored in ctx by the middleware.
func UserFrom(ctx context.Context) (store.User, bool) {
	u, ok := ctx.Value(ctxUser).(store.User)
	return u, ok
}

// bearerToken extracts the token from the Authorization header or, as a
// fallback for websocket clients, from the "token" query parameter.
func bearerToken(r *http.Request) string {
	if h := r.Header.Get("Authorization"); h != "" {
		if len(h) > 7 && strings.EqualFold(h[:7], "Bearer ") {
			return strings.TrimSpace(h[7:])
		}
		return ""
	}
	return r.URL.Query().Get("token")
}

// Authenticate resolves a bearer token to its device and user.
func (s *Server) Authenticate(ctx context.Context, token string) (store.Device, store.User, error) {
	if token == "" {
		return store.Device{}, store.User{}, errorf(http.StatusUnauthorized, CodeUnauthorized, "missing bearer token")
	}
	d, err := s.store.GetDeviceByTokenHash(ctx, store.HashToken(token))
	if errors.Is(err, store.ErrNotFound) {
		return store.Device{}, store.User{}, errorf(http.StatusUnauthorized, CodeUnauthorized, "invalid token")
	}
	if err != nil {
		return store.Device{}, store.User{}, err
	}
	u, err := s.store.GetUser(ctx, d.UserID)
	if err != nil {
		return store.Device{}, store.User{}, err
	}
	return d, u, nil
}

// authenticate is the middleware: bearer → device/user in context, then rate limit.
func (s *Server) authenticate(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		d, u, err := s.Authenticate(r.Context(), bearerToken(r))
		if err != nil {
			writeErr(w, s.log, err)
			return
		}
		if retry, ok := s.limiter.allow(d.ID); !ok {
			w.Header().Set("Retry-After", strconv.Itoa(retry))
			writeError(w, http.StatusTooManyRequests, CodeRateLimited, "rate limit exceeded")
			return
		}
		ctx := context.WithValue(r.Context(), ctxDevice, d)
		ctx = context.WithValue(ctx, ctxUser, u)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// requireAdmin returns a forbidden error unless the caller is an admin.
func requireAdmin(r *http.Request) error {
	u, _ := UserFrom(r.Context())
	if u.Role != store.RoleAdmin {
		return errorf(http.StatusForbidden, CodeForbidden, "admin only")
	}
	return nil
}
