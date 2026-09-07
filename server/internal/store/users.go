package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

// User is a person in the family directory.
type User struct {
	ID        string
	Name      string
	Role      string
	CreatedAt time.Time
}

// CreateUser inserts a user with a fresh id.
func (s *Store) CreateUser(ctx context.Context, name, role string) (User, error) {
	if !validRole(role) {
		return User{}, fmt.Errorf("store: role %q: %w", role, ErrValidation)
	}
	if name == "" {
		return User{}, fmt.Errorf("store: empty name: %w", ErrValidation)
	}
	u := User{ID: NewID("usr_"), Name: name, Role: role, CreatedAt: time.Now().UTC().Truncate(time.Second)}
	_, err := s.db.ExecContext(ctx, `INSERT INTO users (id,name,role,created_at) VALUES (?,?,?,?)`,
		u.ID, u.Name, u.Role, fmtTime(u.CreatedAt))
	if isUniqueErr(err) {
		return User{}, fmt.Errorf("store: user %q exists: %w", name, ErrConflict)
	}
	if err != nil {
		return User{}, fmt.Errorf("store: create user: %w", err)
	}
	return u, nil
}

const userCols = `id, name, role, created_at`

type scanner interface{ Scan(...any) error }

func scanUser(row scanner) (User, error) {
	var u User
	var created string
	if err := row.Scan(&u.ID, &u.Name, &u.Role, &created); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return User{}, ErrNotFound
		}
		return User{}, fmt.Errorf("store: scan user: %w", err)
	}
	t, err := parseTime(created)
	if err != nil {
		return User{}, err
	}
	u.CreatedAt = t
	return u, nil
}

// GetUser returns a user by id.
func (s *Store) GetUser(ctx context.Context, id string) (User, error) {
	return scanUser(s.db.QueryRowContext(ctx, `SELECT `+userCols+` FROM users WHERE id = ?`, id))
}

// GetUserByName returns a user by exact name.
func (s *Store) GetUserByName(ctx context.Context, name string) (User, error) {
	return scanUser(s.db.QueryRowContext(ctx, `SELECT `+userCols+` FROM users WHERE name = ?`, name))
}

// SetUserRole changes a user's role.
func (s *Store) SetUserRole(ctx context.Context, id, role string) error {
	if !validRole(role) {
		return fmt.Errorf("store: role %q: %w", role, ErrValidation)
	}
	res, err := s.db.ExecContext(ctx, `UPDATE users SET role = ? WHERE id = ?`, role, id)
	if err != nil {
		return fmt.Errorf("store: set role: %w", err)
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	return nil
}

// ListUsers returns all users ordered by creation.
func (s *Store) ListUsers(ctx context.Context) ([]User, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT `+userCols+` FROM users ORDER BY rowid`)
	if err != nil {
		return nil, fmt.Errorf("store: list users: %w", err)
	}
	defer func() { _ = rows.Close() }()
	var out []User
	for rows.Next() {
		u, err := scanUser(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, u)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("store: list users: %w", err)
	}
	return out, nil
}
