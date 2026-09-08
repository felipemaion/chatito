package api_test

import (
	"encoding/base64"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/felipemaion/piriquito/server/internal/api"
)

const fixturesDir = "../../../docs/protocol/fixtures"

func fixture(t *testing.T, name string) []byte {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(fixturesDir, name))
	if err != nil {
		t.Fatalf("read fixture %s: %v", name, err)
	}
	return b
}

// roundTrip decodes raw into v, re-encodes it and asserts semantic equality.
func roundTrip(t *testing.T, raw []byte, v any) {
	t.Helper()
	if err := json.Unmarshal(raw, v); err != nil {
		t.Fatalf("decode into %T: %v", v, err)
	}
	out, err := json.Marshal(v)
	if err != nil {
		t.Fatalf("encode %T: %v", v, err)
	}
	var want, got any
	_ = json.Unmarshal(raw, &want)
	_ = json.Unmarshal(out, &got)
	if !reflect.DeepEqual(want, got) {
		t.Fatalf("round trip mismatch for %T:\n want %s\n got  %s", v, raw, out)
	}
}

func TestContractFixtures(t *testing.T) {
	tests := []struct {
		file string
		v    any
	}{
		{"error.json", &api.ErrorResponse{}},
		{"register_request.json", &api.RegisterRequest{}},
		{"register_response.json", &api.RegisterResponse{}},
		{"directory.json", &api.DirectoryResponse{}},
		{"envelopes_post_request.json", &api.EnvelopesPostRequest{}},
		{"envelopes_post_response.json", &api.EnvelopesPostResponse{}},
	}
	for _, tc := range tests {
		t.Run(tc.file, func(t *testing.T) { roundTrip(t, fixture(t, tc.file), tc.v) })
	}
}

func TestContractWSFrames(t *testing.T) {
	var frames map[string]json.RawMessage
	if err := json.Unmarshal(fixture(t, "ws_frames.json"), &frames); err != nil {
		t.Fatal(err)
	}
	roundTrip(t, frames["envelope"], &api.EnvelopeFrame{})
	roundTrip(t, frames["error"], &api.ErrorFrame{})
	roundTrip(t, frames["hello"], &api.HelloFrame{})
	roundTrip(t, frames["ack"], &api.AckFrame{})
	var ping api.Frame
	roundTrip(t, frames["ping"], &ping)
	if ping.Type != "ping" {
		t.Fatalf("ping type = %q", ping.Type)
	}

	var env api.EnvelopeFrame
	_ = json.Unmarshal(frames["envelope"], &env)
	if env.Type != "envelope" || env.Envelope.ID != "env_ZW52ZWxvcGUwMDAwMDAwMDAx" || env.Envelope.CreatedAt != "2026-09-06T18:10:00Z" {
		t.Fatalf("envelope frame = %+v", env)
	}
}

// The relay never decrypts, but the vector must at least be well-formed.
func TestCryptoBoxVectorShape(t *testing.T) {
	var v struct {
		Ciphertext   string `json:"ciphertext"`
		Nonce        string `json:"nonce"`
		PlaintextUTF string `json:"plaintext_utf8"`
		RecipientPK  string `json:"recipient_pk"`
		SenderPK     string `json:"sender_pk"`
		SafetyNumber string `json:"safety_number"`
	}
	if err := json.Unmarshal(fixture(t, "crypto_box_vector.json"), &v); err != nil {
		t.Fatal(err)
	}
	nonce, err := base64.StdEncoding.DecodeString(v.Nonce)
	if err != nil || len(nonce) != 24 {
		t.Fatalf("nonce: len=%d err=%v", len(nonce), err)
	}
	ct, err := base64.StdEncoding.DecodeString(v.Ciphertext)
	if err != nil || len(ct) != len(v.PlaintextUTF)+16 {
		t.Fatalf("ciphertext: len=%d want %d err=%v", len(ct), len(v.PlaintextUTF)+16, err)
	}
	for _, pk := range []string{v.RecipientPK, v.SenderPK} {
		if b, err := base64.StdEncoding.DecodeString(pk); err != nil || len(b) != 32 {
			t.Fatalf("pk %q: len=%d err=%v", pk, len(b), err)
		}
	}
	if len(v.SafetyNumber) != 60 {
		t.Fatalf("safety number len = %d", len(v.SafetyNumber))
	}
	// Same validators the handlers use.
	if err := api.ValidateNonce(v.Nonce); err != nil {
		t.Fatalf("ValidateNonce: %v", err)
	}
	if err := api.ValidateIdentityKey(v.SenderPK); err != nil {
		t.Fatalf("ValidateIdentityKey: %v", err)
	}
}
