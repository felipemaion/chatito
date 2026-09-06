// Package store persists relay state in SQLite (modernc, no CGO) and blob
// chunks on the filesystem. It knows nothing about HTTP.
package store

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/base64"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	_ "modernc.org/sqlite" // sqlite driver
)

// Sentinel errors returned by the store.
var (
	ErrNotFound      = errors.New("not found")
	ErrConflict      = errors.New("conflict")
	ErrValidation    = errors.New("validation")
	ErrInvalidInvite = errors.New("invalid invite")
)

// Roles of a user.
const (
	RoleAdmin  = "admin"
	RoleMember = "member"
)

// Store wraps the SQLite database and the blob directory.
type Store struct {
	db      *sql.DB
	blobDir string
}

// Open opens (or creates) the database at dataDir/relay.db and the blob
// directory at dataDir/blobs, applying migrations.
func Open(dataDir string) (*Store, error) {
	blobDir := filepath.Join(dataDir, "blobs")
	if err := os.MkdirAll(blobDir, 0o750); err != nil {
		return nil, fmt.Errorf("store: create data dir: %w", err)
	}
	dsn := "file:" + filepath.Join(dataDir, "relay.db") +
		"?_pragma=journal_mode(WAL)&_pragma=busy_timeout(5000)&_pragma=foreign_keys(1)&_pragma=synchronous(NORMAL)"
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("store: open db: %w", err)
	}
	s := &Store{db: db, blobDir: blobDir}
	if err := s.migrate(context.Background()); err != nil {
		_ = db.Close()
		return nil, err
	}
	return s, nil
}

// Close closes the database.
func (s *Store) Close() error {
	if err := s.db.Close(); err != nil {
		return fmt.Errorf("store: close: %w", err)
	}
	return nil
}

// BlobDir returns the directory where blob data lives.
func (s *Store) BlobDir() string { return s.blobDir }

func (s *Store) migrate(ctx context.Context) error {
	if _, err := s.db.ExecContext(ctx, schema); err != nil {
		return fmt.Errorf("store: migrate: %w", err)
	}
	return nil
}

// NewID returns prefix + 22 base64url chars (128 random bits).
func NewID(prefix string) string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic("store: crypto/rand failed: " + err.Error())
	}
	return prefix + base64.RawURLEncoding.EncodeToString(b[:])
}

// NewToken returns a 32-byte random bearer token in base64url (no padding).
func NewToken() string {
	var b [32]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic("store: crypto/rand failed: " + err.Error())
	}
	return base64.RawURLEncoding.EncodeToString(b[:])
}

const crockford = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

// newInviteCode returns XXXX-XXXX in Crockford base32.
func newInviteCode() string {
	var b [8]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic("store: crypto/rand failed: " + err.Error())
	}
	var sb strings.Builder
	for i, c := range b {
		if i == 4 {
			sb.WriteByte('-')
		}
		sb.WriteByte(crockford[int(c)%32])
	}
	return sb.String()
}

// NormalizeInviteCode uppercases, strips dashes/spaces and maps Crockford
// look-alikes (O→0, I/L→1) so that user-typed codes match.
func NormalizeInviteCode(code string) string {
	code = strings.ToUpper(strings.NewReplacer("-", "", " ", "").Replace(code))
	code = strings.NewReplacer("O", "0", "I", "1", "L", "1").Replace(code)
	if len(code) != 8 {
		return code
	}
	return code[:4] + "-" + code[4:]
}

func fmtTime(t time.Time) string { return t.UTC().Format(time.RFC3339Nano) }

func parseTime(s string) (time.Time, error) {
	t, err := time.Parse(time.RFC3339Nano, s)
	if err != nil {
		return time.Time{}, fmt.Errorf("store: parse time %q: %w", s, err)
	}
	return t.UTC(), nil
}

func validRole(r string) bool { return r == RoleAdmin || r == RoleMember }

func isUniqueErr(err error) bool {
	return err != nil && strings.Contains(err.Error(), "UNIQUE constraint failed")
}
