package api

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"

	"github.com/felipemaion/chatito/server/internal/store"
)

// Error codes of the protocol (docs/PROTOCOL.md §3).
const (
	CodeUnauthorized          = "unauthorized"
	CodeForbidden             = "forbidden"
	CodeInvalidInvite         = "invalid_invite"
	CodeValidation            = "validation"
	CodePayloadTooLarge       = "payload_too_large"
	CodeNotFound              = "not_found"
	CodeChunkOutOfRange       = "chunk_out_of_range"
	CodeIncompleteBlob        = "incomplete_blob"
	CodeRateLimited           = "rate_limited"
	CodeInternal              = "internal"
	CodeConflict              = "conflict" // extension: state conflict (e.g. upload after complete)
	maxJSONBody               = 1 << 20    // 1 MiB for ordinary JSON bodies
	maxEnvelopesBody          = 10 << 20   // 100 envelopes × 64 KiB base64 + overhead
	MaxCiphertext             = 64 * 1024
	MaxEnvelopesPerPost       = 100
	ChunkSize                 = 8 * 1024 * 1024
	MaxBlobSize         int64 = 500 * 1024 * 1024
)

// ErrorResponse is the JSON error body.
type ErrorResponse struct {
	Error ErrorBody `json:"error"`
}

// ErrorBody carries a machine code and a human message.
type ErrorBody struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// apiError is an error that knows its HTTP status and protocol code.
type apiError struct {
	status  int
	code    string
	message string
}

func (e *apiError) Error() string { return e.code + ": " + e.message }

func errorf(status int, code, msg string) error {
	return &apiError{status: status, code: code, message: msg}
}

func writeError(w http.ResponseWriter, status int, code, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(ErrorResponse{Error: ErrorBody{Code: code, Message: msg}})
}

// writeErr maps any error to a JSON error response.
func writeErr(w http.ResponseWriter, log *slog.Logger, err error) {
	var ae *apiError
	if errors.As(err, &ae) {
		writeError(w, ae.status, ae.code, ae.message)
		return
	}
	var mbe *http.MaxBytesError
	switch {
	case errors.As(err, &mbe):
		writeError(w, http.StatusRequestEntityTooLarge, CodePayloadTooLarge, "request body too large")
	case errors.Is(err, store.ErrNotFound):
		writeError(w, http.StatusNotFound, CodeNotFound, "not found")
	case errors.Is(err, store.ErrInvalidInvite):
		writeError(w, http.StatusForbidden, CodeInvalidInvite, "invite code expired or already used")
	case errors.Is(err, store.ErrValidation):
		writeError(w, http.StatusBadRequest, CodeValidation, err.Error())
	case errors.Is(err, store.ErrChunkOutOfRange):
		writeError(w, http.StatusBadRequest, CodeChunkOutOfRange, err.Error())
	case errors.Is(err, store.ErrIncomplete):
		writeError(w, http.StatusConflict, CodeIncompleteBlob, err.Error())
	case errors.Is(err, store.ErrConflict):
		writeError(w, http.StatusConflict, CodeConflict, err.Error())
	default:
		log.Error("internal error", "err", err)
		writeError(w, http.StatusInternalServerError, CodeInternal, "internal error")
	}
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
