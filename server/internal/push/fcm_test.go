package push_test

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/felipemaion/chatito/server/internal/api"
	"github.com/felipemaion/chatito/server/internal/push"
)

func serviceAccountJSON(t *testing.T, tokenURL string) []byte {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	pemKey := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(key)})
	sa := map[string]string{
		"type": "service_account", "project_id": "chatito-test", "private_key_id": "k1",
		"private_key": string(pemKey), "client_email": "relay@chatito-test.iam.gserviceaccount.com",
		"token_uri": tokenURL,
	}
	b, _ := json.Marshal(sa)
	return b
}

type fakeGoogle struct {
	srv       *httptest.Server
	tokens    atomic.Int32
	sends     atomic.Int32
	lastBody  atomic.Value
	sendCode  atomic.Int32
	sendReply atomic.Value
}

func newFakeGoogle(t *testing.T) *fakeGoogle {
	t.Helper()
	g := &fakeGoogle{}
	g.sendCode.Store(200)
	g.sendReply.Store(`{"name":"projects/chatito-test/messages/1"}`)
	mux := http.NewServeMux()
	mux.HandleFunc("POST /token", func(w http.ResponseWriter, r *http.Request) {
		g.tokens.Add(1)
		_ = r.ParseForm()
		if r.Form.Get("grant_type") != "urn:ietf:params:oauth:grant-type:jwt-bearer" || r.Form.Get("assertion") == "" {
			http.Error(w, "bad grant", http.StatusBadRequest)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"access_token":"at-123","token_type":"Bearer","expires_in":3600}`))
	})
	mux.HandleFunc("POST /v1/projects/chatito-test/messages:send", func(w http.ResponseWriter, r *http.Request) {
		g.sends.Add(1)
		if r.Header.Get("Authorization") != "Bearer at-123" {
			http.Error(w, "no auth", http.StatusUnauthorized)
			return
		}
		b, _ := io.ReadAll(r.Body)
		g.lastBody.Store(string(b))
		w.WriteHeader(int(g.sendCode.Load()))
		_, _ = w.Write([]byte(g.sendReply.Load().(string)))
	})
	g.srv = httptest.NewServer(mux)
	t.Cleanup(g.srv.Close)
	return g
}

func newFCM(t *testing.T, g *fakeGoogle) *push.FCM {
	t.Helper()
	sa := serviceAccountJSON(t, g.srv.URL+"/token")
	f, err := push.NewFCM(context.Background(), sa, push.Options{Endpoint: g.srv.URL, Logger: slog.New(slog.DiscardHandler)})
	if err != nil {
		t.Fatalf("NewFCM: %v", err)
	}
	return f
}

func TestWakeSendsDataOnlyHighPriority(t *testing.T) {
	g := newFakeGoogle(t)
	f := newFCM(t, g)
	if err := f.Wake(context.Background(), "device-token-1"); err != nil {
		t.Fatalf("wake: %v", err)
	}
	if err := f.Wake(context.Background(), "device-token-2"); err != nil {
		t.Fatalf("wake 2: %v", err)
	}
	if g.sends.Load() != 2 || g.tokens.Load() != 1 {
		t.Fatalf("sends=%d tokens=%d (token must be cached)", g.sends.Load(), g.tokens.Load())
	}
	var body struct {
		Message struct {
			Token        string            `json:"token"`
			Data         map[string]string `json:"data"`
			Notification any               `json:"notification"`
			Android      struct {
				Priority string `json:"priority"`
			} `json:"android"`
		} `json:"message"`
	}
	raw := g.lastBody.Load().(string)
	if err := json.Unmarshal([]byte(raw), &body); err != nil {
		t.Fatal(err)
	}
	if body.Message.Token != "device-token-2" || body.Message.Data["type"] != "wake" || len(body.Message.Data) != 1 ||
		body.Message.Notification != nil || body.Message.Android.Priority != "high" {
		t.Fatalf("body = %s", raw)
	}
	if strings.Contains(raw, "notification") {
		t.Fatalf("must be data-only: %s", raw)
	}
}

func TestWakeErrors(t *testing.T) {
	g := newFakeGoogle(t)
	f := newFCM(t, g)
	g.sendCode.Store(404)
	g.sendReply.Store(`{"error":{"status":"NOT_FOUND","details":[{"errorCode":"UNREGISTERED"}]}}`)
	err := f.Wake(context.Background(), "gone")
	if !errors.Is(err, api.ErrPushUnregistered) {
		t.Fatalf("unregistered err = %v", err)
	}
	g.sendCode.Store(500)
	g.sendReply.Store(`boom`)
	if err := f.Wake(context.Background(), "x"); err == nil || errors.Is(err, api.ErrPushUnregistered) {
		t.Fatalf("500 err = %v", err)
	}
	if err := f.Wake(context.Background(), ""); err == nil {
		t.Fatal("empty token should fail")
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if err := f.Wake(ctx, "x"); err == nil {
		t.Fatal("cancelled ctx should fail")
	}
}

func TestNewFCMValidation(t *testing.T) {
	if _, err := push.NewFCM(context.Background(), []byte("{"), push.Options{}); err == nil {
		t.Fatal("bad json should fail")
	}
	if _, err := push.NewFCM(context.Background(), []byte(`{"type":"service_account","client_email":"a","private_key":"x"}`), push.Options{}); err == nil {
		t.Fatal("missing project_id should fail")
	}
	if _, err := push.NewFCM(context.Background(), []byte(`{"type":"service_account","project_id":"p","client_email":"a","private_key":"not-pem"}`), push.Options{}); err == nil {
		t.Fatal("bad key should fail")
	}
}

func TestFromEnv(t *testing.T) {
	p, err := push.FromEnv(context.Background(), "", push.Options{})
	if err != nil || p != nil {
		t.Fatalf("empty env: p=%v err=%v", p, err)
	}
	if _, err := push.FromEnv(context.Background(), "!!!notbase64", push.Options{}); err == nil {
		t.Fatal("bad base64 should fail")
	}
	g := newFakeGoogle(t)
	enc := base64.StdEncoding.EncodeToString(serviceAccountJSON(t, g.srv.URL+"/token"))
	p, err = push.FromEnv(context.Background(), enc, push.Options{Endpoint: g.srv.URL, Logger: slog.New(slog.DiscardHandler)})
	if err != nil || p == nil {
		t.Fatalf("valid env: p=%v err=%v", p, err)
	}
	if err := p.Wake(context.Background(), "tok"); err != nil {
		t.Fatalf("wake: %v", err)
	}
	// ProjectID is exposed for logging.
	if f, ok := p.(*push.FCM); !ok || f.ProjectID() != "chatito-test" {
		t.Fatalf("project = %v", p)
	}
}
