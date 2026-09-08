package api

import (
	"errors"
	"net/http"
	"strings"

	"github.com/felipemaion/piriquito/server/internal/store"
)

const (
	maxNameLen     = 100
	maxPlatformLen = 32
	maxFCMTokenLen = 4096
)

func (s *Server) register(w http.ResponseWriter, r *http.Request) error {
	var req RegisterRequest
	if err := decodeJSON(w, r, maxJSONBody, &req); err != nil {
		return err
	}
	req.DeviceName = strings.TrimSpace(req.DeviceName)
	req.Platform = strings.TrimSpace(req.Platform)
	switch {
	case req.InviteCode == "":
		return errorf(http.StatusBadRequest, CodeValidation, "invite_code is required")
	case req.DeviceName == "" || len(req.DeviceName) > maxNameLen:
		return errorf(http.StatusBadRequest, CodeValidation, "device_name must be 1-100 chars")
	case req.Platform == "" || len(req.Platform) > maxPlatformLen:
		return errorf(http.StatusBadRequest, CodeValidation, "platform is required")
	}
	if err := ValidateIdentityKey(req.IdentityKey); err != nil {
		return err
	}
	ctx := r.Context()
	now := s.now()
	inv, err := s.store.RedeemInvite(ctx, req.InviteCode, now)
	if err != nil {
		return err
	}
	u, err := s.store.GetUser(ctx, inv.UserID)
	if err != nil {
		return err
	}
	token := store.NewToken()
	d := store.Device{
		ID: store.NewID("dev_"), UserID: u.ID, Name: req.DeviceName, Platform: req.Platform,
		IdentityKey: req.IdentityKey, TokenHash: store.HashToken(token), CreatedAt: now,
	}
	if err := s.store.CreateDevice(ctx, d); err != nil {
		return err
	}
	s.log.Info("device registered", "device", d.ID, "user", u.ID, "platform", d.Platform)
	writeJSON(w, http.StatusCreated, RegisterResponse{Device: deviceDTO(d, true), User: userDTO(u), Token: token})
	return nil
}

func (s *Server) me(w http.ResponseWriter, r *http.Request) error {
	d, _ := DeviceFrom(r.Context())
	u, _ := UserFrom(r.Context())
	writeJSON(w, http.StatusOK, MeResponse{User: userDTO(u), Device: deviceDTO(d, true)})
	return nil
}

func (s *Server) setPush(w http.ResponseWriter, r *http.Request) error {
	var req PushRequest
	if err := decodeJSON(w, r, maxJSONBody, &req); err != nil {
		return err
	}
	if req.FCMToken != nil && (*req.FCMToken == "" || len(*req.FCMToken) > maxFCMTokenLen) {
		return errorf(http.StatusBadRequest, CodeValidation, "fcm_token must be null or 1-4096 chars")
	}
	d, _ := DeviceFrom(r.Context())
	if err := s.store.SetDevicePushToken(r.Context(), d.ID, req.FCMToken); err != nil {
		return err
	}
	w.WriteHeader(http.StatusNoContent)
	return nil
}

func (s *Server) deleteDevice(w http.ResponseWriter, r *http.Request) error {
	ctx := r.Context()
	caller, _ := UserFrom(ctx)
	target, err := s.store.GetDevice(ctx, r.PathValue("id"))
	if err != nil {
		return err
	}
	if target.UserID != caller.ID && caller.Role != store.RoleAdmin {
		return errorf(http.StatusForbidden, CodeForbidden, "not your device")
	}
	if err := s.store.DeleteDevice(ctx, target.ID); err != nil && !errors.Is(err, store.ErrNotFound) {
		return err
	}
	if dc, ok := s.notifier.(Disconnecter); ok {
		dc.Disconnect(target.ID)
	}
	s.log.Info("device deleted", "device", target.ID, "by", caller.ID)
	w.WriteHeader(http.StatusNoContent)
	return nil
}

func (s *Server) directory(w http.ResponseWriter, r *http.Request) error {
	ctx := r.Context()
	users, err := s.store.ListUsers(ctx)
	if err != nil {
		return err
	}
	devices, err := s.store.ListDevices(ctx)
	if err != nil {
		return err
	}
	byUser := map[string][]DeviceDTO{}
	for _, d := range devices {
		byUser[d.UserID] = append(byUser[d.UserID], deviceDTO(d, false))
	}
	out := DirectoryResponse{Users: []DirectoryUser{}}
	for _, u := range users {
		devs := byUser[u.ID]
		if devs == nil {
			devs = []DeviceDTO{}
		}
		out.Users = append(out.Users, DirectoryUser{ID: u.ID, Name: u.Name, Role: u.Role, Devices: devs})
	}
	writeJSON(w, http.StatusOK, out)
	return nil
}
