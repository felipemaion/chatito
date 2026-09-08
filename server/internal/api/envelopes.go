package api

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"net/http"
	"strconv"

	"github.com/felipemaion/piriquito/server/internal/store"
)

const defaultListLimit = 100

func (s *Server) postEnvelopes(w http.ResponseWriter, r *http.Request) error {
	var req EnvelopesPostRequest
	if err := decodeJSON(w, r, maxEnvelopesBody, &req); err != nil {
		return err
	}
	if len(req.Envelopes) == 0 {
		return errorf(http.StatusBadRequest, CodeValidation, "envelopes must not be empty")
	}
	if len(req.Envelopes) > MaxEnvelopesPerPost {
		return errorf(http.StatusBadRequest, CodeValidation, fmt.Sprintf("at most %d envelopes per request", MaxEnvelopesPerPost))
	}
	ctx := r.Context()
	from, _ := DeviceFrom(ctx)
	now := s.now()
	envs := make([]store.Envelope, 0, len(req.Envelopes))
	seen := map[string]bool{}
	for i, in := range req.Envelopes {
		if in.ToDevice == "" {
			return errorf(http.StatusBadRequest, CodeValidation, fmt.Sprintf("envelopes[%d].to_device is required", i))
		}
		if err := ValidateNonce(in.Nonce); err != nil {
			return errorf(http.StatusBadRequest, CodeValidation, fmt.Sprintf("envelopes[%d].nonce must be 24 bytes in base64", i))
		}
		ct, err := base64.StdEncoding.DecodeString(in.Ciphertext)
		if err != nil || len(ct) < 16 {
			return errorf(http.StatusBadRequest, CodeValidation, fmt.Sprintf("envelopes[%d].ciphertext must be base64 of at least 16 bytes", i))
		}
		if len(ct) > MaxCiphertext {
			return errorf(http.StatusRequestEntityTooLarge, CodePayloadTooLarge, fmt.Sprintf("envelopes[%d].ciphertext exceeds 64 KiB", i))
		}
		if !seen[in.ToDevice] {
			if _, err := s.store.GetDevice(ctx, in.ToDevice); err != nil {
				return errorf(http.StatusBadRequest, CodeValidation, fmt.Sprintf("envelopes[%d].to_device %s is unknown", i, in.ToDevice))
			}
			seen[in.ToDevice] = true
		}
		nonce, _ := base64.StdEncoding.DecodeString(in.Nonce)
		envs = append(envs, store.Envelope{
			ID: store.NewID("env_"), FromDevice: from.ID, ToDevice: in.ToDevice,
			Nonce: nonce, Ciphertext: ct, CreatedAt: now,
		})
	}
	if err := s.store.InsertEnvelopes(ctx, envs); err != nil {
		return err
	}
	out := EnvelopesPostResponse{Accepted: make([]AcceptedEnvelope, 0, len(envs))}
	byDevice := map[string][]store.Envelope{}
	for _, e := range envs {
		out.Accepted = append(out.Accepted, AcceptedEnvelope{ID: e.ID, ToDevice: e.ToDevice})
		byDevice[e.ToDevice] = append(byDevice[e.ToDevice], e)
	}
	for deviceID, list := range byDevice {
		s.deliver(ctx, deviceID, list)
	}
	writeJSON(w, http.StatusAccepted, out)
	return nil
}

// deliver notifies live connections and wakes the device via push.
func (s *Server) deliver(ctx context.Context, deviceID string, envs []store.Envelope) {
	if s.notifier != nil {
		s.notifier.Notify(deviceID, envs)
	}
	if s.pusher == nil {
		return
	}
	d, err := s.store.GetDevice(ctx, deviceID)
	if err != nil || d.FCMToken == nil {
		return
	}
	if err := s.pusher.Wake(ctx, *d.FCMToken); err != nil {
		s.log.Warn("push failed", "device", deviceID, "err", err)
		if errors.Is(err, ErrPushUnregistered) {
			if err := s.store.SetDevicePushToken(ctx, deviceID, nil); err != nil {
				s.log.Warn("clear push token failed", "device", deviceID, "err", err)
			}
		}
	}
}

func (s *Server) listEnvelopes(w http.ResponseWriter, r *http.Request) error {
	limit := defaultListLimit
	if q := r.URL.Query().Get("limit"); q != "" {
		n, err := strconv.Atoi(q)
		if err != nil {
			return errorf(http.StatusBadRequest, CodeValidation, "limit must be an integer")
		}
		if n > 0 && n < limit {
			limit = n
		}
	}
	d, _ := DeviceFrom(r.Context())
	envs, err := s.store.ListPendingEnvelopes(r.Context(), d.ID, limit)
	if err != nil {
		return err
	}
	out := EnvelopesListResponse{Envelopes: make([]EnvelopeDTO, 0, len(envs))}
	for _, e := range envs {
		out.Envelopes = append(out.Envelopes, EnvelopeToDTO(e))
	}
	writeJSON(w, http.StatusOK, out)
	return nil
}

func (s *Server) ackEnvelopes(w http.ResponseWriter, r *http.Request) error {
	var req AckRequest
	if err := decodeJSON(w, r, maxJSONBody, &req); err != nil {
		return err
	}
	d, _ := DeviceFrom(r.Context())
	if err := s.store.AckEnvelopes(r.Context(), d.ID, req.IDs); err != nil {
		return err
	}
	w.WriteHeader(http.StatusNoContent)
	return nil
}
