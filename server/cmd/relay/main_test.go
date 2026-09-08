package main

import (
	"bytes"
	"context"
	"encoding/json"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"

	"github.com/felipemaion/piriquito/server/internal/store"
)

func envOf(m map[string]string) func(string) string {
	return func(k string) string { return m[k] }
}

func TestHealthcheckFlag(t *testing.T) {
	ok := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { _, _ = w.Write([]byte(`{"status":"ok"}`)) }))
	defer ok.Close()
	var out, errb bytes.Buffer
	env := envOf(map[string]string{"RELAY_ADDR": strings.TrimPrefix(ok.URL, "http://")})
	if code := run(context.Background(), []string{"-healthcheck"}, env, &out, &errb, nil); code != 0 {
		t.Fatalf("healthy = %d %s", code, errb.String())
	}
	// port-only address is resolved against 127.0.0.1
	_, port, _ := net.SplitHostPort(strings.TrimPrefix(ok.URL, "http://"))
	if code := run(context.Background(), []string{"-healthcheck"}, envOf(map[string]string{"RELAY_ADDR": ":" + port}), &out, &errb, nil); code != 0 {
		t.Fatalf("healthy via port = %d %s", code, errb.String())
	}
	bad := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(500) }))
	defer bad.Close()
	if code := run(context.Background(), []string{"-healthcheck"}, envOf(map[string]string{"RELAY_ADDR": strings.TrimPrefix(bad.URL, "http://")}), &out, &errb, nil); code != 1 {
		t.Fatalf("unhealthy = %d", code)
	}
	closed := httptest.NewServer(http.NotFoundHandler())
	addr := strings.TrimPrefix(closed.URL, "http://")
	closed.Close()
	if code := run(context.Background(), []string{"-healthcheck"}, envOf(map[string]string{"RELAY_ADDR": addr}), &out, &errb, nil); code != 1 {
		t.Fatalf("closed = %d", code)
	}
}

var codeRe = regexp.MustCompile(`[0-9A-Z]{4}-[0-9A-Z]{4}`)

func TestAdminBootstrapAndInvite(t *testing.T) {
	dir := t.TempDir()
	env := envOf(map[string]string{"RELAY_DATA_DIR": dir})
	var out, errb bytes.Buffer

	if code := run(context.Background(), []string{"admin", "bootstrap"}, env, &out, &errb, nil); code != 2 {
		t.Fatalf("bootstrap without name = %d %s", code, errb.String())
	}
	out.Reset()
	if code := run(context.Background(), []string{"admin", "bootstrap", "--name", "Felipe"}, env, &out, &errb, nil); code != 0 {
		t.Fatalf("bootstrap = %d %s", code, errb.String())
	}
	if !codeRe.MatchString(out.String()) || !strings.Contains(out.String(), "Felipe") {
		t.Fatalf("bootstrap output = %q", out.String())
	}
	st, err := store.Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	u, err := st.GetUserByName(context.Background(), "Felipe")
	if err != nil || u.Role != store.RoleAdmin {
		t.Fatalf("admin user = %+v %v", u, err)
	}
	inv, err := st.RedeemInvite(context.Background(), codeRe.FindString(out.String()), time.Now())
	if err != nil || inv.UserID != u.ID {
		t.Fatalf("invite = %+v %v", inv, err)
	}
	_ = st.Close()

	// second bootstrap refused
	errb.Reset()
	if code := run(context.Background(), []string{"admin", "bootstrap", "--name", "Outro"}, env, &out, &errb, nil); code != 1 || !strings.Contains(errb.String(), "already") {
		t.Fatalf("second bootstrap = %d %s", code, errb.String())
	}

	// invite for a new member and for an existing user
	out.Reset()
	if code := run(context.Background(), []string{"admin", "invite", "--user", "Mãe"}, env, &out, &errb, nil); code != 0 {
		t.Fatalf("invite = %d %s", code, errb.String())
	}
	if !codeRe.MatchString(out.String()) {
		t.Fatalf("invite output = %q", out.String())
	}
	st, _ = store.Open(dir)
	if u, err := st.GetUserByName(context.Background(), "Mãe"); err != nil || u.Role != store.RoleMember {
		t.Fatalf("member = %+v %v", u, err)
	}
	_ = st.Close()
	out.Reset()
	if code := run(context.Background(), []string{"admin", "invite", "--user", "Felipe"}, env, &out, &errb, nil); code != 0 || !codeRe.MatchString(out.String()) {
		t.Fatalf("invite existing = %d %q", code, out.String())
	}
	if code := run(context.Background(), []string{"admin", "invite"}, env, &out, &errb, nil); code != 2 {
		t.Fatalf("invite without user = %d", code)
	}
	if code := run(context.Background(), []string{"admin", "nope"}, env, &out, &errb, nil); code != 2 {
		t.Fatalf("unknown admin cmd = %d", code)
	}
	if code := run(context.Background(), []string{"nope"}, env, &out, &errb, nil); code != 2 {
		t.Fatalf("unknown cmd = %d", code)
	}
	if code := run(context.Background(), []string{"-bogus"}, env, &out, &errb, nil); code != 2 {
		t.Fatalf("bad flag = %d", code)
	}
}

func TestAdminFailsOnBadDataDir(t *testing.T) {
	f := filepath.Join(t.TempDir(), "file")
	_ = os.WriteFile(f, []byte("x"), 0o600)
	var out, errb bytes.Buffer
	if code := run(context.Background(), []string{"admin", "invite", "--user", "X"}, envOf(map[string]string{"RELAY_DATA_DIR": f}), &out, &errb, nil); code != 1 {
		t.Fatalf("code = %d", code)
	}
}

func TestServeEndToEndAndGracefulShutdown(t *testing.T) {
	dir := t.TempDir()
	env := envOf(map[string]string{"RELAY_DATA_DIR": dir, "RELAY_ADDR": "127.0.0.1:0"})
	var out, errb bytes.Buffer
	if code := run(context.Background(), []string{"admin", "bootstrap", "--name", "Felipe"}, env, &out, &errb, nil); code != 0 {
		t.Fatalf("bootstrap = %d %s", code, errb.String())
	}
	invite := codeRe.FindString(out.String())

	ctx, cancel := context.WithCancel(context.Background())
	ready := make(chan string, 1)
	done := make(chan int, 1)
	var logs bytes.Buffer
	go func() { done <- run(ctx, nil, env, &logs, &errb, ready) }()
	var addr string
	select {
	case addr = <-ready:
	case <-time.After(10 * time.Second):
		t.Fatal("server did not start")
	}
	base := "http://" + addr

	res, err := http.Get(base + "/healthz")
	if err != nil || res.StatusCode != 200 {
		t.Fatalf("healthz: %v %v", err, res)
	}
	_ = res.Body.Close()

	body, _ := json.Marshal(map[string]string{"invite_code": invite, "device_name": "Mac", "platform": "macos", "identity_key": "hSDwCYkwp1R0i33ctD73Wg2/Og0mOBr066SpjqqbTmo="})
	res, err = http.Post(base+"/v1/devices", "application/json", bytes.NewReader(body))
	if err != nil || res.StatusCode != 201 {
		t.Fatalf("register: %v %v", err, res)
	}
	var reg struct {
		Token string `json:"token"`
	}
	_ = json.NewDecoder(res.Body).Decode(&reg)
	_ = res.Body.Close()
	req, _ := http.NewRequest("GET", base+"/v1/directory", nil)
	req.Header.Set("Authorization", "Bearer "+reg.Token)
	res, err = http.DefaultClient.Do(req)
	if err != nil || res.StatusCode != 200 {
		t.Fatalf("directory: %v %v", err, res)
	}
	_ = res.Body.Close()

	// the -healthcheck flag works against the live server
	if code := run(context.Background(), []string{"-healthcheck"}, envOf(map[string]string{"RELAY_ADDR": addr}), &out, &errb, nil); code != 0 {
		t.Fatalf("live healthcheck = %d", code)
	}

	cancel()
	select {
	case code := <-done:
		if code != 0 {
			t.Fatalf("serve exit = %d %s", code, errb.String())
		}
	case <-time.After(15 * time.Second):
		t.Fatal("server did not stop")
	}
	// logs are JSON lines
	first, _, _ := strings.Cut(logs.String(), "\n")
	var line map[string]any
	if err := json.Unmarshal([]byte(first), &line); err != nil || line["msg"] == nil {
		t.Fatalf("first log line not JSON: %q", first)
	}
}

func TestServeFailures(t *testing.T) {
	var out, errb bytes.Buffer
	f := filepath.Join(t.TempDir(), "file")
	_ = os.WriteFile(f, []byte("x"), 0o600)
	if code := run(context.Background(), nil, envOf(map[string]string{"RELAY_DATA_DIR": f}), &out, &errb, nil); code != 1 {
		t.Fatalf("bad data dir = %d", code)
	}
	if code := run(context.Background(), nil, envOf(map[string]string{"RELAY_DATA_DIR": t.TempDir(), "FCM_SERVICE_ACCOUNT_B64": "!!!"}), &out, &errb, nil); code != 1 {
		t.Fatalf("bad fcm env = %d", code)
	}
	// address already in use
	l, _ := net.Listen("tcp", "127.0.0.1:0")
	defer func() { _ = l.Close() }()
	if code := run(context.Background(), nil, envOf(map[string]string{"RELAY_DATA_DIR": t.TempDir(), "RELAY_ADDR": l.Addr().String()}), &out, &errb, nil); code != 1 {
		t.Fatalf("addr in use = %d", code)
	}
}
