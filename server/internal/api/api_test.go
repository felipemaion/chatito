package api_test

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/felipemaion/piriquito/server/internal/api"
	"github.com/felipemaion/piriquito/server/internal/store"
)

type fakeNotifier struct {
	mu    sync.Mutex
	calls map[string][]store.Envelope
}

func (f *fakeNotifier) Notify(deviceID string, envs []store.Envelope) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.calls == nil {
		f.calls = map[string][]store.Envelope{}
	}
	f.calls[deviceID] = append(f.calls[deviceID], envs...)
}

func (f *fakeNotifier) count(deviceID string) int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.calls[deviceID])
}

type fakePusher struct {
	mu     sync.Mutex
	tokens []string
	err    error
}

func (f *fakePusher) Wake(_ context.Context, token string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.tokens = append(f.tokens, token)
	return f.err
}

func (f *fakePusher) sent() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]string(nil), f.tokens...)
}

type env struct {
	t            *testing.T
	srv          *httptest.Server
	st           *store.Store
	notifier     *fakeNotifier
	pusher       *fakePusher
	now          time.Time
	rate         int
	registerRate int
}

func newEnv(t *testing.T) *env {
	t.Helper()
	st, err := store.Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = st.Close() })
	e := &env{t: t, st: st, notifier: &fakeNotifier{}, pusher: &fakePusher{},
		now: time.Date(2026, 9, 6, 18, 0, 0, 0, time.UTC), rate: 1000, registerRate: 1000}
	s := api.New(api.Options{
		Store: st, Notifier: e.notifier, Pusher: e.pusher,
		Now:               func() time.Time { return e.now },
		RateLimit:         func() int { return e.rate },
		RegisterRateLimit: func() int { return e.registerRate },
		Logger:            slog.New(slog.DiscardHandler),
	})
	e.srv = httptest.NewServer(s.Handler())
	t.Cleanup(e.srv.Close)
	return e
}

type resp struct {
	code int
	hdr  http.Header
	body []byte
}

func (r resp) json(t *testing.T, v any) {
	t.Helper()
	if err := json.Unmarshal(r.body, v); err != nil {
		t.Fatalf("decode %s: %v", r.body, err)
	}
}

func (r resp) errCode(t *testing.T) string {
	t.Helper()
	var er api.ErrorResponse
	r.json(t, &er)
	return er.Error.Code
}

func (e *env) do(method, path, token string, body any, hdr ...string) resp {
	e.t.Helper()
	var rd io.Reader
	switch b := body.(type) {
	case nil:
	case []byte:
		rd = bytes.NewReader(b)
	case string:
		rd = strings.NewReader(b)
	default:
		j, _ := json.Marshal(b)
		rd = bytes.NewReader(j)
	}
	req, _ := http.NewRequest(method, e.srv.URL+path, rd)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	if _, ok := body.([]byte); ok {
		req.Header.Set("Content-Type", "application/octet-stream")
	} else if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	for i := 0; i+1 < len(hdr); i += 2 {
		req.Header.Set(hdr[i], hdr[i+1])
	}
	res, err := e.srv.Client().Do(req)
	if err != nil {
		e.t.Fatalf("%s %s: %v", method, path, err)
	}
	defer func() { _ = res.Body.Close() }()
	b, _ := io.ReadAll(res.Body)
	return resp{code: res.StatusCode, hdr: res.Header, body: b}
}

func (e *env) invite(userID string) string {
	e.t.Helper()
	inv, err := e.st.CreateInvite(context.Background(), userID, e.now.Add(7*24*time.Hour))
	if err != nil {
		e.t.Fatal(err)
	}
	return inv.Code
}

const identityKey = "hSDwCYkwp1R0i33ctD73Wg2/Og0mOBr066SpjqqbTmo="

// register creates a device for userID through the API and returns (device id, token).
func (e *env) register(userID, name string) (string, string) {
	e.t.Helper()
	r := e.do("POST", "/v1/devices", "", api.RegisterRequest{
		InviteCode: e.invite(userID), DeviceName: name, Platform: "macos", IdentityKey: identityKey,
	})
	if r.code != 201 {
		e.t.Fatalf("register %s: %d %s", name, r.code, r.body)
	}
	var out api.RegisterResponse
	r.json(e.t, &out)
	return out.Device.ID, out.Token
}

func (e *env) admin() store.User {
	e.t.Helper()
	u, err := e.st.CreateUser(context.Background(), "Felipe", store.RoleAdmin)
	if err != nil {
		e.t.Fatal(err)
	}
	return u
}

func (e *env) member(name string) store.User {
	e.t.Helper()
	u, err := e.st.CreateUser(context.Background(), name, store.RoleMember)
	if err != nil {
		e.t.Fatal(err)
	}
	return u
}

func TestHealthz(t *testing.T) {
	e := newEnv(t)
	r := e.do("GET", "/healthz", "", nil)
	if r.code != 200 || !strings.Contains(string(r.body), `"ok"`) {
		t.Fatalf("healthz = %d %s", r.code, r.body)
	}
}

func TestRegister(t *testing.T) {
	e := newEnv(t)
	u := e.admin()
	code := e.invite(u.ID)

	r := e.do("POST", "/v1/devices", "", api.RegisterRequest{InviteCode: code, DeviceName: "Mac", Platform: "macos", IdentityKey: identityKey})
	if r.code != 201 {
		t.Fatalf("register = %d %s", r.code, r.body)
	}
	var out api.RegisterResponse
	r.json(t, &out)
	if out.User.ID != u.ID || out.User.Role != "admin" || out.User.Name != "Felipe" {
		t.Fatalf("user = %+v", out.User)
	}
	if !strings.HasPrefix(out.Device.ID, "dev_") || out.Device.UserID != u.ID || out.Device.IdentityKey != identityKey ||
		out.Device.Platform != "macos" || out.Device.Name != "Mac" || out.Device.CreatedAt != "2026-09-06T18:00:00Z" {
		t.Fatalf("device = %+v", out.Device)
	}
	if len(out.Token) < 40 {
		t.Fatalf("token = %q", out.Token)
	}
	// token works
	me := e.do("GET", "/v1/me", out.Token, nil)
	if me.code != 200 {
		t.Fatalf("me = %d %s", me.code, me.body)
	}
	var meOut api.MeResponse
	me.json(t, &meOut)
	if meOut.Device.ID != out.Device.ID || meOut.User.ID != u.ID {
		t.Fatalf("me = %+v", meOut)
	}

	// invite is single use
	r = e.do("POST", "/v1/devices", "", api.RegisterRequest{InviteCode: code, DeviceName: "Mac", Platform: "macos", IdentityKey: identityKey})
	if r.code != 403 || r.errCode(t) != "invalid_invite" {
		t.Fatalf("reuse = %d %s", r.code, r.body)
	}
	// validation
	for name, req := range map[string]api.RegisterRequest{
		"no name":   {InviteCode: e.invite(u.ID), Platform: "macos", IdentityKey: identityKey},
		"no plat":   {InviteCode: e.invite(u.ID), DeviceName: "x", IdentityKey: identityKey},
		"bad key":   {InviteCode: e.invite(u.ID), DeviceName: "x", Platform: "macos", IdentityKey: "not-base64!"},
		"short":     {InviteCode: e.invite(u.ID), DeviceName: "x", Platform: "macos", IdentityKey: "AAAA"},
		"no code":   {DeviceName: "x", Platform: "macos", IdentityKey: identityKey},
		"long name": {InviteCode: e.invite(u.ID), DeviceName: strings.Repeat("x", 200), Platform: "macos", IdentityKey: identityKey},
	} {
		r = e.do("POST", "/v1/devices", "", req)
		if r.code != 400 || r.errCode(t) != "validation" {
			t.Fatalf("%s = %d %s", name, r.code, r.body)
		}
	}
	r = e.do("POST", "/v1/devices", "", "{not json")
	if r.code != 400 || r.errCode(t) != "validation" {
		t.Fatalf("bad json = %d %s", r.code, r.body)
	}
	r = e.do("POST", "/v1/devices", "", `{"invite_code":"`+strings.Repeat("x", 2<<20)+`"}`)
	if r.code != 413 || r.errCode(t) != "payload_too_large" {
		t.Fatalf("huge body = %d %s", r.code, r.body)
	}
}

func TestAuth(t *testing.T) {
	e := newEnv(t)
	u := e.admin()
	_, token := e.register(u.ID, "Mac")

	for name, hdr := range map[string]string{"none": "", "wrong": "Bearer nope", "basic": "Basic abc", "empty bearer": "Bearer "} {
		req, _ := http.NewRequest("GET", e.srv.URL+"/v1/me", nil)
		if hdr != "" {
			req.Header.Set("Authorization", hdr)
		}
		res, err := e.srv.Client().Do(req)
		if err != nil {
			t.Fatal(err)
		}
		b, _ := io.ReadAll(res.Body)
		_ = res.Body.Close()
		if res.StatusCode != 401 || !strings.Contains(string(b), `"unauthorized"`) {
			t.Fatalf("%s = %d %s", name, res.StatusCode, b)
		}
	}
	// query token fallback works too (needed by WS clients)
	r := e.do("GET", "/v1/me?token="+token, "", nil)
	if r.code != 200 {
		t.Fatalf("query token = %d %s", r.code, r.body)
	}
	// unknown route under /v1 is JSON 404
	r = e.do("GET", "/v1/nope", token, nil)
	if r.code != 404 || r.errCode(t) != "not_found" {
		t.Fatalf("unknown = %d %s", r.code, r.body)
	}
}

func TestRateLimit(t *testing.T) {
	e := newEnv(t)
	e.rate = 3
	u := e.admin()
	_, token := e.register(u.ID, "Mac")
	var last resp
	for range 3 {
		if last = e.do("GET", "/v1/me", token, nil); last.code != 200 {
			t.Fatalf("under limit = %d", last.code)
		}
	}
	last = e.do("GET", "/v1/me", token, nil)
	if last.code != 429 || last.errCode(t) != "rate_limited" || last.hdr.Get("Retry-After") == "" {
		t.Fatalf("over limit = %d %s hdr=%v", last.code, last.body, last.hdr)
	}
	e.now = e.now.Add(61 * time.Second)
	if last = e.do("GET", "/v1/me", token, nil); last.code != 200 {
		t.Fatalf("after window = %d", last.code)
	}
}

// TestRegisterRateLimitByIP guards brute forcing of invite codes: POST
// /v1/devices is rate limited per client IP even though it needs no token.
func TestRegisterRateLimitByIP(t *testing.T) {
	e := newEnv(t)
	e.registerRate = 3
	u := e.admin()
	req := func() api.RegisterRequest {
		return api.RegisterRequest{InviteCode: e.invite(u.ID), DeviceName: "x", Platform: "macos", IdentityKey: identityKey}
	}
	var last resp
	for range 3 {
		if last = e.do("POST", "/v1/devices", "", req()); last.code != 201 {
			t.Fatalf("under limit = %d %s", last.code, last.body)
		}
	}
	last = e.do("POST", "/v1/devices", "", req())
	if last.code != 429 || last.errCode(t) != "rate_limited" || last.hdr.Get("Retry-After") == "" {
		t.Fatalf("over limit = %d %s hdr=%v", last.code, last.body, last.hdr)
	}
	e.now = e.now.Add(61 * time.Second)
	if last = e.do("POST", "/v1/devices", "", req()); last.code != 201 {
		t.Fatalf("after window = %d %s", last.code, last.body)
	}
}

func TestPushAndDeleteDevice(t *testing.T) {
	e := newEnv(t)
	adm := e.admin()
	mem := e.member("Mãe")
	admDev, admTok := e.register(adm.ID, "Mac")
	memDev, memTok := e.register(mem.ID, "Galaxy")
	memDev2, memTok2 := e.register(mem.ID, "Tablet")

	r := e.do("PUT", "/v1/devices/me/push", memTok, map[string]any{"fcm_token": "fcm-1"})
	if r.code != 204 {
		t.Fatalf("set push = %d %s", r.code, r.body)
	}
	d, _ := e.st.GetDevice(context.Background(), memDev)
	if d.FCMToken == nil || *d.FCMToken != "fcm-1" {
		t.Fatalf("fcm = %v", d.FCMToken)
	}
	r = e.do("PUT", "/v1/devices/me/push", memTok, map[string]any{"fcm_token": nil})
	if r.code != 204 {
		t.Fatalf("clear push = %d %s", r.code, r.body)
	}
	if d, _ = e.st.GetDevice(context.Background(), memDev); d.FCMToken != nil {
		t.Fatalf("fcm should be cleared")
	}
	r = e.do("PUT", "/v1/devices/me/push", memTok, map[string]any{"fcm_token": strings.Repeat("x", 5000)})
	if r.code != 400 {
		t.Fatalf("long fcm = %d", r.code)
	}

	// member cannot delete admin's device
	r = e.do("DELETE", "/v1/devices/"+admDev, memTok, nil)
	if r.code != 403 || r.errCode(t) != "forbidden" {
		t.Fatalf("member delete admin = %d %s", r.code, r.body)
	}
	// member deletes own other device
	r = e.do("DELETE", "/v1/devices/"+memDev2, memTok, nil)
	if r.code != 204 {
		t.Fatalf("delete own = %d %s", r.code, r.body)
	}
	if r = e.do("GET", "/v1/me", memTok2, nil); r.code != 401 {
		t.Fatalf("deleted device token still valid: %d", r.code)
	}
	// admin deletes member's device
	r = e.do("DELETE", "/v1/devices/"+memDev, admTok, nil)
	if r.code != 204 {
		t.Fatalf("admin delete = %d %s", r.code, r.body)
	}
	r = e.do("DELETE", "/v1/devices/"+memDev, admTok, nil)
	if r.code != 404 || r.errCode(t) != "not_found" {
		t.Fatalf("delete twice = %d %s", r.code, r.body)
	}
}

func TestDirectory(t *testing.T) {
	e := newEnv(t)
	adm := e.admin()
	mem := e.member("Mãe")
	_, admTok := e.register(adm.ID, "MacBook do Felipe")
	e.register(mem.ID, "Galaxy")

	r := e.do("GET", "/v1/directory", admTok, nil)
	if r.code != 200 {
		t.Fatalf("directory = %d %s", r.code, r.body)
	}
	var dir api.DirectoryResponse
	r.json(t, &dir)
	if len(dir.Users) != 2 || dir.Users[0].Name != "Felipe" || dir.Users[0].Role != "admin" || len(dir.Users[0].Devices) != 1 ||
		dir.Users[1].Name != "Mãe" || len(dir.Users[1].Devices) != 1 || dir.Users[1].Devices[0].IdentityKey != identityKey {
		t.Fatalf("dir = %s", r.body)
	}
	if dir.Users[0].Devices[0].CreatedAt != "2026-09-06T18:00:00Z" {
		t.Fatalf("created_at = %q", dir.Users[0].Devices[0].CreatedAt)
	}
	// users without devices still appear, with an empty (not null) list
	e.member("Filho")
	r = e.do("GET", "/v1/directory", admTok, nil)
	if !strings.Contains(string(r.body), `"devices":[]`) {
		t.Fatalf("empty devices should be []: %s", r.body)
	}
}

func b64(n int, fill byte) string {
	return base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{fill}, n))
}

func TestEnvelopes(t *testing.T) {
	e := newEnv(t)
	adm := e.admin()
	mem := e.member("Mãe")
	admDev, admTok := e.register(adm.ID, "Mac")
	memDev, memTok := e.register(mem.ID, "Galaxy")
	_ = e.do("PUT", "/v1/devices/me/push", memTok, map[string]any{"fcm_token": "fcm-mem"})

	post := api.EnvelopesPostRequest{Envelopes: []api.EnvelopeIn{
		{ToDevice: memDev, Nonce: b64(24, 1), Ciphertext: b64(64, 2)},
		{ToDevice: admDev, Nonce: b64(24, 3), Ciphertext: b64(64, 4)},
	}}
	r := e.do("POST", "/v1/envelopes", admTok, post)
	if r.code != 202 {
		t.Fatalf("post = %d %s", r.code, r.body)
	}
	var out api.EnvelopesPostResponse
	r.json(t, &out)
	if len(out.Accepted) != 2 || !strings.HasPrefix(out.Accepted[0].ID, "env_") || out.Accepted[0].ToDevice != memDev || out.Accepted[1].ToDevice != admDev {
		t.Fatalf("accepted = %+v", out.Accepted)
	}
	// realtime + push side effects
	if e.notifier.count(memDev) != 1 || e.notifier.count(admDev) != 1 {
		t.Fatalf("notifier calls = %+v", e.notifier.calls)
	}
	if got := e.pusher.sent(); len(got) != 1 || got[0] != "fcm-mem" {
		t.Fatalf("push sent = %v", got)
	}

	// pending list for member
	r = e.do("GET", "/v1/envelopes", memTok, nil)
	if r.code != 200 {
		t.Fatalf("get = %d %s", r.code, r.body)
	}
	var list api.EnvelopesListResponse
	r.json(t, &list)
	if len(list.Envelopes) != 1 || list.Envelopes[0].ID != out.Accepted[0].ID || list.Envelopes[0].FromDevice != admDev ||
		list.Envelopes[0].ToDevice != memDev || list.Envelopes[0].Nonce != b64(24, 1) || list.Envelopes[0].Ciphertext != b64(64, 2) ||
		list.Envelopes[0].CreatedAt != "2026-09-06T18:00:00Z" {
		t.Fatalf("list = %s", r.body)
	}
	r = e.do("GET", "/v1/envelopes?limit=abc", memTok, nil)
	if r.code != 400 {
		t.Fatalf("bad limit = %d", r.code)
	}
	r = e.do("GET", "/v1/envelopes?limit=0", memTok, nil)
	if r.code != 200 {
		t.Fatalf("limit 0 clamps: %d", r.code)
	}

	// ack removes; ack of someone else's id is ignored; empty list is a 204 too
	r = e.do("POST", "/v1/envelopes/ack", memTok, map[string]any{"ids": []string{out.Accepted[0].ID, out.Accepted[1].ID, "env_nope"}})
	if r.code != 204 {
		t.Fatalf("ack = %d %s", r.code, r.body)
	}
	r = e.do("GET", "/v1/envelopes", memTok, nil)
	r.json(t, &list)
	if len(list.Envelopes) != 0 {
		t.Fatalf("after ack = %s", r.body)
	}
	r = e.do("GET", "/v1/envelopes", admTok, nil)
	r.json(t, &list)
	if len(list.Envelopes) != 1 {
		t.Fatalf("foreign ack must not delete: %s", r.body)
	}
	if r = e.do("POST", "/v1/envelopes/ack", memTok, "{bad"); r.code != 400 {
		t.Fatalf("bad ack = %d", r.code)
	}

	// validation
	cases := map[string]api.EnvelopesPostRequest{
		"empty":        {},
		"bad nonce":    {Envelopes: []api.EnvelopeIn{{ToDevice: memDev, Nonce: b64(23, 1), Ciphertext: b64(64, 2)}}},
		"bad b64":      {Envelopes: []api.EnvelopeIn{{ToDevice: memDev, Nonce: "!!!", Ciphertext: b64(64, 2)}}},
		"short ct":     {Envelopes: []api.EnvelopeIn{{ToDevice: memDev, Nonce: b64(24, 1), Ciphertext: b64(15, 2)}}},
		"bad ct b64":   {Envelopes: []api.EnvelopeIn{{ToDevice: memDev, Nonce: b64(24, 1), Ciphertext: "***"}}},
		"unknown dev":  {Envelopes: []api.EnvelopeIn{{ToDevice: "dev_nope", Nonce: b64(24, 1), Ciphertext: b64(64, 2)}}},
		"no to_device": {Envelopes: []api.EnvelopeIn{{Nonce: b64(24, 1), Ciphertext: b64(64, 2)}}},
	}
	for name, req := range cases {
		r = e.do("POST", "/v1/envelopes", admTok, req)
		if r.code != 400 || r.errCode(t) != "validation" {
			t.Fatalf("%s = %d %s", name, r.code, r.body)
		}
	}
	tooMany := api.EnvelopesPostRequest{}
	for range 101 {
		tooMany.Envelopes = append(tooMany.Envelopes, api.EnvelopeIn{ToDevice: memDev, Nonce: b64(24, 1), Ciphertext: b64(64, 2)})
	}
	if r = e.do("POST", "/v1/envelopes", admTok, tooMany); r.code != 400 {
		t.Fatalf("101 envelopes = %d %s", r.code, r.body)
	}
	big := api.EnvelopesPostRequest{Envelopes: []api.EnvelopeIn{{ToDevice: memDev, Nonce: b64(24, 1), Ciphertext: b64(64*1024+1, 2)}}}
	if r = e.do("POST", "/v1/envelopes", admTok, big); r.code != 413 || r.errCode(t) != "payload_too_large" {
		t.Fatalf("big ciphertext = %d %s", r.code, r.body)
	}
	exact := api.EnvelopesPostRequest{Envelopes: []api.EnvelopeIn{{ToDevice: memDev, Nonce: b64(24, 1), Ciphertext: b64(64*1024, 2)}}}
	if r = e.do("POST", "/v1/envelopes", admTok, exact); r.code != 202 {
		t.Fatalf("64KiB ciphertext = %d %s", r.code, r.body)
	}
	// a push failure must not fail the request, and the token is kept
	e.pusher.err = io.ErrUnexpectedEOF
	if r = e.do("POST", "/v1/envelopes", admTok, exact); r.code != 202 {
		t.Fatalf("push error leaked = %d %s", r.code, r.body)
	}
	if d, _ := e.st.GetDevice(context.Background(), memDev); d.FCMToken == nil {
		t.Fatal("transient push error must keep the token")
	}
	// an unregistered token is forgotten
	e.pusher.err = fmt.Errorf("wrapped: %w", api.ErrPushUnregistered)
	if r = e.do("POST", "/v1/envelopes", admTok, exact); r.code != 202 {
		t.Fatalf("unregistered push leaked = %d %s", r.code, r.body)
	}
	if d, _ := e.st.GetDevice(context.Background(), memDev); d.FCMToken != nil {
		t.Fatal("unregistered token should be cleared")
	}
}

func TestAdmin(t *testing.T) {
	e := newEnv(t)
	adm := e.admin()
	mem := e.member("Mãe")
	_, admTok := e.register(adm.ID, "Mac")
	_, memTok := e.register(mem.ID, "Galaxy")

	// member is forbidden
	r := e.do("POST", "/v1/admin/invites", memTok, map[string]any{"user_name": "Filho"})
	if r.code != 403 || r.errCode(t) != "forbidden" {
		t.Fatalf("member invite = %d %s", r.code, r.body)
	}
	// new user by name
	r = e.do("POST", "/v1/admin/invites", admTok, map[string]any{"user_name": "Filho"})
	if r.code != 201 {
		t.Fatalf("invite new = %d %s", r.code, r.body)
	}
	var inv api.InviteResponse
	r.json(t, &inv)
	if len(inv.Code) != 9 || !strings.HasPrefix(inv.UserID, "usr_") || inv.ExpiresAt != "2026-09-13T18:00:00Z" {
		t.Fatalf("invite = %+v", inv)
	}
	filho, _ := e.st.GetUserByName(context.Background(), "Filho")
	if filho.Role != "member" || filho.ID != inv.UserID {
		t.Fatalf("filho = %+v", filho)
	}
	// existing user by name reuses it; by id works too
	r = e.do("POST", "/v1/admin/invites", admTok, map[string]any{"user_name": "Filho"})
	r.json(t, &inv)
	if r.code != 201 || inv.UserID != filho.ID {
		t.Fatalf("invite existing = %d %+v", r.code, inv)
	}
	r = e.do("POST", "/v1/admin/invites", admTok, map[string]any{"user_id": mem.ID})
	r.json(t, &inv)
	if r.code != 201 || inv.UserID != mem.ID {
		t.Fatalf("invite by id = %d %+v", r.code, inv)
	}
	// the invite actually registers
	r = e.do("POST", "/v1/devices", "", api.RegisterRequest{InviteCode: strings.ToLower(inv.Code), DeviceName: "Tab", Platform: "android", IdentityKey: identityKey})
	if r.code != 201 {
		t.Fatalf("register with invite = %d %s", r.code, r.body)
	}
	for name, body := range map[string]any{"none": map[string]any{}, "unknown id": map[string]any{"user_id": "usr_nope"}, "bad": "{"} {
		r = e.do("POST", "/v1/admin/invites", admTok, body)
		if r.code != 400 && r.code != 404 {
			t.Fatalf("%s = %d %s", name, r.code, r.body)
		}
	}

	// role changes
	r = e.do("POST", "/v1/admin/users/"+mem.ID+"/role", admTok, map[string]any{"role": "admin"})
	if r.code != 204 {
		t.Fatalf("set role = %d %s", r.code, r.body)
	}
	if r = e.do("POST", "/v1/admin/invites", memTok, map[string]any{"user_name": "X"}); r.code != 201 {
		t.Fatalf("promoted member should be admin now: %d", r.code)
	}
	r = e.do("POST", "/v1/admin/users/"+mem.ID+"/role", admTok, map[string]any{"role": "god"})
	if r.code != 400 {
		t.Fatalf("bad role = %d", r.code)
	}
	r = e.do("POST", "/v1/admin/users/usr_nope/role", admTok, map[string]any{"role": "member"})
	if r.code != 404 {
		t.Fatalf("role unknown user = %d", r.code)
	}
	r = e.do("POST", "/v1/admin/users/"+adm.ID+"/role", admTok, "{")
	if r.code != 400 {
		t.Fatalf("role bad json = %d", r.code)
	}
}
