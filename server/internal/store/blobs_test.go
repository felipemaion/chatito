package store_test

import (
	"bytes"
	"context"
	"errors"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/felipemaion/chatito/server/internal/store"
)

// TestWriteChunkConcurrentSameIndexIsSafe guards against a fixed tmp file
// name in WriteChunk: concurrent uploads of the same chunk must never
// corrupt each other, only race on which write wins.
func TestWriteChunkConcurrentSameIndexIsSafe(t *testing.T) {
	s := openTest(t)
	ctx := context.Background()
	u, _ := s.CreateUser(ctx, "Felipe", store.RoleAdmin)
	owner, _ := mkDevice(t, s, u.ID, "Mac")
	r1, _ := mkDevice(t, s, u.ID, "Phone")
	b := store.Blob{ID: store.NewID("blob_"), OwnerDevice: owner.ID, Size: 4, ChunkSize: 4,
		CreatedAt: time.Now(), ExpiresAt: time.Now().Add(time.Hour)}
	if err := s.CreateBlob(ctx, b, []string{r1.ID}); err != nil {
		t.Fatal(err)
	}
	var wg sync.WaitGroup
	errs := make(chan error, 20)
	for range 20 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if _, err := s.WriteChunk(ctx, b.ID, 0, bytes.NewReader([]byte("abcd"))); err != nil {
				errs <- err
			}
		}()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Fatalf("concurrent write chunk: %v", err)
	}
	if err := s.CompleteBlob(ctx, b.ID); err != nil {
		t.Fatalf("complete: %v", err)
	}
	data, err := os.ReadFile(s.BlobPath(b.ID))
	if err != nil || string(data) != "abcd" {
		t.Fatalf("data = %q, %v", data, err)
	}
}

// TestCompleteBlobConcurrentIsSafe guards against a fixed tmp file name in
// assemble: concurrent (idempotent) completions must never corrupt the
// assembled file.
func TestCompleteBlobConcurrentIsSafe(t *testing.T) {
	s := openTest(t)
	ctx := context.Background()
	u, _ := s.CreateUser(ctx, "Felipe", store.RoleAdmin)
	owner, _ := mkDevice(t, s, u.ID, "Mac")
	r1, _ := mkDevice(t, s, u.ID, "Phone")
	b := store.Blob{ID: store.NewID("blob_"), OwnerDevice: owner.ID, Size: 4, ChunkSize: 4,
		CreatedAt: time.Now(), ExpiresAt: time.Now().Add(time.Hour)}
	if err := s.CreateBlob(ctx, b, []string{r1.ID}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.WriteChunk(ctx, b.ID, 0, bytes.NewReader([]byte("abcd"))); err != nil {
		t.Fatal(err)
	}
	var wg sync.WaitGroup
	errs := make(chan error, 10)
	for range 10 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if err := s.CompleteBlob(ctx, b.ID); err != nil {
				errs <- err
			}
		}()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Fatalf("concurrent complete: %v", err)
	}
	data, err := os.ReadFile(s.BlobPath(b.ID))
	if err != nil || string(data) != "abcd" {
		t.Fatalf("data = %q, %v", data, err)
	}
}

func TestBlobLifecycle(t *testing.T) {
	s := openTest(t)
	ctx := context.Background()
	u, _ := s.CreateUser(ctx, "Felipe", store.RoleAdmin)
	owner, _ := mkDevice(t, s, u.ID, "Mac")
	r1, _ := mkDevice(t, s, u.ID, "Phone")
	r2, _ := mkDevice(t, s, u.ID, "Win")
	now := time.Date(2026, 9, 6, 18, 0, 0, 0, time.UTC)

	b := store.Blob{ID: store.NewID("blob_"), OwnerDevice: owner.ID, Size: 10, ChunkSize: 4, CreatedAt: now, ExpiresAt: now.Add(30 * 24 * time.Hour)}
	if err := s.CreateBlob(ctx, b, []string{r1.ID, r2.ID}); err != nil {
		t.Fatalf("create: %v", err)
	}
	if err := s.CreateBlob(ctx, b, []string{r1.ID}); !errors.Is(err, store.ErrConflict) {
		t.Fatalf("dup err = %v", err)
	}
	if err := s.CreateBlob(ctx, store.Blob{ID: store.NewID("blob_"), OwnerDevice: owner.ID, Size: 1, ChunkSize: 1, CreatedAt: now, ExpiresAt: now}, nil); !errors.Is(err, store.ErrValidation) {
		t.Fatalf("no recipients err = %v", err)
	}
	if b.ChunkCount() != 3 {
		t.Fatalf("chunk count = %d", b.ChunkCount())
	}

	got, err := s.GetBlob(ctx, b.ID)
	if err != nil || got.ID != b.ID || got.Size != 10 || got.ChunkSize != 4 || got.Complete || !got.ExpiresAt.Equal(b.ExpiresAt) {
		t.Fatalf("get = %+v, %v", got, err)
	}
	if _, err := s.GetBlob(ctx, "blob_missing"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("missing err = %v", err)
	}
	recs, err := s.BlobRecipients(ctx, b.ID)
	if err != nil || len(recs) != 2 || recs[0].DeviceID != r1.ID || recs[0].Delivered || recs[1].DeviceID != r2.ID {
		t.Fatalf("recipients = %+v, %v", recs, err)
	}

	// complete before any chunk
	if err := s.CompleteBlob(ctx, b.ID); !errors.Is(err, store.ErrIncomplete) {
		t.Fatalf("early complete err = %v", err)
	}

	// chunk range / size validation
	if _, err := s.WriteChunk(ctx, b.ID, 3, bytes.NewReader([]byte("xx"))); !errors.Is(err, store.ErrChunkOutOfRange) {
		t.Fatalf("out of range err = %v", err)
	}
	if _, err := s.WriteChunk(ctx, b.ID, -1, bytes.NewReader([]byte("xx"))); !errors.Is(err, store.ErrChunkOutOfRange) {
		t.Fatalf("negative err = %v", err)
	}
	if _, err := s.WriteChunk(ctx, "blob_missing", 0, bytes.NewReader([]byte("xx"))); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("missing blob err = %v", err)
	}
	if _, err := s.WriteChunk(ctx, b.ID, 0, bytes.NewReader([]byte("abc"))); !errors.Is(err, store.ErrValidation) {
		t.Fatalf("short chunk err = %v", err)
	}
	if _, err := s.WriteChunk(ctx, b.ID, 2, bytes.NewReader([]byte("abc"))); !errors.Is(err, store.ErrValidation) {
		t.Fatalf("long last chunk err = %v", err)
	}

	// happy path, out of order, with re-PUT overwrite
	for _, c := range []struct {
		n    int
		data string
	}{{2, "zz"}, {0, "XXXX"}, {1, "efgh"}, {0, "abcd"}} {
		n, err := s.WriteChunk(ctx, b.ID, c.n, bytes.NewReader([]byte(c.data)))
		if err != nil || n != int64(len(c.data)) {
			t.Fatalf("write chunk %d: n=%d err=%v", c.n, n, err)
		}
	}
	// last chunk wrong then fixed
	if _, err := s.WriteChunk(ctx, b.ID, 2, bytes.NewReader([]byte("ij"))); err != nil {
		t.Fatalf("rewrite last: %v", err)
	}
	if err := s.CompleteBlob(ctx, b.ID); err != nil {
		t.Fatalf("complete: %v", err)
	}
	if err := s.CompleteBlob(ctx, b.ID); err != nil {
		t.Fatalf("complete idempotent: %v", err)
	}
	if err := s.CompleteBlob(ctx, "blob_missing"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("complete missing err = %v", err)
	}
	got, _ = s.GetBlob(ctx, b.ID)
	if !got.Complete {
		t.Fatal("blob should be complete")
	}
	data, err := os.ReadFile(s.BlobPath(b.ID))
	if err != nil || string(data) != "abcdefghij" {
		t.Fatalf("assembled = %q, %v", data, err)
	}
	if parts, _ := filepath.Glob(filepath.Join(s.BlobDir(), b.ID+".*")); len(parts) != 0 {
		t.Fatalf("chunk parts left: %v", parts)
	}
	// writing chunks after completion is rejected
	if _, err := s.WriteChunk(ctx, b.ID, 0, bytes.NewReader([]byte("abcd"))); !errors.Is(err, store.ErrConflict) {
		t.Fatalf("write after complete err = %v", err)
	}

	// delivery tracking
	all, err := s.MarkBlobDelivered(ctx, b.ID, "dev_stranger")
	if err != nil || all {
		t.Fatalf("stranger delivered = %v, %v", all, err)
	}
	all, err = s.MarkBlobDelivered(ctx, b.ID, r1.ID)
	if err != nil || all {
		t.Fatalf("first delivered = %v, %v", all, err)
	}
	all, err = s.MarkBlobDelivered(ctx, b.ID, r1.ID)
	if err != nil || all {
		t.Fatalf("repeat delivered = %v, %v", all, err)
	}
	all, err = s.MarkBlobDelivered(ctx, b.ID, r2.ID)
	if err != nil || !all {
		t.Fatalf("last delivered = %v, %v", all, err)
	}
	if _, err := s.MarkBlobDelivered(ctx, "blob_missing", r2.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("mark missing err = %v", err)
	}

	if err := s.DeleteBlob(ctx, b.ID); err != nil {
		t.Fatalf("delete: %v", err)
	}
	if err := s.DeleteBlob(ctx, b.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("delete twice err = %v", err)
	}
	if _, err := os.Stat(s.BlobPath(b.ID)); !os.IsNotExist(err) {
		t.Fatalf("file should be gone: %v", err)
	}
}

func TestBlobExpiryAndDeviceCascade(t *testing.T) {
	s := openTest(t)
	ctx := context.Background()
	u, _ := s.CreateUser(ctx, "Felipe", store.RoleAdmin)
	owner, _ := mkDevice(t, s, u.ID, "Mac")
	r1, _ := mkDevice(t, s, u.ID, "Phone")
	now := time.Date(2026, 9, 6, 18, 0, 0, 0, time.UTC)

	old := store.Blob{ID: store.NewID("blob_"), OwnerDevice: owner.ID, Size: 2, ChunkSize: 4, CreatedAt: now.Add(-40 * 24 * time.Hour), ExpiresAt: now.Add(-10 * 24 * time.Hour)}
	fresh := store.Blob{ID: store.NewID("blob_"), OwnerDevice: owner.ID, Size: 2, ChunkSize: 4, CreatedAt: now, ExpiresAt: now.Add(30 * 24 * time.Hour)}
	for _, b := range []store.Blob{old, fresh} {
		if err := s.CreateBlob(ctx, b, []string{r1.ID}); err != nil {
			t.Fatalf("create: %v", err)
		}
		if _, err := s.WriteChunk(ctx, b.ID, 0, bytes.NewReader([]byte("ab"))); err != nil {
			t.Fatalf("chunk: %v", err)
		}
	}
	if err := s.CompleteBlob(ctx, fresh.ID); err != nil {
		t.Fatalf("complete: %v", err)
	}
	n, err := s.ExpireBlobs(ctx, now)
	if err != nil || n != 1 {
		t.Fatalf("expire = %d, %v", n, err)
	}
	if _, err := s.GetBlob(ctx, old.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("old should be gone: %v", err)
	}
	if parts, _ := filepath.Glob(filepath.Join(s.BlobDir(), old.ID+"*")); len(parts) != 0 {
		t.Fatalf("old parts left: %v", parts)
	}
	if _, err := os.Stat(s.BlobPath(fresh.ID)); err != nil {
		t.Fatalf("fresh file missing: %v", err)
	}

	// sweep of fully delivered blobs: fresh is complete but undelivered → stays
	n, err = s.DeleteDeliveredBlobs(ctx)
	if err != nil || n != 0 {
		t.Fatalf("sweep undelivered = %d, %v", n, err)
	}
	if _, err := s.MarkBlobDelivered(ctx, fresh.ID, r1.ID); err != nil {
		t.Fatal(err)
	}
	n, err = s.DeleteDeliveredBlobs(ctx)
	if err != nil || n != 1 {
		t.Fatalf("sweep delivered = %d, %v", n, err)
	}
	if _, err := os.Stat(s.BlobPath(fresh.ID)); !os.IsNotExist(err) {
		t.Fatalf("delivered file should be gone: %v", err)
	}
	// recreate fresh for the cascade check below
	if err := s.CreateBlob(ctx, fresh, []string{r1.ID}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.WriteChunk(ctx, fresh.ID, 0, bytes.NewReader([]byte("ab"))); err != nil {
		t.Fatal(err)
	}
	if err := s.CompleteBlob(ctx, fresh.ID); err != nil {
		t.Fatal(err)
	}

	// deleting the owner device removes its blobs (rows and files)
	if err := s.DeleteDevice(ctx, owner.ID); err != nil {
		t.Fatalf("delete owner: %v", err)
	}
	if _, err := s.GetBlob(ctx, fresh.ID); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("fresh should be gone: %v", err)
	}
	if _, err := os.Stat(s.BlobPath(fresh.ID)); !os.IsNotExist(err) {
		t.Fatalf("fresh file should be gone: %v", err)
	}
}
