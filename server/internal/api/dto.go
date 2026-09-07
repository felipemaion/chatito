package api

import (
	"time"

	"github.com/felipemaion/chatito/server/internal/store"
)

// timeStr formats a time as RFC 3339 UTC with second precision.
func timeStr(t time.Time) string { return t.UTC().Truncate(time.Second).Format(time.RFC3339) }

// UserDTO is a user as exposed by the API.
type UserDTO struct {
	ID   string `json:"id"`
	Name string `json:"name"`
	Role string `json:"role"`
}

func userDTO(u store.User) UserDTO { return UserDTO{ID: u.ID, Name: u.Name, Role: u.Role} }

// DeviceDTO is a device as exposed by the API (never includes the token).
type DeviceDTO struct {
	ID          string `json:"id"`
	UserID      string `json:"user_id,omitempty"`
	Name        string `json:"name"`
	Platform    string `json:"platform"`
	IdentityKey string `json:"identity_key"`
	CreatedAt   string `json:"created_at"`
}

func deviceDTO(d store.Device, withUser bool) DeviceDTO {
	out := DeviceDTO{ID: d.ID, Name: d.Name, Platform: d.Platform, IdentityKey: d.IdentityKey, CreatedAt: timeStr(d.CreatedAt)}
	if withUser {
		out.UserID = d.UserID
	}
	return out
}

// RegisterRequest is the body of POST /v1/devices.
type RegisterRequest struct {
	InviteCode  string `json:"invite_code"`
	DeviceName  string `json:"device_name"`
	Platform    string `json:"platform"`
	IdentityKey string `json:"identity_key"`
}

// RegisterResponse is the body returned by POST /v1/devices.
type RegisterResponse struct {
	Device DeviceDTO `json:"device"`
	User   UserDTO   `json:"user"`
	Token  string    `json:"token"`
}

// MeResponse is the body of GET /v1/me.
type MeResponse struct {
	User   UserDTO   `json:"user"`
	Device DeviceDTO `json:"device"`
}

// PushRequest is the body of PUT /v1/devices/me/push.
type PushRequest struct {
	FCMToken *string `json:"fcm_token"`
}

// DirectoryUser is a user with its devices.
type DirectoryUser struct {
	ID      string      `json:"id"`
	Name    string      `json:"name"`
	Role    string      `json:"role"`
	Devices []DeviceDTO `json:"devices"`
}

// DirectoryResponse is the body of GET /v1/directory.
type DirectoryResponse struct {
	Users []DirectoryUser `json:"users"`
}

// EnvelopeIn is one envelope submitted by a client.
type EnvelopeIn struct {
	ToDevice   string `json:"to_device"`
	Nonce      string `json:"nonce"`
	Ciphertext string `json:"ciphertext"`
}

// EnvelopesPostRequest is the body of POST /v1/envelopes.
type EnvelopesPostRequest struct {
	Envelopes []EnvelopeIn `json:"envelopes"`
}

// AcceptedEnvelope echoes the id assigned to a submitted envelope.
type AcceptedEnvelope struct {
	ID       string `json:"id"`
	ToDevice string `json:"to_device"`
}

// EnvelopesPostResponse is the body returned by POST /v1/envelopes.
type EnvelopesPostResponse struct {
	Accepted []AcceptedEnvelope `json:"accepted"`
}

// EnvelopeDTO is an envelope as delivered to its recipient.
type EnvelopeDTO struct {
	ID         string `json:"id"`
	FromDevice string `json:"from_device"`
	ToDevice   string `json:"to_device"`
	Nonce      string `json:"nonce"`
	Ciphertext string `json:"ciphertext"`
	CreatedAt  string `json:"created_at"`
}

// EnvelopeToDTO converts a stored envelope to its wire form.
func EnvelopeToDTO(e store.Envelope) EnvelopeDTO {
	return EnvelopeDTO{
		ID: e.ID, FromDevice: e.FromDevice, ToDevice: e.ToDevice,
		Nonce: b64enc(e.Nonce), Ciphertext: b64enc(e.Ciphertext), CreatedAt: timeStr(e.CreatedAt),
	}
}

// EnvelopesListResponse is the body of GET /v1/envelopes.
type EnvelopesListResponse struct {
	Envelopes []EnvelopeDTO `json:"envelopes"`
}

// AckRequest is the body of POST /v1/envelopes/ack.
type AckRequest struct {
	IDs []string `json:"ids"`
}

// BlobCreateRequest is the body of POST /v1/blobs.
type BlobCreateRequest struct {
	Size       int64    `json:"size"`
	Recipients []string `json:"recipients"`
}

// BlobCreateResponse is the body returned by POST /v1/blobs.
type BlobCreateResponse struct {
	BlobID    string `json:"blob_id"`
	ChunkSize int64  `json:"chunk_size"`
	ExpiresAt string `json:"expires_at"`
}

// BlobCompleteResponse is the body returned by POST /v1/blobs/{id}/complete.
type BlobCompleteResponse struct {
	BlobID string `json:"blob_id"`
	Size   int64  `json:"size"`
}

// InviteRequest is the body of POST /v1/admin/invites.
type InviteRequest struct {
	UserName string `json:"user_name"`
	UserID   string `json:"user_id"`
}

// InviteResponse is the body returned by POST /v1/admin/invites.
type InviteResponse struct {
	Code      string `json:"code"`
	UserID    string `json:"user_id"`
	ExpiresAt string `json:"expires_at"`
}

// RoleRequest is the body of POST /v1/admin/users/{id}/role.
type RoleRequest struct {
	Role string `json:"role"`
}

// WebSocket frames (docs/PROTOCOL.md §4).

// Frame is the minimal frame used to sniff the type.
type Frame struct {
	Type string `json:"type"`
}

// HelloFrame is sent by the server right after the connection is accepted.
type HelloFrame struct {
	Type     string `json:"type"`
	DeviceID string `json:"device_id"`
	Pending  int    `json:"pending"`
}

// EnvelopeFrame pushes one envelope to the client.
type EnvelopeFrame struct {
	Type     string      `json:"type"`
	Envelope EnvelopeDTO `json:"envelope"`
}

// AckFrame is sent by the client to delete delivered envelopes.
type AckFrame struct {
	Type string   `json:"type"`
	IDs  []string `json:"ids"`
}

// ErrorFrame is sent by the server before closing on a fatal error.
type ErrorFrame struct {
	Type  string    `json:"type"`
	Error ErrorBody `json:"error"`
}
