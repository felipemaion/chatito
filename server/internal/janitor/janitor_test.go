package janitor_test

import (
	"bytes"
	"context"
	"errors"
	"log/slog"
	"testing"
	"time"

	"github.com/felipemaion/piriquito/server/internal/janitor"
	"github.com/felipemaion/piriquito/server/internal/store"
)

func seed(t *testing.T, st *store.Store, now time.Time) (oldEnv, freshEnv, oldBlob, deliveredBlob, freshBlob, oldInvite string) {
	t.Helper()
	ctx := context.Background()
	u, _ := st.CreateUser(ctx, "Felipe", store.RoleAdmin)
	mk := func(name string) store.Device {
		d := store.Device{ID: store.NewID("dev_"), UserID: u.ID, Name: name, Platform: "macos", IdentityKey: "k", TokenHash: store.HashToken(name), CreatedAt: now}
		if err := st.CreateDevice(ctx, d); err != nil {
			t.Fatal(err)
		}
		return d
	}
	a, b := mk("a"), mk("b")
	envs := []store.Envelope{
		{ID: store.NewID("env_"), FromDevice: a.ID, ToDevice: b.ID, Nonce: []byte("n"), Ciphertext: []byte("c"), CreatedAt: now.Add(-31 * 24 * time.Hour)},
		{ID: store.NewID("env_"), FromDevice: a.ID, ToDevice: b.ID, Nonce: []byte("n"), Ciphertext: []byte("c"), CreatedAt: now.Add(-29 * 24 * time.Hour)},
	}
	if err := st.InsertEnvelopes(ctx, envs); err != nil {
		t.Fatal(err)
	}
	blob := func(expires time.Time, complete bool) string {
		bl := store.Blob{ID: store.NewID("blob_"), OwnerDevice: a.ID, Size: 1, ChunkSize: 1, CreatedAt: now, ExpiresAt: expires}
		if err := st.CreateBlob(ctx, bl, []string{b.ID}); err != nil {
			t.Fatal(err)
		}
		if complete {
			if _, err := st.WriteChunk(ctx, bl.ID, 0, bytes.NewReader([]byte("x"))); err != nil {
				t.Fatal(err)
			}
			if err := st.CompleteBlob(ctx, bl.ID); err != nil {
				t.Fatal(err)
			}
		}
		return bl.ID
	}
	oldBlob = blob(now.Add(-time.Hour), false)
	deliveredBlob = blob(now.Add(24*time.Hour), true)
	if _, err := st.MarkBlobDelivered(ctx, deliveredBlob, b.ID); err != nil {
		t.Fatal(err)
	}
	freshBlob = blob(now.Add(24*time.Hour), true)
	inv, _ := st.CreateInvite(ctx, u.ID, now.Add(-time.Minute))
	_, _ = st.CreateInvite(ctx, u.ID, now.Add(time.Hour))
	return envs[0].ID, envs[1].ID, oldBlob, deliveredBlob, freshBlob, inv.Code
}

func TestRunOnce(t *testing.T) {
	st, err := store.Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = st.Close() }()
	now := time.Date(2026, 9, 6, 18, 0, 0, 0, time.UTC)
	_, freshEnv, oldBlob, deliveredBlob, freshBlob, oldInvite := seed(t, st, now)

	j := janitor.New(st, janitor.Options{Now: func() time.Time { return now }, Logger: slog.New(slog.DiscardHandler)})
	stats, err := j.RunOnce(context.Background())
	if err != nil {
		t.Fatalf("run: %v", err)
	}
	if stats.Envelopes != 1 || stats.Blobs != 2 || stats.Invites != 1 {
		t.Fatalf("stats = %+v", stats)
	}
	ctx := context.Background()
	if _, err := st.GetBlob(ctx, oldBlob); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("old blob should be gone: %v", err)
	}
	if _, err := st.GetBlob(ctx, deliveredBlob); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("delivered blob should be gone: %v", err)
	}
	if _, err := st.GetBlob(ctx, freshBlob); err != nil {
		t.Fatalf("fresh blob should stay: %v", err)
	}
	if _, err := st.RedeemInvite(ctx, oldInvite, now.Add(-time.Hour)); !errors.Is(err, store.ErrInvalidInvite) {
		t.Fatalf("old invite should be gone: %v", err)
	}
	envs, _ := st.ListPendingEnvelopes(ctx, deviceOf(t, st), 10)
	if len(envs) != 1 || envs[0].ID != freshEnv {
		t.Fatalf("envelopes after run = %+v", envs)
	}
	// second run is a no-op
	stats, _ = j.RunOnce(ctx)
	if stats.Envelopes+int64(stats.Blobs)+stats.Invites != 0 {
		t.Fatalf("second run stats = %+v", stats)
	}
}

func deviceOf(t *testing.T, st *store.Store) string {
	t.Helper()
	devs, err := st.ListDevices(context.Background())
	if err != nil || len(devs) != 2 {
		t.Fatalf("devices = %v %v", devs, err)
	}
	return devs[1].ID
}

func TestRunLoopsUntilCancelled(t *testing.T) {
	st, err := store.Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = st.Close() }()
	now := time.Date(2026, 9, 6, 18, 0, 0, 0, time.UTC)
	seed(t, st, now)
	j := janitor.New(st, janitor.Options{Interval: 5 * time.Millisecond, Now: func() time.Time { return now }, Logger: slog.New(slog.DiscardHandler)})
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { j.Run(ctx); close(done) }()
	deadline := time.Now().Add(2 * time.Second)
	for j.Runs() < 3 && time.Now().Before(deadline) {
		time.Sleep(5 * time.Millisecond)
	}
	cancel()
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		t.Fatal("Run did not return after cancel")
	}
	if j.Runs() < 3 {
		t.Fatalf("runs = %d", j.Runs())
	}
}

func TestRunOnceReportsStoreErrors(t *testing.T) {
	st, err := store.Open(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	_ = st.Close()
	j := janitor.New(st, janitor.Options{Logger: slog.New(slog.DiscardHandler)})
	if _, err := j.RunOnce(context.Background()); err == nil {
		t.Fatal("expected error from closed store")
	}
	// Run keeps looping despite errors and exits on cancel.
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Millisecond)
	defer cancel()
	j2 := janitor.New(st, janitor.Options{Interval: 5 * time.Millisecond, Logger: slog.New(slog.DiscardHandler)})
	j2.Run(ctx)
	if j2.Runs() < 2 {
		t.Fatalf("runs = %d", j2.Runs())
	}
}
