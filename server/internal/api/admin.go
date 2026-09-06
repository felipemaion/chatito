package api

import (
	"context"
	"errors"
	"net/http"
	"strings"

	"github.com/felipemaion/chatito/server/internal/store"
)

// IssueInvite creates (if needed) the target user and issues an invite for it.
// Exactly one of userName / userID must be given. Shared by the HTTP handler
// and the admin CLI.
func (s *Server) IssueInvite(ctx context.Context, userName, userID string) (store.Invite, error) {
	var u store.User
	var err error
	switch {
	case userID != "":
		u, err = s.store.GetUser(ctx, userID)
	case userName != "":
		u, err = s.store.GetUserByName(ctx, userName)
		if errors.Is(err, store.ErrNotFound) {
			u, err = s.store.CreateUser(ctx, userName, store.RoleMember)
		}
	default:
		return store.Invite{}, errorf(http.StatusBadRequest, CodeValidation, "user_name or user_id is required")
	}
	if err != nil {
		return store.Invite{}, err
	}
	return s.store.CreateInvite(ctx, u.ID, s.now().Add(InviteTTL))
}

func (s *Server) adminInvite(w http.ResponseWriter, r *http.Request) error {
	if err := requireAdmin(r); err != nil {
		return err
	}
	var req InviteRequest
	if err := decodeJSON(w, r, maxJSONBody, &req); err != nil {
		return err
	}
	req.UserName = strings.TrimSpace(req.UserName)
	if len(req.UserName) > maxNameLen {
		return errorf(http.StatusBadRequest, CodeValidation, "user_name too long")
	}
	inv, err := s.IssueInvite(r.Context(), req.UserName, req.UserID)
	if err != nil {
		return err
	}
	admin, _ := UserFrom(r.Context())
	s.log.Info("invite issued", "for_user", inv.UserID, "by", admin.ID)
	writeJSON(w, http.StatusCreated, InviteResponse{Code: inv.Code, UserID: inv.UserID, ExpiresAt: timeStr(inv.ExpiresAt)})
	return nil
}

func (s *Server) adminSetRole(w http.ResponseWriter, r *http.Request) error {
	if err := requireAdmin(r); err != nil {
		return err
	}
	var req RoleRequest
	if err := decodeJSON(w, r, maxJSONBody, &req); err != nil {
		return err
	}
	if err := s.store.SetUserRole(r.Context(), r.PathValue("id"), req.Role); err != nil {
		return err
	}
	w.WriteHeader(http.StatusNoContent)
	return nil
}
