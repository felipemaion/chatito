package ws_test

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"

	"github.com/felipemaion/piriquito/server/internal/api"
	"github.com/felipemaion/piriquito/server/internal/store"
	"github.com/felipemaion/piriquito/server/internal/ws"
)

type env struct {
	t   *testing.T
	srv *httptest.Server
	st  *store.Store
	hub *ws.Hub
	now time.Time
}

func newEnv(t *testing.T, ping time.Duration) *env {
	t.Helper()
	st, err := store.Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = st.Close() })
	e := &env{t: t, st: st, now: time.Date(2026, 9, 6, 18, 0, 0, 0, time.UTC)}
	e.hub = ws.NewHub(st, ws.Options{PingInterval: ping, Logger: slog.New(slog.DiscardHandler)})
	t.Cleanup(e.hub.Close)
	s := api.New(api.Options{
		Store: st, Notifier: e.hub, WS: e.hub, Logger: slog.New(slog.DiscardHandler),
		Now: func() time.Time { return e.now }, RateLimit: func() int { return 0 },
	})
	e.srv = httptest.NewServer(s.Handler())
	t.Cleanup(e.srv.Close)
	return e
}

func (e *env) register(name string) (string, string) {
	e.t.Helper()
	ctx := context.Background()
	u, err := e.st.CreateUser(ctx, name, store.RoleMember)
	if err != nil {
		e.t.Fatal(err)
	}
	inv, err := e.st.CreateInvite(ctx, u.ID, e.now.Add(time.Hour))
	if err != nil {
		e.t.Fatal(err)
	}
	body, _ := json.Marshal(api.RegisterRequest{InviteCode: inv.Code, DeviceName: name, Platform: "macos", IdentityKey: "hSDwCYkwp1R0i33ctD73Wg2/Og0mOBr066SpjqqbTmo="})
	res, err := http.Post(e.srv.URL+"/v1/devices", "application/json", bytes.NewReader(body))
	if err != nil {
		e.t.Fatal(err)
	}
	defer func() { _ = res.Body.Close() }()
	var out api.RegisterResponse
	if err := json.NewDecoder(res.Body).Decode(&out); err != nil || res.StatusCode != 201 {
		e.t.Fatalf("register: %d %v", res.StatusCode, err)
	}
	return out.Device.ID, out.Token
}

func (e *env) dial(token string, viaQuery bool) *websocket.Conn {
	e.t.Helper()
	url := "ws" + strings.TrimPrefix(e.srv.URL, "http") + "/v1/ws"
	opts := &websocket.DialOptions{HTTPHeader: http.Header{}}
	if viaQuery {
		url += "?token=" + token
	} else {
		opts.HTTPHeader.Set("Authorization", "Bearer "+token)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	c, _, err := websocket.Dial(ctx, url, opts)
	if err != nil {
		e.t.Fatalf("dial: %v", err)
	}
	e.t.Cleanup(func() { _ = c.CloseNow() })
	return c
}

func readFrame(t *testing.T, c *websocket.Conn) map[string]any {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_, data, err := c.Read(ctx)
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	var m map[string]any
	if err := json.Unmarshal(data, &m); err != nil {
		t.Fatalf("bad frame %s: %v", data, err)
	}
	return m
}

// readUntil reads frames, skipping pings, until one of the given type arrives.
func readUntil(t *testing.T, c *websocket.Conn, typ string) map[string]any {
	t.Helper()
	for range 50 {
		f := readFrame(t, c)
		if f["type"] == typ {
			return f
		}
		if f["type"] != "ping" {
			t.Fatalf("unexpected frame %v while waiting for %s", f, typ)
		}
	}
	t.Fatalf("no %s frame", typ)
	return nil
}

func send(t *testing.T, c *websocket.Conn, v any) {
	t.Helper()
	data, _ := json.Marshal(v)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := c.Write(ctx, websocket.MessageText, data); err != nil {
		t.Fatalf("write: %v", err)
	}
}

func closeStatus(t *testing.T, c *websocket.Conn) websocket.StatusCode {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	for {
		_, _, err := c.Read(ctx)
		if err == nil {
			continue
		}
		var ce websocket.CloseError
		if errors.As(err, &ce) {
			return ce.Code
		}
		t.Fatalf("read err without close status: %v", err)
	}
}

func b64(n int, fill byte) string {
	return base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{fill}, n))
}

func (e *env) post(token string, to ...string) []string {
	e.t.Helper()
	req := api.EnvelopesPostRequest{}
	for _, d := range to {
		req.Envelopes = append(req.Envelopes, api.EnvelopeIn{ToDevice: d, Nonce: b64(24, 1), Ciphertext: b64(32, 2)})
	}
	body, _ := json.Marshal(req)
	r, _ := http.NewRequest("POST", e.srv.URL+"/v1/envelopes", bytes.NewReader(body))
	r.Header.Set("Authorization", "Bearer "+token)
	res, err := http.DefaultClient.Do(r)
	if err != nil {
		e.t.Fatal(err)
	}
	defer func() { _ = res.Body.Close() }()
	var out api.EnvelopesPostResponse
	b, _ := io.ReadAll(res.Body)
	if err := json.Unmarshal(b, &out); err != nil || res.StatusCode != 202 {
		e.t.Fatalf("post: %d %s", res.StatusCode, b)
	}
	ids := make([]string, 0, len(out.Accepted))
	for _, a := range out.Accepted {
		ids = append(ids, a.ID)
	}
	return ids
}

func TestHelloFlushAckAndRealtime(t *testing.T) {
	e := newEnv(t, time.Hour)
	aDev, aTok := e.register("A")
	bDev, bTok := e.register("B")
	pending := e.post(aTok, bDev, bDev)

	c := e.dial(bTok, false)
	hello := readFrame(t, c)
	if hello["type"] != "hello" || hello["device_id"] != bDev || hello["pending"].(float64) != 2 {
		t.Fatalf("hello = %v", hello)
	}
	for i, id := range pending {
		f := readFrame(t, c)
		envl, _ := f["envelope"].(map[string]any)
		if f["type"] != "envelope" || envl["id"] != id || envl["from_device"] != aDev || envl["to_device"] != bDev ||
			envl["nonce"] != b64(24, 1) || envl["ciphertext"] != b64(32, 2) || envl["created_at"] != "2026-09-06T18:00:00Z" {
			t.Fatalf("flush[%d] = %v", i, f)
		}
	}
	// ack over ws deletes
	send(t, c, api.AckFrame{Type: "ack", IDs: append(pending, "env_nope")})
	deadline := time.Now().Add(3 * time.Second)
	for {
		n, _ := e.st.CountPendingEnvelopes(context.Background(), bDev)
		if n == 0 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("ack not applied, pending = %d", n)
		}
		time.Sleep(10 * time.Millisecond)
	}
	// realtime delivery of a new envelope
	live := e.post(aTok, bDev)
	f := readUntil(t, c, "envelope")
	if f["envelope"].(map[string]any)["id"] != live[0] {
		t.Fatalf("live = %v", f)
	}
	// client ping gets a pong; unknown frames are ignored
	send(t, c, api.Frame{Type: "ping"})
	if f := readUntil(t, c, "pong"); f["type"] != "pong" {
		t.Fatalf("pong = %v", f)
	}
	send(t, c, map[string]any{"type": "whatever"})
	send(t, c, api.Frame{Type: "ping"})
	readUntil(t, c, "pong")

	// query-string token also works
	c2 := e.dial(aTok, true)
	if h := readFrame(t, c2); h["device_id"] != aDev || h["pending"].(float64) != 0 {
		t.Fatalf("hello via query = %v", h)
	}
	_ = c2.Close(websocket.StatusNormalClosure, "bye")
	_ = c.Close(websocket.StatusNormalClosure, "bye")
}

func TestSecondConnectionReplacesFirst(t *testing.T) {
	e := newEnv(t, time.Hour)
	bDev, bTok := e.register("B")
	c1 := e.dial(bTok, false)
	readFrame(t, c1)
	c2 := e.dial(bTok, false)
	readFrame(t, c2)
	if code := closeStatus(t, c1); code != 4409 {
		t.Fatalf("old conn close code = %d, want 4409", code)
	}
	if e.hub.Connected(bDev) != true {
		t.Fatal("new connection should be registered")
	}
	_ = c2.Close(websocket.StatusNormalClosure, "bye")
	deadline := time.Now().Add(2 * time.Second)
	for e.hub.Connected(bDev) && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if e.hub.Connected(bDev) {
		t.Fatal("connection should be unregistered after close")
	}
}

func TestPingTimeoutClosesSilentClient(t *testing.T) {
	e := newEnv(t, 30*time.Millisecond)
	_, tok := e.register("B")
	c := e.dial(tok, false)
	readFrame(t, c) // hello
	// Never answer pings: the server must close after 2 ping intervals
	// elapse without a pong (~60ms here), having sent only 1 ping — not
	// wait for a 3rd tick.
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	pings := 0
	start := time.Now()
	for {
		_, data, err := c.Read(ctx)
		if err != nil {
			var ce websocket.CloseError
			if !errors.As(err, &ce) || ce.Code != websocket.StatusGoingAway {
				t.Fatalf("expected going-away close, got %v", err)
			}
			break
		}
		var f map[string]any
		if json.Unmarshal(data, &f) == nil && f["type"] == "ping" {
			pings++
		}
	}
	if pings != 1 {
		t.Fatalf("pings sent before close = %d, want 1", pings)
	}
	if time.Since(start) > 500*time.Millisecond {
		t.Fatal("close took too long")
	}
}

func TestPongKeepsConnectionAlive(t *testing.T) {
	e := newEnv(t, 20*time.Millisecond)
	_, tok := e.register("B")
	c := e.dial(tok, false)
	readFrame(t, c)
	pings := 0
	deadline := time.Now().Add(300 * time.Millisecond)
	for time.Now().Before(deadline) {
		f := readFrame(t, c)
		if f["type"] == "ping" {
			pings++
			send(t, c, api.Frame{Type: "pong"})
		}
	}
	if pings < 5 {
		t.Fatalf("expected several pings, got %d", pings)
	}
}

func TestMalformedFrameClosesWithError(t *testing.T) {
	e := newEnv(t, time.Hour)
	_, tok := e.register("B")
	c := e.dial(tok, false)
	readFrame(t, c)
	ctx := context.Background()
	if err := c.Write(ctx, websocket.MessageText, []byte("{not json")); err != nil {
		t.Fatal(err)
	}
	f := readUntil(t, c, "error")
	if f["error"].(map[string]any)["code"] != "validation" {
		t.Fatalf("error frame = %v", f)
	}
	if code := closeStatus(t, c); code != websocket.StatusUnsupportedData {
		t.Fatalf("close code = %d", code)
	}
}

func TestUnauthorizedDialAndDisconnect(t *testing.T) {
	e := newEnv(t, time.Hour)
	url := "ws" + strings.TrimPrefix(e.srv.URL, "http") + "/v1/ws?token=bad"
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_, res, err := websocket.Dial(ctx, url, nil)
	if err == nil || res == nil || res.StatusCode != 401 {
		t.Fatalf("dial with bad token: err=%v res=%v", err, res)
	}

	bDev, bTok := e.register("B")
	c := e.dial(bTok, false)
	readFrame(t, c)
	e.hub.Disconnect(bDev)
	f := readUntil(t, c, "error")
	if f["error"].(map[string]any)["code"] != "unauthorized" {
		t.Fatalf("error frame = %v", f)
	}
	if code := closeStatus(t, c); code != 4401 {
		t.Fatalf("close code = %d, want 4401", code)
	}
	e.hub.Disconnect("dev_nobody") // no-op
}

func TestDeleteDeviceDisconnects(t *testing.T) {
	e := newEnv(t, time.Hour)
	bDev, bTok := e.register("B")
	c := e.dial(bTok, false)
	readFrame(t, c)
	r, _ := http.NewRequest("DELETE", e.srv.URL+"/v1/devices/"+bDev, nil)
	r.Header.Set("Authorization", "Bearer "+bTok)
	res, err := http.DefaultClient.Do(r)
	if err != nil || res.StatusCode != 204 {
		t.Fatalf("delete: %v %v", err, res)
	}
	_ = res.Body.Close()
	if code := closeStatus(t, c); code != 4401 {
		t.Fatalf("close code = %d, want 4401", code)
	}
}

func TestHubCloseDisconnectsAll(t *testing.T) {
	e := newEnv(t, time.Hour)
	_, tok := e.register("B")
	c := e.dial(tok, false)
	readFrame(t, c)
	e.hub.Close()
	if code := closeStatus(t, c); code != websocket.StatusGoingAway {
		t.Fatalf("close code = %d", code)
	}
	// Notify after close is a no-op.
	e.hub.Notify("dev_x", []store.Envelope{{ID: "env_x"}})
}

func TestServeHTTPWithoutAuthContext(t *testing.T) {
	hub := ws.NewHub(nil, ws.Options{Logger: slog.New(slog.DiscardHandler)})
	rec := httptest.NewRecorder()
	hub.ServeHTTP(rec, httptest.NewRequest("GET", "/v1/ws", nil))
	if rec.Code != 401 {
		t.Fatalf("code = %d", rec.Code)
	}
}
