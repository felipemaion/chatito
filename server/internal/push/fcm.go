// Package push wakes Android devices through FCM HTTP v1 with data-only
// messages. It never carries message content.
package push

import (
	"bytes"
	"context"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"

	"github.com/felipemaion/piriquito/server/internal/api"
)

const (
	defaultEndpoint = "https://fcm.googleapis.com"
	fcmScope        = "https://www.googleapis.com/auth/firebase.messaging"
	requestTimeout  = 10 * time.Second
)

// Options tunes the FCM client (mainly for tests).
type Options struct {
	Endpoint string       // default https://fcm.googleapis.com
	Logger   *slog.Logger // optional
}

// FCM is an api.Pusher backed by Firebase Cloud Messaging HTTP v1.
type FCM struct {
	projectID string
	client    *http.Client
	endpoint  string
	log       *slog.Logger
}

// NewFCM builds a pusher from a service-account JSON document.
func NewFCM(ctx context.Context, serviceAccount []byte, opts Options) (*FCM, error) {
	var meta struct {
		ProjectID string `json:"project_id"`
	}
	if err := json.Unmarshal(serviceAccount, &meta); err != nil {
		return nil, fmt.Errorf("push: parse service account: %w", err)
	}
	if meta.ProjectID == "" {
		return nil, errors.New("push: service account has no project_id")
	}
	cfg, err := google.JWTConfigFromJSON(serviceAccount, fcmScope)
	if err != nil {
		return nil, fmt.Errorf("push: service account credentials: %w", err)
	}
	if err := checkPrivateKey(cfg.PrivateKey); err != nil {
		return nil, err
	}
	f := &FCM{projectID: meta.ProjectID, endpoint: strings.TrimRight(opts.Endpoint, "/"), log: opts.Logger}
	if f.endpoint == "" {
		f.endpoint = defaultEndpoint
	}
	if f.log == nil {
		f.log = slog.Default()
	}
	base := &http.Client{Timeout: requestTimeout}
	f.client = oauth2.NewClient(context.WithValue(ctx, oauth2.HTTPClient, base), cfg.TokenSource(ctx))
	f.client.Timeout = requestTimeout
	return f, nil
}

// FromEnv builds a pusher from the base64 service account in the env var
// value. An empty value disables push and returns (nil, nil).
func FromEnv(ctx context.Context, b64 string, opts Options) (api.Pusher, error) {
	if strings.TrimSpace(b64) == "" {
		return nil, nil //nolint:nilnil // nil pusher means "push disabled" by design
	}
	raw, err := base64.StdEncoding.DecodeString(strings.TrimSpace(b64))
	if err != nil {
		return nil, fmt.Errorf("push: FCM_SERVICE_ACCOUNT_B64 is not base64: %w", err)
	}
	return NewFCM(ctx, raw, opts)
}

// checkPrivateKey fails fast on an unusable service-account key instead of
// discovering it on the first push.
func checkPrivateKey(pemKey []byte) error {
	block, _ := pem.Decode(pemKey)
	if block == nil {
		return errors.New("push: service account private_key is not PEM")
	}
	if _, err := x509.ParsePKCS8PrivateKey(block.Bytes); err == nil {
		return nil
	}
	if _, err := x509.ParsePKCS1PrivateKey(block.Bytes); err != nil {
		return fmt.Errorf("push: service account private_key: %w", err)
	}
	return nil
}

// ProjectID returns the Firebase project this client sends through.
func (f *FCM) ProjectID() string { return f.projectID }

type sendRequest struct {
	Message struct {
		Token   string            `json:"token"`
		Data    map[string]string `json:"data"`
		Android struct {
			Priority string `json:"priority"`
		} `json:"android"`
	} `json:"message"`
}

// Wake sends {"type":"wake"} as a high-priority data-only message.
func (f *FCM) Wake(ctx context.Context, token string) error {
	if token == "" {
		return errors.New("push: empty fcm token")
	}
	var req sendRequest
	req.Message.Token = token
	req.Message.Data = map[string]string{"type": "wake"}
	req.Message.Android.Priority = "high"
	body, _ := json.Marshal(req)
	url := f.endpoint + "/v1/projects/" + f.projectID + "/messages:send"
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("push: build request: %w", err)
	}
	httpReq.Header.Set("Content-Type", "application/json")
	res, err := f.client.Do(httpReq)
	if err != nil {
		return fmt.Errorf("push: send: %w", err)
	}
	defer func() { _ = res.Body.Close() }()
	if res.StatusCode >= 200 && res.StatusCode < 300 {
		return nil
	}
	reply, _ := io.ReadAll(io.LimitReader(res.Body, 4096))
	if res.StatusCode == http.StatusNotFound || bytes.Contains(reply, []byte("UNREGISTERED")) {
		return fmt.Errorf("push: token no longer registered: %w", api.ErrPushUnregistered)
	}
	return fmt.Errorf("push: fcm status %d: %s", res.StatusCode, strings.TrimSpace(string(reply)))
}
