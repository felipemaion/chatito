package store_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/felipemaion/chatito/server/internal/store"
)

func mkDevice(t *testing.T, s *store.Store, userID, name string) (store.Device, string) {
	t.Helper()
	token := store.NewToken()
	d := store.Device{
		ID: store.NewID("dev_"), UserID: userID, Name: name, Platform: "macos",
		IdentityKey: "hSDwCYkwp1R0i33ctD73Wg2/Og0mOBr066SpjqqbTmo=",
		TokenHash:   store.HashToken(token),
		CreatedAt:   time.Now().UTC().Truncate(time.Second),
	}
	if err := s.CreateDevice(context.Background(), d); err != nil {
		t.Fatalf("create device: %v", err)
	}
	return d, token
}

func TestHashToken(t *testing.T) {
	h := store.HashToken("abc")
	if len(h) != 64 || h != store.HashToken("abc") || h == store.HashToken("abd") {
		t.Fatalf("hash = %q", h)
	}
}

func TestDevices(t *testing.T) {
	s := openTest(t)
	ctx := context.Background()
	u, _ := s.CreateUser(ctx, "Felipe", store.RoleAdmin)
	d, token := mkDevice(t, s, u.ID, "Mac")

	if err := s.CreateDevice(ctx, d); !errors.Is(err, store.ErrConflict) {
		t.Fatalf("dup err = %v", err)
	}
	if err := s.CreateDevice(ctx, store.Device{ID: "dev_x", UserID: "usr_missing", TokenHash: "h", IdentityKey: "k", CreatedAt: time.Now()}); err == nil {
		t.Fatal("expected FK error for missing user")
	}

	got, err := s.GetDeviceByTokenHash(ctx, store.HashToken(token))
	if err != nil || got.ID != d.ID || got.UserID != u.ID || got.FCMToken != nil {
		t.Fatalf("by token = %+v, %v", got, err)
	}
	if _, err := s.GetDeviceByTokenHash(ctx, "nope"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("bad token err = %v", err)
	}
	got, err = s.GetDevice(ctx, d.ID)
	if err != nil || got.Name != "Mac" {
		t.Fatalf("get = %+v, %v", got, err)
	}
	if _, err := s.GetDevice(ctx, "dev_missing"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("get missing err = %v", err)
	}

	fcm := "fcm-token-1"
	if err := s.SetDevicePushToken(ctx, d.ID, &fcm); err != nil {
		t.Fatalf("set push: %v", err)
	}
	got, _ = s.GetDevice(ctx, d.ID)
	if got.FCMToken == nil || *got.FCMToken != fcm {
		t.Fatalf("fcm = %v", got.FCMToken)
	}
	if err := s.SetDevicePushToken(ctx, d.ID, nil); err != nil {
		t.Fatalf("clear push: %v", err)
	}
	got, _ = s.GetDevice(ctx, d.ID)
	if got.FCMToken != nil {
		t.Fatalf("fcm should be nil, got %v", *got.FCMToken)
	}
	if err := s.SetDevicePushToken(ctx, "dev_missing", &fcm); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("set push missing err = %v", err)
	}

	d2, _ := mkDevice(t, s, u.ID, "Phone")
	all, err := s.ListDevices(ctx)
	if err != nil || len(all) != 2 || all[0].ID != d.ID || all[1].ID != d2.ID {
		t.Fatalf("list = %v, %v", all, err)
	}

	if err := s.DeleteDevice(ctx, d2.ID); err != nil {
		t.Fatalf("delete: %v", err)
	}
	if err := s.DeleteDevice(ctx, d2.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("delete twice err = %v", err)
	}
	all, _ = s.ListDevices(ctx)
	if len(all) != 1 {
		t.Fatalf("after delete = %v", all)
	}
}

func TestEnvelopes(t *testing.T) {
	s := openTest(t)
	ctx := context.Background()
	u, _ := s.CreateUser(ctx, "Felipe", store.RoleAdmin)
	a, _ := mkDevice(t, s, u.ID, "A")
	b, _ := mkDevice(t, s, u.ID, "B")
	now := time.Date(2026, 9, 6, 18, 0, 0, 0, time.UTC)

	envs := []store.Envelope{
		{ID: store.NewID("env_"), FromDevice: a.ID, ToDevice: b.ID, Nonce: []byte("n1"), Ciphertext: []byte("c1"), CreatedAt: now},
		{ID: store.NewID("env_"), FromDevice: a.ID, ToDevice: b.ID, Nonce: []byte("n2"), Ciphertext: []byte("c2"), CreatedAt: now.Add(time.Second)},
		{ID: store.NewID("env_"), FromDevice: b.ID, ToDevice: a.ID, Nonce: []byte("n3"), Ciphertext: []byte("c3"), CreatedAt: now},
	}
	if err := s.InsertEnvelopes(ctx, envs); err != nil {
		t.Fatalf("insert: %v", err)
	}
	if err := s.InsertEnvelopes(ctx, nil); err != nil {
		t.Fatalf("insert empty: %v", err)
	}
	// unknown recipient: whole batch rejected
	bad := []store.Envelope{{ID: store.NewID("env_"), FromDevice: a.ID, ToDevice: "dev_missing", Nonce: []byte("n"), Ciphertext: []byte("c"), CreatedAt: now}}
	if err := s.InsertEnvelopes(ctx, bad); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("unknown recipient err = %v", err)
	}

	n, err := s.CountPendingEnvelopes(ctx, b.ID)
	if err != nil || n != 2 {
		t.Fatalf("count = %d, %v", n, err)
	}
	pend, err := s.ListPendingEnvelopes(ctx, b.ID, 10)
	if err != nil || len(pend) != 2 || pend[0].ID != envs[0].ID || pend[1].ID != envs[1].ID {
		t.Fatalf("pending = %+v, %v", pend, err)
	}
	if string(pend[0].Nonce) != "n1" || string(pend[0].Ciphertext) != "c1" || pend[0].FromDevice != a.ID || !pend[0].CreatedAt.Equal(now) {
		t.Fatalf("pending[0] = %+v", pend[0])
	}
	pend, _ = s.ListPendingEnvelopes(ctx, b.ID, 1)
	if len(pend) != 1 {
		t.Fatalf("limit ignored: %d", len(pend))
	}

	// ack only deletes envelopes addressed to the caller; unknown ids ignored
	if err := s.AckEnvelopes(ctx, a.ID, []string{envs[0].ID, "env_nope"}); err != nil {
		t.Fatalf("ack foreign: %v", err)
	}
	if n, _ = s.CountPendingEnvelopes(ctx, b.ID); n != 2 {
		t.Fatalf("foreign ack must not delete: %d", n)
	}
	if err := s.AckEnvelopes(ctx, b.ID, []string{envs[0].ID, "env_nope"}); err != nil {
		t.Fatalf("ack: %v", err)
	}
	if err := s.AckEnvelopes(ctx, b.ID, nil); err != nil {
		t.Fatalf("ack empty: %v", err)
	}
	if n, _ = s.CountPendingEnvelopes(ctx, b.ID); n != 1 {
		t.Fatalf("after ack = %d", n)
	}

	// expiry
	cnt, err := s.ExpireEnvelopes(ctx, now.Add(500*time.Millisecond))
	if err != nil || cnt != 1 { // only n3 (created at now) is older than cutoff; n2 is now+1s
		t.Fatalf("expire = %d, %v", cnt, err)
	}
	if n, _ = s.CountPendingEnvelopes(ctx, a.ID); n != 0 {
		t.Fatalf("a pending after expire = %d", n)
	}

	// deleting a device drops its pending envelopes
	if err := s.DeleteDevice(ctx, b.ID); err != nil {
		t.Fatalf("delete b: %v", err)
	}
	if n, _ = s.CountPendingEnvelopes(ctx, b.ID); n != 0 {
		t.Fatalf("b pending after delete = %d", n)
	}
}
