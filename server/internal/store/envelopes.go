package store

import (
	"context"
	"fmt"
	"strings"
	"time"
)

// Envelope is an opaque ciphertext addressed to one device.
type Envelope struct {
	ID         string
	FromDevice string
	ToDevice   string
	Nonce      []byte
	Ciphertext []byte
	CreatedAt  time.Time
}

// InsertEnvelopes stores a batch atomically. If any recipient device does not
// exist the whole batch is rejected with ErrNotFound.
func (s *Store) InsertEnvelopes(ctx context.Context, envs []Envelope) error {
	if len(envs) == 0 {
		return nil
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("store: begin: %w", err)
	}
	defer func() { _ = tx.Rollback() }()
	for _, e := range envs {
		_, err := tx.ExecContext(ctx,
			`INSERT INTO envelopes (id,from_device,to_device,nonce,ciphertext,created_at) VALUES (?,?,?,?,?,?)`,
			e.ID, e.FromDevice, e.ToDevice, e.Nonce, e.Ciphertext, fmtTime(e.CreatedAt))
		if err != nil {
			if strings.Contains(err.Error(), "FOREIGN KEY constraint failed") {
				return fmt.Errorf("store: recipient %s: %w", e.ToDevice, ErrNotFound)
			}
			return fmt.Errorf("store: insert envelope: %w", err)
		}
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("store: commit: %w", err)
	}
	return nil
}

const envelopeCols = `id, from_device, to_device, nonce, ciphertext, created_at`

func scanEnvelope(row scanner) (Envelope, error) {
	var e Envelope
	var created string
	if err := row.Scan(&e.ID, &e.FromDevice, &e.ToDevice, &e.Nonce, &e.Ciphertext, &created); err != nil {
		return Envelope{}, fmt.Errorf("store: scan envelope: %w", err)
	}
	t, err := parseTime(created)
	if err != nil {
		return Envelope{}, err
	}
	e.CreatedAt = t
	return e, nil
}

// ListPendingEnvelopes returns up to limit envelopes for deviceID, oldest first.
func (s *Store) ListPendingEnvelopes(ctx context.Context, deviceID string, limit int) ([]Envelope, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT `+envelopeCols+` FROM envelopes WHERE to_device = ? ORDER BY created_at, rowid LIMIT ?`, deviceID, limit)
	if err != nil {
		return nil, fmt.Errorf("store: list envelopes: %w", err)
	}
	defer func() { _ = rows.Close() }()
	var out []Envelope
	for rows.Next() {
		e, err := scanEnvelope(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("store: list envelopes: %w", err)
	}
	return out, nil
}

// CountPendingEnvelopes counts envelopes queued for deviceID.
func (s *Store) CountPendingEnvelopes(ctx context.Context, deviceID string) (int, error) {
	var n int
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM envelopes WHERE to_device = ?`, deviceID).Scan(&n); err != nil {
		return 0, fmt.Errorf("store: count envelopes: %w", err)
	}
	return n, nil
}

// AckEnvelopes removes the given envelopes, but only those addressed to
// deviceID. Unknown ids are ignored.
func (s *Store) AckEnvelopes(ctx context.Context, deviceID string, ids []string) error {
	if len(ids) == 0 {
		return nil
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("store: begin: %w", err)
	}
	defer func() { _ = tx.Rollback() }()
	for _, id := range ids {
		if _, err := tx.ExecContext(ctx, `DELETE FROM envelopes WHERE id = ? AND to_device = ?`, id, deviceID); err != nil {
			return fmt.Errorf("store: ack envelope: %w", err)
		}
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("store: commit: %w", err)
	}
	return nil
}

// ExpireEnvelopes removes envelopes created before cutoff.
func (s *Store) ExpireEnvelopes(ctx context.Context, cutoff time.Time) (int64, error) {
	res, err := s.db.ExecContext(ctx, `DELETE FROM envelopes WHERE created_at < ?`, fmtTime(cutoff))
	if err != nil {
		return 0, fmt.Errorf("store: expire envelopes: %w", err)
	}
	n, _ := res.RowsAffected()
	return n, nil
}
