package api

import (
	"errors"
	"fmt"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/felipemaion/chatito/server/internal/store"
)

func (s *Server) createBlob(w http.ResponseWriter, r *http.Request) error {
	var req BlobCreateRequest
	if err := decodeJSON(w, r, maxJSONBody, &req); err != nil {
		return err
	}
	if req.Size <= 0 {
		return errorf(http.StatusBadRequest, CodeValidation, "size must be positive")
	}
	if req.Size > MaxBlobSize {
		return errorf(http.StatusRequestEntityTooLarge, CodePayloadTooLarge, fmt.Sprintf("size exceeds %d bytes", MaxBlobSize))
	}
	if len(req.Recipients) == 0 {
		return errorf(http.StatusBadRequest, CodeValidation, "recipients must not be empty")
	}
	ctx := r.Context()
	for _, id := range req.Recipients {
		if _, err := s.store.GetDevice(ctx, id); err != nil {
			return errorf(http.StatusBadRequest, CodeValidation, "unknown recipient "+id)
		}
	}
	d, _ := DeviceFrom(ctx)
	now := s.now()
	b := store.Blob{
		ID: store.NewID("blob_"), OwnerDevice: d.ID, Size: req.Size, ChunkSize: ChunkSize,
		CreatedAt: now, ExpiresAt: now.Add(BlobTTL),
	}
	if err := s.store.CreateBlob(ctx, b, req.Recipients); err != nil {
		return err
	}
	writeJSON(w, http.StatusCreated, BlobCreateResponse{BlobID: b.ID, ChunkSize: b.ChunkSize, ExpiresAt: timeStr(b.ExpiresAt)})
	return nil
}

// ownedBlob loads the blob and checks the caller owns it.
func (s *Server) ownedBlob(r *http.Request) (store.Blob, error) {
	b, err := s.store.GetBlob(r.Context(), r.PathValue("id"))
	if err != nil {
		return store.Blob{}, err
	}
	d, _ := DeviceFrom(r.Context())
	if b.OwnerDevice != d.ID {
		return store.Blob{}, errorf(http.StatusForbidden, CodeForbidden, "not the blob owner")
	}
	return b, nil
}

func (s *Server) putChunk(w http.ResponseWriter, r *http.Request) error {
	b, err := s.ownedBlob(r)
	if err != nil {
		return err
	}
	n, err := strconv.Atoi(r.PathValue("n"))
	if err != nil {
		return errorf(http.StatusBadRequest, CodeValidation, "chunk index must be an integer")
	}
	body := http.MaxBytesReader(w, r.Body, b.ChunkSize)
	if _, err := s.store.WriteChunk(r.Context(), b.ID, n, body); err != nil {
		return err
	}
	w.WriteHeader(http.StatusNoContent)
	return nil
}

func (s *Server) completeBlob(w http.ResponseWriter, r *http.Request) error {
	b, err := s.ownedBlob(r)
	if err != nil {
		return err
	}
	if err := s.store.CompleteBlob(r.Context(), b.ID); err != nil {
		return err
	}
	writeJSON(w, http.StatusOK, BlobCompleteResponse{BlobID: b.ID, Size: b.Size})
	return nil
}

func (s *Server) deleteBlob(w http.ResponseWriter, r *http.Request) error {
	b, err := s.ownedBlob(r)
	if err != nil {
		return err
	}
	if err := s.store.DeleteBlob(r.Context(), b.ID); err != nil {
		return err
	}
	w.WriteHeader(http.StatusNoContent)
	return nil
}

// countingWriter records the status and bytes actually written.
type countingWriter struct {
	http.ResponseWriter
	status  int
	written int64
}

func (c *countingWriter) WriteHeader(code int) {
	c.status = code
	c.ResponseWriter.WriteHeader(code)
}

func (c *countingWriter) Write(p []byte) (int, error) {
	if c.status == 0 {
		c.status = http.StatusOK
	}
	n, err := c.ResponseWriter.Write(p)
	c.written += int64(n)
	return n, err
}

func (s *Server) getBlob(w http.ResponseWriter, r *http.Request) error {
	ctx := r.Context()
	b, err := s.store.GetBlob(ctx, r.PathValue("id"))
	if err != nil {
		return err
	}
	if !b.Complete || !s.now().Before(b.ExpiresAt) {
		return errorf(http.StatusNotFound, CodeNotFound, "not found")
	}
	d, _ := DeviceFrom(ctx)
	isOwner := b.OwnerDevice == d.ID
	if !isOwner {
		recs, err := s.store.BlobRecipients(ctx, b.ID)
		if err != nil {
			return err
		}
		allowed := false
		for _, rc := range recs {
			allowed = allowed || rc.DeviceID == d.ID
		}
		if !allowed {
			return errorf(http.StatusForbidden, CodeForbidden, "not a recipient")
		}
	}
	f, err := os.Open(s.store.BlobPath(b.ID))
	if err != nil {
		return fmt.Errorf("api: open blob: %w", err)
	}
	w.Header().Set("Content-Type", "application/octet-stream")
	cw := &countingWriter{ResponseWriter: w}
	http.ServeContent(cw, r, "", time.Time{}, f)
	_ = f.Close()
	if isOwner || !fullyServed(cw, b.Size) {
		return nil
	}
	all, err := s.store.MarkBlobDelivered(ctx, b.ID, d.ID)
	if err != nil {
		s.log.Warn("mark delivered failed", "blob", b.ID, "err", err)
		return nil
	}
	if all {
		if err := s.store.DeleteBlob(ctx, b.ID); err != nil && !errors.Is(err, store.ErrNotFound) {
			s.log.Warn("delete delivered blob failed", "blob", b.ID, "err", err)
		}
		s.log.Info("blob delivered to all recipients", "blob", b.ID)
	}
	return nil
}

// fullyServed reports whether the response delivered the tail of the blob:
// either the whole file, or a range that reaches its last byte. A client
// resuming a download therefore counts as delivered when it fetches the end.
func fullyServed(cw *countingWriter, size int64) bool {
	if cw.status != http.StatusOK && cw.status != http.StatusPartialContent {
		return false
	}
	if cl, err := strconv.ParseInt(cw.Header().Get("Content-Length"), 10, 64); err != nil || cl != cw.written {
		return false
	}
	if cw.status == http.StatusOK {
		return true
	}
	// Content-Range: bytes start-end/size
	var start, end, total int64
	if _, err := fmt.Sscanf(cw.Header().Get("Content-Range"), "bytes %d-%d/%d", &start, &end, &total); err != nil {
		return false
	}
	return end == size-1
}
