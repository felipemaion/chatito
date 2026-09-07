package store

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"time"
)

// Device is one installation of the app, bound to a user.
type Device struct {
	ID          string
	UserID      string
	Name        string
	Platform    string
	IdentityKey string // base64 X25519 public key
	TokenHash   string // hex SHA-256 of the bearer token
	FCMToken    *string
	CreatedAt   time.Time
}

// HashToken returns the hex SHA-256 of a bearer token.
func HashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}

// CreateDevice inserts a device. The caller fills every field.
func (s *Store) CreateDevice(ctx context.Context, d Device) error {
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO devices (id,user_id,name,platform,identity_key,token_hash,fcm_token,created_at) VALUES (?,?,?,?,?,?,?,?)`,
		d.ID, d.UserID, d.Name, d.Platform, d.IdentityKey, d.TokenHash, d.FCMToken, fmtTime(d.CreatedAt))
	if isUniqueErr(err) {
		return fmt.Errorf("store: device %s exists: %w", d.ID, ErrConflict)
	}
	if err != nil {
		return fmt.Errorf("store: create device: %w", err)
	}
	return nil
}

const deviceCols = `id, user_id, name, platform, identity_key, token_hash, fcm_token, created_at`

func scanDevice(row scanner) (Device, error) {
	var d Device
	var created string
	var fcm sql.NullString
	if err := row.Scan(&d.ID, &d.UserID, &d.Name, &d.Platform, &d.IdentityKey, &d.TokenHash, &fcm, &created); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return Device{}, ErrNotFound
		}
		return Device{}, fmt.Errorf("store: scan device: %w", err)
	}
	if fcm.Valid {
		v := fcm.String
		d.FCMToken = &v
	}
	t, err := parseTime(created)
	if err != nil {
		return Device{}, err
	}
	d.CreatedAt = t
	return d, nil
}

// GetDevice returns a device by id.
func (s *Store) GetDevice(ctx context.Context, id string) (Device, error) {
	return scanDevice(s.db.QueryRowContext(ctx, `SELECT `+deviceCols+` FROM devices WHERE id = ?`, id))
}

// GetDeviceByTokenHash resolves a bearer token hash to its device.
func (s *Store) GetDeviceByTokenHash(ctx context.Context, hash string) (Device, error) {
	return scanDevice(s.db.QueryRowContext(ctx, `SELECT `+deviceCols+` FROM devices WHERE token_hash = ?`, hash))
}

// SetDevicePushToken sets (or clears, with nil) the FCM token of a device.
func (s *Store) SetDevicePushToken(ctx context.Context, id string, token *string) error {
	res, err := s.db.ExecContext(ctx, `UPDATE devices SET fcm_token = ? WHERE id = ?`, token, id)
	if err != nil {
		return fmt.Errorf("store: set push token: %w", err)
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	return nil
}

// ListDevices returns every device ordered by creation.
func (s *Store) ListDevices(ctx context.Context) ([]Device, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT `+deviceCols+` FROM devices ORDER BY rowid`)
	if err != nil {
		return nil, fmt.Errorf("store: list devices: %w", err)
	}
	defer func() { _ = rows.Close() }()
	var out []Device
	for rows.Next() {
		d, err := scanDevice(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("store: list devices: %w", err)
	}
	return out, nil
}

// DeleteDevice removes a device; pending envelopes and owned blobs cascade.
func (s *Store) DeleteDevice(ctx context.Context, id string) error {
	owned, err := s.listBlobs(ctx, `WHERE owner_device = ?`, id)
	if err != nil {
		return err
	}
	res, err := s.db.ExecContext(ctx, `DELETE FROM devices WHERE id = ?`, id)
	if err != nil {
		return fmt.Errorf("store: delete device: %w", err)
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	for _, b := range owned {
		s.removeBlobFiles(b)
	}
	// The device row's deletion cascaded away its blob_recipients rows too;
	// a blob some other device owns may now be fully delivered.
	if _, err := s.DeleteDeliveredBlobs(ctx); err != nil {
		return err
	}
	return nil
}
