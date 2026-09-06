package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"time"
)

// Blob-specific errors.
var (
	ErrIncomplete      = errors.New("incomplete blob")
	ErrChunkOutOfRange = errors.New("chunk out of range")
)

// Blob is an encrypted file uploaded in chunks and assembled on completion.
type Blob struct {
	ID          string
	OwnerDevice string
	Size        int64
	ChunkSize   int64
	Complete    bool
	CreatedAt   time.Time
	ExpiresAt   time.Time
}

// BlobRecipient tracks whether a recipient device already downloaded a blob.
type BlobRecipient struct {
	DeviceID  string
	Delivered bool
}

// ChunkCount returns ceil(Size/ChunkSize).
func (b Blob) ChunkCount() int {
	if b.ChunkSize <= 0 {
		return 0
	}
	return int((b.Size + b.ChunkSize - 1) / b.ChunkSize)
}

// expectedChunkSize returns the byte length chunk n must have.
func (b Blob) expectedChunkSize(n int) int64 {
	if n < b.ChunkCount()-1 {
		return b.ChunkSize
	}
	return b.Size - int64(n)*b.ChunkSize
}

// BlobPath returns the path of the assembled blob file.
func (s *Store) BlobPath(id string) string { return filepath.Join(s.blobDir, id) }

func (s *Store) chunkPath(id string, n int) string {
	return filepath.Join(s.blobDir, id+"."+strconv.Itoa(n)+".part")
}

// CreateBlob registers a blob and its recipients (at least one).
func (s *Store) CreateBlob(ctx context.Context, b Blob, recipients []string) error {
	if len(recipients) == 0 {
		return fmt.Errorf("store: blob needs recipients: %w", ErrValidation)
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("store: begin: %w", err)
	}
	defer func() { _ = tx.Rollback() }()
	_, err = tx.ExecContext(ctx,
		`INSERT INTO blobs (id,owner_device,size,chunk_size,complete,created_at,expires_at) VALUES (?,?,?,?,0,?,?)`,
		b.ID, b.OwnerDevice, b.Size, b.ChunkSize, fmtTime(b.CreatedAt), fmtTime(b.ExpiresAt))
	if isUniqueErr(err) {
		return fmt.Errorf("store: blob %s exists: %w", b.ID, ErrConflict)
	}
	if err != nil {
		return fmt.Errorf("store: create blob: %w", err)
	}
	for _, r := range recipients {
		if _, err := tx.ExecContext(ctx, `INSERT OR IGNORE INTO blob_recipients (blob_id,device_id) VALUES (?,?)`, b.ID, r); err != nil {
			return fmt.Errorf("store: add recipient: %w", err)
		}
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("store: commit: %w", err)
	}
	return nil
}

const blobCols = `id, owner_device, size, chunk_size, complete, created_at, expires_at`

func scanBlob(row scanner) (Blob, error) {
	var b Blob
	var created, expires string
	var complete int
	if err := row.Scan(&b.ID, &b.OwnerDevice, &b.Size, &b.ChunkSize, &complete, &created, &expires); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return Blob{}, ErrNotFound
		}
		return Blob{}, fmt.Errorf("store: scan blob: %w", err)
	}
	b.Complete = complete == 1
	var err error
	if b.CreatedAt, err = parseTime(created); err != nil {
		return Blob{}, err
	}
	if b.ExpiresAt, err = parseTime(expires); err != nil {
		return Blob{}, err
	}
	return b, nil
}

// GetBlob returns blob metadata.
func (s *Store) GetBlob(ctx context.Context, id string) (Blob, error) {
	return scanBlob(s.db.QueryRowContext(ctx, `SELECT `+blobCols+` FROM blobs WHERE id = ?`, id))
}

// BlobRecipients lists the recipients of a blob in insertion order.
func (s *Store) BlobRecipients(ctx context.Context, id string) ([]BlobRecipient, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT device_id, delivered FROM blob_recipients WHERE blob_id = ? ORDER BY rowid`, id)
	if err != nil {
		return nil, fmt.Errorf("store: blob recipients: %w", err)
	}
	defer func() { _ = rows.Close() }()
	var out []BlobRecipient
	for rows.Next() {
		var r BlobRecipient
		var d int
		if err := rows.Scan(&r.DeviceID, &d); err != nil {
			return nil, fmt.Errorf("store: scan recipient: %w", err)
		}
		r.Delivered = d == 1
		out = append(out, r)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("store: blob recipients: %w", err)
	}
	return out, nil
}

// WriteChunk stores chunk n of a blob from r, validating its index and exact
// size. Re-writing an existing chunk overwrites it.
func (s *Store) WriteChunk(ctx context.Context, id string, n int, r io.Reader) (int64, error) {
	b, err := s.GetBlob(ctx, id)
	if err != nil {
		return 0, err
	}
	if b.Complete {
		return 0, fmt.Errorf("store: blob already complete: %w", ErrConflict)
	}
	if n < 0 || n >= b.ChunkCount() {
		return 0, fmt.Errorf("store: chunk %d of %d: %w", n, b.ChunkCount(), ErrChunkOutOfRange)
	}
	want := b.expectedChunkSize(n)
	tmp := s.chunkPath(id, n) + ".tmp"
	f, err := os.OpenFile(tmp, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o640)
	if err != nil {
		return 0, fmt.Errorf("store: create chunk: %w", err)
	}
	written, err := io.Copy(f, io.LimitReader(r, want+1))
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		_ = os.Remove(tmp)
		return 0, fmt.Errorf("store: write chunk: %w", err)
	}
	if written != want {
		_ = os.Remove(tmp)
		return 0, fmt.Errorf("store: chunk %d size %d, want %d: %w", n, written, want, ErrValidation)
	}
	if err := os.Rename(tmp, s.chunkPath(id, n)); err != nil {
		_ = os.Remove(tmp)
		return 0, fmt.Errorf("store: commit chunk: %w", err)
	}
	if _, err := s.db.ExecContext(ctx,
		`INSERT INTO blob_chunks (blob_id,n,size) VALUES (?,?,?) ON CONFLICT(blob_id,n) DO UPDATE SET size = excluded.size`,
		id, n, written); err != nil {
		return 0, fmt.Errorf("store: record chunk: %w", err)
	}
	return written, nil
}

// CompleteBlob verifies every chunk is present, assembles them into one file
// and marks the blob complete. Idempotent once complete.
func (s *Store) CompleteBlob(ctx context.Context, id string) error {
	b, err := s.GetBlob(ctx, id)
	if err != nil {
		return err
	}
	if b.Complete {
		return nil
	}
	var have int
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM blob_chunks WHERE blob_id = ?`, id).Scan(&have); err != nil {
		return fmt.Errorf("store: count chunks: %w", err)
	}
	if have != b.ChunkCount() {
		return fmt.Errorf("store: %d of %d chunks: %w", have, b.ChunkCount(), ErrIncomplete)
	}
	if err := s.assemble(b); err != nil {
		return err
	}
	if _, err := s.db.ExecContext(ctx, `UPDATE blobs SET complete = 1 WHERE id = ?`, id); err != nil {
		return fmt.Errorf("store: mark complete: %w", err)
	}
	if _, err := s.db.ExecContext(ctx, `DELETE FROM blob_chunks WHERE blob_id = ?`, id); err != nil {
		return fmt.Errorf("store: drop chunk rows: %w", err)
	}
	for n := range b.ChunkCount() {
		_ = os.Remove(s.chunkPath(id, n))
	}
	return nil
}

func (s *Store) assemble(b Blob) error {
	tmp := s.BlobPath(b.ID) + ".tmp"
	out, err := os.OpenFile(tmp, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o640)
	if err != nil {
		return fmt.Errorf("store: create blob file: %w", err)
	}
	var total int64
	for n := range b.ChunkCount() {
		in, err := os.Open(s.chunkPath(b.ID, n))
		if err != nil {
			_ = out.Close()
			_ = os.Remove(tmp)
			return fmt.Errorf("store: chunk %d missing: %w", n, ErrIncomplete)
		}
		w, err := io.Copy(out, in)
		_ = in.Close()
		if err != nil {
			_ = out.Close()
			_ = os.Remove(tmp)
			return fmt.Errorf("store: assemble chunk %d: %w", n, err)
		}
		total += w
	}
	if err := out.Close(); err != nil {
		_ = os.Remove(tmp)
		return fmt.Errorf("store: close blob file: %w", err)
	}
	if total != b.Size {
		_ = os.Remove(tmp)
		return fmt.Errorf("store: assembled %d bytes, want %d: %w", total, b.Size, ErrIncomplete)
	}
	if err := os.Rename(tmp, s.BlobPath(b.ID)); err != nil {
		_ = os.Remove(tmp)
		return fmt.Errorf("store: finalize blob: %w", err)
	}
	return nil
}

// MarkBlobDelivered flags deviceID as having downloaded the blob and reports
// whether every recipient has now been served. Non-recipients are ignored.
func (s *Store) MarkBlobDelivered(ctx context.Context, id, deviceID string) (bool, error) {
	if _, err := s.GetBlob(ctx, id); err != nil {
		return false, err
	}
	if _, err := s.db.ExecContext(ctx, `UPDATE blob_recipients SET delivered = 1 WHERE blob_id = ? AND device_id = ?`, id, deviceID); err != nil {
		return false, fmt.Errorf("store: mark delivered: %w", err)
	}
	var pending int
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM blob_recipients WHERE blob_id = ? AND delivered = 0`, id).Scan(&pending); err != nil {
		return false, fmt.Errorf("store: count pending recipients: %w", err)
	}
	return pending == 0, nil
}

// DeleteBlob removes a blob's rows and files.
func (s *Store) DeleteBlob(ctx context.Context, id string) error {
	b, err := s.GetBlob(ctx, id)
	if err != nil {
		return err
	}
	if _, err := s.db.ExecContext(ctx, `DELETE FROM blobs WHERE id = ?`, id); err != nil {
		return fmt.Errorf("store: delete blob: %w", err)
	}
	s.removeBlobFiles(b)
	return nil
}

func (s *Store) removeBlobFiles(b Blob) {
	_ = os.Remove(s.BlobPath(b.ID))
	for n := range b.ChunkCount() {
		_ = os.Remove(s.chunkPath(b.ID, n))
	}
}

// ExpireBlobs deletes blobs whose expiry is at or before now.
func (s *Store) ExpireBlobs(ctx context.Context, now time.Time) (int, error) {
	blobs, err := s.listBlobs(ctx, `WHERE expires_at <= ?`, fmtTime(now))
	if err != nil {
		return 0, err
	}
	var n int
	for _, b := range blobs {
		if err := s.DeleteBlob(ctx, b.ID); err != nil && !errors.Is(err, ErrNotFound) {
			return n, err
		}
		n++
	}
	return n, nil
}

// DeleteDeliveredBlobs removes complete blobs that every recipient already
// downloaded (safety net for deliveries whose cleanup failed).
func (s *Store) DeleteDeliveredBlobs(ctx context.Context) (int, error) {
	blobs, err := s.listBlobs(ctx, `WHERE complete = 1 AND NOT EXISTS (
		SELECT 1 FROM blob_recipients r WHERE r.blob_id = blobs.id AND r.delivered = 0)`)
	if err != nil {
		return 0, err
	}
	var n int
	for _, b := range blobs {
		if err := s.DeleteBlob(ctx, b.ID); err != nil && !errors.Is(err, ErrNotFound) {
			return n, err
		}
		n++
	}
	return n, nil
}

func (s *Store) listBlobs(ctx context.Context, where string, args ...any) ([]Blob, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT `+blobCols+` FROM blobs `+where, args...)
	if err != nil {
		return nil, fmt.Errorf("store: list blobs: %w", err)
	}
	defer func() { _ = rows.Close() }()
	var out []Blob
	for rows.Next() {
		b, err := scanBlob(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, b)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("store: list blobs: %w", err)
	}
	return out, nil
}
