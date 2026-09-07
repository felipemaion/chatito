package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

// Invite is a single-use registration code issued by an admin.
type Invite struct {
	Code      string
	UserID    string
	ExpiresAt time.Time
}

// CreateInvite issues a new invite for userID.
func (s *Store) CreateInvite(ctx context.Context, userID string, expiresAt time.Time) (Invite, error) {
	if _, err := s.GetUser(ctx, userID); err != nil {
		return Invite{}, err
	}
	inv := Invite{Code: newInviteCode(), UserID: userID, ExpiresAt: expiresAt.UTC()}
	_, err := s.db.ExecContext(ctx, `INSERT INTO invites (code,user_id,expires_at) VALUES (?,?,?)`,
		inv.Code, inv.UserID, fmtTime(inv.ExpiresAt))
	if err != nil {
		return Invite{}, fmt.Errorf("store: create invite: %w", err)
	}
	return inv, nil
}

// RedeemInvite atomically marks an unused, unexpired invite as used and
// returns it. Any failure maps to ErrInvalidInvite.
func (s *Store) RedeemInvite(ctx context.Context, code string, now time.Time) (Invite, error) {
	code = NormalizeInviteCode(code)
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Invite{}, fmt.Errorf("store: begin: %w", err)
	}
	defer func() { _ = tx.Rollback() }()
	var inv Invite
	var expires string
	var used sql.NullString
	err = tx.QueryRowContext(ctx, `SELECT code,user_id,expires_at,used_at FROM invites WHERE code = ?`, code).
		Scan(&inv.Code, &inv.UserID, &expires, &used)
	if errors.Is(err, sql.ErrNoRows) {
		return Invite{}, ErrInvalidInvite
	}
	if err != nil {
		return Invite{}, fmt.Errorf("store: redeem: %w", err)
	}
	if inv.ExpiresAt, err = parseTime(expires); err != nil {
		return Invite{}, err
	}
	if used.Valid || !now.Before(inv.ExpiresAt) {
		return Invite{}, ErrInvalidInvite
	}
	if _, err := tx.ExecContext(ctx, `UPDATE invites SET used_at = ? WHERE code = ? AND used_at IS NULL`, fmtTime(now), code); err != nil {
		return Invite{}, fmt.Errorf("store: mark invite used: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return Invite{}, fmt.Errorf("store: commit: %w", err)
	}
	return inv, nil
}

// ExpireInvites removes invites whose expiry is at or before now.
func (s *Store) ExpireInvites(ctx context.Context, now time.Time) (int64, error) {
	res, err := s.db.ExecContext(ctx, `DELETE FROM invites WHERE expires_at <= ?`, fmtTime(now))
	if err != nil {
		return 0, fmt.Errorf("store: expire invites: %w", err)
	}
	n, _ := res.RowsAffected()
	return n, nil
}
