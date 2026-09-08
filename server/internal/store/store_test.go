package store_test

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/felipemaion/piriquito/server/internal/store"
)

func openTest(t *testing.T) *store.Store {
	t.Helper()
	dir := t.TempDir()
	s, err := store.Open(dir)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	t.Cleanup(func() { _ = s.Close() })
	return s
}

func TestOpenCreatesSchemaAndIsIdempotent(t *testing.T) {
	dir := t.TempDir()
	s, err := store.Open(dir)
	if err != nil {
		t.Fatalf("open: %v", err)
	}
	if err := s.Close(); err != nil {
		t.Fatalf("close: %v", err)
	}
	s2, err := store.Open(dir)
	if err != nil {
		t.Fatalf("reopen: %v", err)
	}
	defer func() { _ = s2.Close() }()
	if s2.BlobDir() != filepath.Join(dir, "blobs") {
		t.Fatalf("blob dir = %q", s2.BlobDir())
	}
}

func TestOpenFailsWhenDataDirIsAFile(t *testing.T) {
	f := filepath.Join(t.TempDir(), "file")
	if err := os.WriteFile(f, []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := store.Open(f); err == nil {
		t.Fatal("expected error when data dir is a file")
	}
}

func TestNormalizeInviteCode(t *testing.T) {
	for in, want := range map[string]string{
		"7k3m-9qzr": "7K3M-9QZR", "7K3M9QZR": "7K3M-9QZR", " 7k3m 9qzr ": "7K3M-9QZR",
		"OI1L-OI1L": "0111-0111", "short": "SH0RT",
	} {
		if got := store.NormalizeInviteCode(in); got != want {
			t.Errorf("normalize(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestNewID(t *testing.T) {
	id := store.NewID("usr_")
	if len(id) != 26 || id[:4] != "usr_" {
		t.Fatalf("id = %q", id)
	}
	a, b := store.NewID("dev_"), store.NewID("dev_")
	if a == b {
		t.Fatal("ids must be unique")
	}
	if tok := store.NewToken(); len(tok) != 43 {
		t.Fatalf("token = %q", tok)
	}
}

func TestUsersCRUD(t *testing.T) {
	s := openTest(t)
	ctx := context.Background()

	u, err := s.CreateUser(ctx, "Felipe", store.RoleAdmin)
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	if u.ID[:4] != "usr_" || u.Name != "Felipe" || u.Role != store.RoleAdmin || u.CreatedAt.IsZero() {
		t.Fatalf("user = %+v", u)
	}
	if _, err := s.CreateUser(ctx, "Felipe", store.RoleMember); !errors.Is(err, store.ErrConflict) {
		t.Fatalf("duplicate name err = %v, want ErrConflict", err)
	}
	if _, err := s.CreateUser(ctx, "X", "god"); !errors.Is(err, store.ErrValidation) {
		t.Fatalf("bad role err = %v, want ErrValidation", err)
	}

	got, err := s.GetUser(ctx, u.ID)
	if err != nil || got.ID != u.ID {
		t.Fatalf("get = %+v, %v", got, err)
	}
	if _, err := s.GetUser(ctx, "usr_missing"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("missing err = %v", err)
	}
	byName, err := s.GetUserByName(ctx, "Felipe")
	if err != nil || byName.ID != u.ID {
		t.Fatalf("by name = %+v, %v", byName, err)
	}
	if _, err := s.GetUserByName(ctx, "Ninguém"); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("by name missing err = %v", err)
	}

	if err := s.SetUserRole(ctx, u.ID, store.RoleMember); err != nil {
		t.Fatalf("set role: %v", err)
	}
	if err := s.SetUserRole(ctx, u.ID, "god"); !errors.Is(err, store.ErrValidation) {
		t.Fatalf("set bad role err = %v", err)
	}
	if err := s.SetUserRole(ctx, "usr_missing", store.RoleAdmin); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("set role missing err = %v", err)
	}
	got, _ = s.GetUser(ctx, u.ID)
	if got.Role != store.RoleMember {
		t.Fatalf("role = %q", got.Role)
	}

	_, _ = s.CreateUser(ctx, "Mãe", store.RoleMember)
	users, err := s.ListUsers(ctx)
	if err != nil || len(users) != 2 {
		t.Fatalf("list = %v, %v", users, err)
	}
	if users[0].Name != "Felipe" || users[1].Name != "Mãe" {
		t.Fatalf("list order = %v", users)
	}
}

func TestInvites(t *testing.T) {
	s := openTest(t)
	ctx := context.Background()
	u, _ := s.CreateUser(ctx, "Felipe", store.RoleAdmin)
	now := time.Date(2026, 9, 6, 18, 0, 0, 0, time.UTC)

	inv, err := s.CreateInvite(ctx, u.ID, now.Add(7*24*time.Hour))
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	if len(inv.Code) != 9 || inv.Code[4] != '-' || inv.UserID != u.ID {
		t.Fatalf("invite = %+v", inv)
	}
	if _, err := s.CreateInvite(ctx, "usr_missing", now); !errors.Is(err, store.ErrNotFound) {
		t.Fatalf("missing user err = %v", err)
	}

	// expired
	if _, err := s.RedeemInvite(ctx, inv.Code, now.Add(8*24*time.Hour)); !errors.Is(err, store.ErrInvalidInvite) {
		t.Fatalf("expired err = %v", err)
	}
	got, err := s.RedeemInvite(ctx, inv.Code, now.Add(time.Hour))
	if err != nil || got.UserID != u.ID {
		t.Fatalf("redeem = %+v, %v", got, err)
	}
	// single use
	if _, err := s.RedeemInvite(ctx, inv.Code, now.Add(time.Hour)); !errors.Is(err, store.ErrInvalidInvite) {
		t.Fatalf("reuse err = %v", err)
	}
	if _, err := s.RedeemInvite(ctx, "ZZZZ-ZZZZ", now); !errors.Is(err, store.ErrInvalidInvite) {
		t.Fatalf("unknown err = %v", err)
	}
	// lowercase / no dash are normalised
	inv2, _ := s.CreateInvite(ctx, u.ID, now.Add(time.Hour))
	loose := string([]byte{inv2.Code[0], inv2.Code[1], inv2.Code[2], inv2.Code[3], inv2.Code[5], inv2.Code[6], inv2.Code[7], inv2.Code[8]})
	if _, err := s.RedeemInvite(ctx, loose, now); err != nil {
		t.Fatalf("redeem without dash: %v", err)
	}

	// expiry job
	_, _ = s.CreateInvite(ctx, u.ID, now.Add(time.Hour))
	old, _ := s.CreateInvite(ctx, u.ID, now.Add(-time.Hour))
	n, err := s.ExpireInvites(ctx, now)
	if err != nil || n != 1 {
		t.Fatalf("expire = %d, %v", n, err)
	}
	if _, err := s.RedeemInvite(ctx, old.Code, now.Add(-2*time.Hour)); !errors.Is(err, store.ErrInvalidInvite) {
		t.Fatalf("expired invite should be gone: %v", err)
	}
}
