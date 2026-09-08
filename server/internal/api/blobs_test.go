package api_test

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"testing"
	"time"

	"github.com/felipemaion/piriquito/server/internal/api"
	"github.com/felipemaion/piriquito/server/internal/store"
)

func newBlobEnv(t *testing.T) *env {
	t.Helper()
	return newEnv(t)
}

func TestBlobFlow(t *testing.T) {
	e := newBlobEnv(t)
	adm := e.admin()
	mem := e.member("Mãe")
	_, ownerTok := e.register(adm.ID, "Mac")
	memDev, memTok := e.register(mem.ID, "Galaxy")
	memDev2, memTok2 := e.register(mem.ID, "Tablet")
	_, strangerTok := e.register(e.member("Filho").ID, "PC")

	chunk := int64(api.ChunkSize)
	size := chunk + 10
	r := e.do("POST", "/v1/blobs", ownerTok, map[string]any{"size": size, "recipients": []string{memDev, memDev2}})
	if r.code != 201 {
		t.Fatalf("create = %d %s", r.code, r.body)
	}
	var created api.BlobCreateResponse
	r.json(t, &created)
	if created.ChunkSize != api.ChunkSize || created.ExpiresAt != "2026-10-06T18:00:00Z" || len(created.BlobID) != 27 {
		t.Fatalf("created = %+v", created)
	}
	id := created.BlobID
	path := "/v1/blobs/" + id

	// complete before chunks -> 409 incomplete_blob
	r = e.do("POST", path+"/complete", ownerTok, nil)
	if r.code != 409 || r.errCode(t) != "incomplete_blob" {
		t.Fatalf("early complete = %d %s", r.code, r.body)
	}
	// non-owner cannot upload/complete/delete
	if r = e.do("PUT", path+"/chunks/0", memTok, bytes.Repeat([]byte("a"), int(chunk))); r.code != 403 {
		t.Fatalf("stranger chunk = %d %s", r.code, r.body)
	}
	if r = e.do("POST", path+"/complete", memTok, nil); r.code != 403 {
		t.Fatalf("stranger complete = %d", r.code)
	}
	if r = e.do("DELETE", path, memTok, nil); r.code != 403 {
		t.Fatalf("stranger delete = %d", r.code)
	}
	// chunk validation
	if r = e.do("PUT", path+"/chunks/2", ownerTok, []byte("x")); r.code != 400 || r.errCode(t) != "chunk_out_of_range" {
		t.Fatalf("out of range = %d %s", r.code, r.body)
	}
	if r = e.do("PUT", path+"/chunks/x", ownerTok, []byte("x")); r.code != 400 {
		t.Fatalf("bad index = %d %s", r.code, r.body)
	}
	if r = e.do("PUT", path+"/chunks/0", ownerTok, []byte("short")); r.code != 400 || r.errCode(t) != "validation" {
		t.Fatalf("short chunk = %d %s", r.code, r.body)
	}
	if r = e.do("PUT", path+"/chunks/0", ownerTok, bytes.Repeat([]byte("a"), int(chunk)+1)); r.code != 413 || r.errCode(t) != "payload_too_large" {
		t.Fatalf("oversize chunk = %d %s", r.code, r.body)
	}
	if r = e.do("PUT", "/v1/blobs/blob_nope/chunks/0", ownerTok, []byte("x")); r.code != 404 {
		t.Fatalf("unknown blob = %d %s", r.code, r.body)
	}
	// happy path
	first := bytes.Repeat([]byte("a"), int(chunk))
	last := []byte("0123456789")
	if r = e.do("PUT", path+"/chunks/0", ownerTok, first); r.code != 204 {
		t.Fatalf("chunk 0 = %d %s", r.code, r.body)
	}
	if r = e.do("PUT", path+"/chunks/1", ownerTok, last); r.code != 204 {
		t.Fatalf("chunk 1 = %d %s", r.code, r.body)
	}
	// download before complete is 404 (not visible yet)
	if r = e.do("GET", path, memTok, nil); r.code != 404 {
		t.Fatalf("get incomplete = %d %s", r.code, r.body)
	}
	r = e.do("POST", path+"/complete", ownerTok, nil)
	if r.code != 200 {
		t.Fatalf("complete = %d %s", r.code, r.body)
	}
	var done api.BlobCompleteResponse
	r.json(t, &done)
	if done.BlobID != id || done.Size != size {
		t.Fatalf("done = %+v", done)
	}
	if r = e.do("PUT", path+"/chunks/0", ownerTok, first); r.code != 409 {
		t.Fatalf("chunk after complete = %d %s", r.code, r.body)
	}

	// stranger cannot read
	if r = e.do("GET", path, strangerTok, nil); r.code != 403 {
		t.Fatalf("stranger get = %d", r.code)
	}
	// owner can read, without affecting delivery
	r = e.do("GET", path, ownerTok, nil)
	if r.code != 200 || int64(len(r.body)) != size || r.hdr.Get("Content-Length") != fmt.Sprint(size) || r.hdr.Get("Content-Type") != "application/octet-stream" {
		t.Fatalf("owner get = %d len=%d hdr=%v", r.code, len(r.body), r.hdr)
	}
	// range request by recipient 1: partial does not mark delivered
	r = e.do("GET", path, memTok, nil, "Range", "bytes=0-3")
	if r.code != 206 || string(r.body) != "aaaa" || r.hdr.Get("Content-Range") == "" {
		t.Fatalf("range = %d %q %v", r.code, r.body, r.hdr)
	}
	recs, _ := e.st.BlobRecipients(context.Background(), id)
	if recs[0].Delivered {
		t.Fatal("partial range must not mark delivered")
	}
	// final range (resume to the end) marks delivered
	r = e.do("GET", path, memTok, nil, "Range", fmt.Sprintf("bytes=%d-", chunk))
	if r.code != 206 || string(r.body) != "0123456789" {
		t.Fatalf("tail range = %d %q", r.code, r.body)
	}
	recs, _ = e.st.BlobRecipients(context.Background(), id)
	if !recs[0].Delivered || recs[1].Delivered {
		t.Fatalf("after tail range recs = %+v", recs)
	}
	// last recipient full download deletes the blob
	r = e.do("GET", path, memTok2, nil)
	if r.code != 200 || !bytes.Equal(r.body, append(first, last...)) {
		t.Fatalf("full get = %d len=%d", r.code, len(r.body))
	}
	if _, err := e.st.GetBlob(context.Background(), id); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("blob should be deleted after all delivered: %v", err)
	}
	if _, err := os.Stat(e.st.BlobPath(id)); !os.IsNotExist(err) {
		t.Fatalf("file should be gone: %v", err)
	}
	if r = e.do("GET", path, memTok, nil); r.code != 404 {
		t.Fatalf("get deleted = %d", r.code)
	}

	// owner delete
	r = e.do("POST", "/v1/blobs", ownerTok, map[string]any{"size": 3, "recipients": []string{memDev}})
	r.json(t, &created)
	if r = e.do("DELETE", "/v1/blobs/"+created.BlobID, ownerTok, nil); r.code != 204 {
		t.Fatalf("delete = %d %s", r.code, r.body)
	}
	if r = e.do("DELETE", "/v1/blobs/"+created.BlobID, ownerTok, nil); r.code != 404 {
		t.Fatalf("delete twice = %d", r.code)
	}
	if r = e.do("POST", "/v1/blobs/blob_nope/complete", ownerTok, nil); r.code != 404 {
		t.Fatalf("complete unknown = %d", r.code)
	}
}

func TestBlobCreateValidation(t *testing.T) {
	e := newBlobEnv(t)
	adm := e.admin()
	memDev, _ := e.register(e.member("Mãe").ID, "Galaxy")
	_, tok := e.register(adm.ID, "Mac")
	for name, body := range map[string]any{
		"zero size":   map[string]any{"size": 0, "recipients": []string{memDev}},
		"neg size":    map[string]any{"size": -1, "recipients": []string{memDev}},
		"no recips":   map[string]any{"size": 10, "recipients": []string{}},
		"missing rec": map[string]any{"size": 10},
		"unknown rec": map[string]any{"size": 10, "recipients": []string{"dev_nope"}},
		"bad json":    "{",
		"too big":     map[string]any{"size": api.MaxBlobSize + 1, "recipients": []string{memDev}},
	} {
		r := e.do("POST", "/v1/blobs", tok, body)
		if r.code != 400 && r.code != 413 {
			t.Fatalf("%s = %d %s", name, r.code, r.body)
		}
	}
	r := e.do("POST", "/v1/blobs", tok, map[string]any{"size": api.MaxBlobSize, "recipients": []string{memDev}})
	if r.code != 201 {
		t.Fatalf("max size = %d %s", r.code, r.body)
	}
}

func TestBlobExpiryHonoursClock(t *testing.T) {
	e := newBlobEnv(t)
	adm := e.admin()
	memDev, memTok := e.register(e.member("Mãe").ID, "Galaxy")
	_, tok := e.register(adm.ID, "Mac")
	r := e.do("POST", "/v1/blobs", tok, map[string]any{"size": 3, "recipients": []string{memDev}})
	var created api.BlobCreateResponse
	r.json(t, &created)
	_ = e.do("PUT", "/v1/blobs/"+created.BlobID+"/chunks/0", tok, []byte("abc"))
	_ = e.do("POST", "/v1/blobs/"+created.BlobID+"/complete", tok, nil)
	e.now = e.now.Add(31 * 24 * time.Hour)
	if r = e.do("GET", "/v1/blobs/"+created.BlobID, memTok, nil); r.code != 404 {
		t.Fatalf("expired blob get = %d", r.code)
	}
}
