// Package ws implements the realtime websocket endpoint (/v1/ws): it pushes
// pending and freshly queued envelopes to connected devices and accepts acks.
package ws

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/coder/websocket"

	"github.com/felipemaion/piriquito/server/internal/api"
	"github.com/felipemaion/piriquito/server/internal/store"
)

// Close codes specific to the protocol (docs/PROTOCOL.md §4).
const (
	CloseUnauthorized websocket.StatusCode = 4401
	CloseReplaced     websocket.StatusCode = 4409

	defaultPingInterval = 30 * time.Second
	maxMissedPongs      = 2
	writeTimeout        = 10 * time.Second
	outboundBuffer      = 256
	flushLimit          = 1000
	maxFrameBytes       = 1 << 20
)

// Options tunes the hub.
type Options struct {
	PingInterval time.Duration // default 30s
	Logger       *slog.Logger
}

// Hub tracks one live connection per device.
type Hub struct {
	store *store.Store
	log   *slog.Logger
	ping  time.Duration

	mu     sync.Mutex
	conns  map[string]*conn
	closed bool
}

// NewHub creates a hub backed by st.
func NewHub(st *store.Store, opts Options) *Hub {
	h := &Hub{store: st, log: opts.Logger, ping: opts.PingInterval, conns: map[string]*conn{}}
	if h.log == nil {
		h.log = slog.Default()
	}
	if h.ping <= 0 {
		h.ping = defaultPingInterval
	}
	return h
}

// conn is one websocket connection with a serialised outbound queue.
type conn struct {
	deviceID string
	ws       *websocket.Conn
	out      chan []byte
	pong     chan struct{}
	done     chan struct{}
	once     sync.Once
	code     websocket.StatusCode
	reason   string

	sentMu sync.Mutex
	sent   map[string]struct{}
}

// markSent reports whether envelope id is being sent for the first time on
// this connection. It guards against the race between the initial pending
// flush (a direct DB read) and a concurrent Notify call for the same
// just-inserted envelope, which could otherwise deliver it twice.
func (c *conn) markSent(id string) bool {
	c.sentMu.Lock()
	defer c.sentMu.Unlock()
	if c.sent == nil {
		c.sent = map[string]struct{}{}
	}
	if _, dup := c.sent[id]; dup {
		return false
	}
	c.sent[id] = struct{}{}
	return true
}

// closeWith records the close code and ends the connection once.
func (c *conn) closeWith(code websocket.StatusCode, reason string) {
	c.once.Do(func() {
		c.code, c.reason = code, reason
		close(c.done)
	})
}

// Connected reports whether deviceID has a live connection.
func (h *Hub) Connected(deviceID string) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	_, ok := h.conns[deviceID]
	return ok
}

// Notify implements api.Notifier: it queues envelopes on the device's live
// connection, if any. Envelopes are persisted anyway, so a full queue drops.
func (h *Hub) Notify(deviceID string, envs []store.Envelope) {
	h.mu.Lock()
	c := h.conns[deviceID]
	h.mu.Unlock()
	if c == nil {
		return
	}
	for _, e := range envs {
		if !c.markSent(e.ID) {
			continue
		}
		c.enqueue(mustJSON(api.EnvelopeFrame{Type: "envelope", Envelope: api.EnvelopeToDTO(e)}))
	}
}

// Disconnect closes the device's connection with 4401 (e.g. device deleted).
func (h *Hub) Disconnect(deviceID string) {
	h.mu.Lock()
	c := h.conns[deviceID]
	h.mu.Unlock()
	if c == nil {
		return
	}
	c.enqueue(mustJSON(api.ErrorFrame{Type: "error", Error: api.ErrorBody{Code: api.CodeUnauthorized, Message: "device no longer valid"}}))
	c.closeWith(CloseUnauthorized, "unauthorized")
}

// Close disconnects every client (server shutdown).
func (h *Hub) Close() {
	h.mu.Lock()
	h.closed = true
	conns := make([]*conn, 0, len(h.conns))
	for _, c := range h.conns {
		conns = append(conns, c)
	}
	h.mu.Unlock()
	for _, c := range conns {
		c.closeWith(websocket.StatusGoingAway, "server shutdown")
	}
}

func (c *conn) enqueue(frame []byte) {
	select {
	case c.out <- frame:
	case <-c.done:
	default:
	}
}

func mustJSON(v any) []byte {
	b, err := json.Marshal(v)
	if err != nil {
		panic("ws: marshal frame: " + err.Error())
	}
	return b
}

// ServeHTTP upgrades an authenticated request (api middleware) to a websocket.
func (h *Hub) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	d, ok := api.DeviceFrom(r.Context())
	if !ok {
		http.Error(w, "unauthorized", http.StatusUnauthorized)
		return
	}
	// Native clients (Flutter desktop/mobile) don't send an Origin header, so
	// the library's default check (reject only a mismatching Origin) is
	// enough; skipping it entirely would also accept forged browser origins.
	wsc, err := websocket.Accept(w, r, nil)
	if err != nil {
		h.log.Warn("ws accept failed", "device", d.ID, "err", err)
		return
	}
	wsc.SetReadLimit(maxFrameBytes)
	c := &conn{deviceID: d.ID, ws: wsc, out: make(chan []byte, outboundBuffer), pong: make(chan struct{}, 1), done: make(chan struct{})}

	h.mu.Lock()
	if h.closed {
		h.mu.Unlock()
		_ = wsc.Close(websocket.StatusGoingAway, "server shutdown")
		return
	}
	if old := h.conns[d.ID]; old != nil {
		old.closeWith(CloseReplaced, "replaced by a new connection")
	}
	h.conns[d.ID] = c
	h.mu.Unlock()
	defer func() {
		h.mu.Lock()
		if h.conns[d.ID] == c {
			delete(h.conns, d.ID)
		}
		h.mu.Unlock()
	}()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	if err := h.sendHelloAndPending(ctx, c); err != nil {
		h.log.Warn("ws initial flush failed", "device", d.ID, "err", err)
		_ = wsc.Close(websocket.StatusInternalError, "flush failed")
		return
	}
	h.log.Info("ws connected", "device", d.ID)
	go h.readLoop(ctx, c)
	h.writeLoop(ctx, c)
	h.log.Info("ws disconnected", "device", d.ID, "code", int(c.code), "reason", c.reason)
}

func (h *Hub) sendHelloAndPending(ctx context.Context, c *conn) error {
	pending, err := h.store.ListPendingEnvelopes(ctx, c.deviceID, flushLimit)
	if err != nil {
		return err
	}
	if err := c.write(ctx, mustJSON(api.HelloFrame{Type: "hello", DeviceID: c.deviceID, Pending: len(pending)})); err != nil {
		return err
	}
	for _, e := range pending {
		if !c.markSent(e.ID) {
			continue
		}
		if err := c.write(ctx, mustJSON(api.EnvelopeFrame{Type: "envelope", Envelope: api.EnvelopeToDTO(e)})); err != nil {
			return err
		}
	}
	return nil
}

func (c *conn) write(ctx context.Context, frame []byte) error {
	wctx, cancel := context.WithTimeout(ctx, writeTimeout)
	defer cancel()
	return c.ws.Write(wctx, websocket.MessageText, frame)
}

// writeLoop serialises outbound frames, drives server pings and performs the
// final close. It returns when the connection is done.
func (h *Hub) writeLoop(ctx context.Context, c *conn) {
	ticker := time.NewTicker(h.ping)
	defer ticker.Stop()
	missed := 0
	for {
		select {
		case <-c.done:
			_ = c.ws.Close(c.code, c.reason)
			return
		case frame := <-c.out:
			if err := c.write(ctx, frame); err != nil {
				c.closeWith(websocket.StatusAbnormalClosure, "write failed")
			}
		case <-c.pong:
			missed = 0
		case <-ticker.C:
			missed++
			if missed >= maxMissedPongs {
				c.closeWith(websocket.StatusGoingAway, "pong timeout")
				continue
			}
			if err := c.write(ctx, mustJSON(api.Frame{Type: "ping"})); err != nil {
				c.closeWith(websocket.StatusAbnormalClosure, "write failed")
			}
		}
	}
}

// readLoop handles client frames until the connection ends.
func (h *Hub) readLoop(ctx context.Context, c *conn) {
	for {
		_, data, err := c.ws.Read(ctx)
		if err != nil {
			code := websocket.CloseStatus(err)
			if code == -1 {
				code = websocket.StatusAbnormalClosure
			}
			c.closeWith(code, "client closed")
			return
		}
		var f api.Frame
		if err := json.Unmarshal(data, &f); err != nil {
			c.enqueue(mustJSON(api.ErrorFrame{Type: "error", Error: api.ErrorBody{Code: api.CodeValidation, Message: "malformed frame"}}))
			c.closeWith(websocket.StatusUnsupportedData, "malformed frame")
			return
		}
		switch f.Type {
		case "ack":
			var ack api.AckFrame
			if err := json.Unmarshal(data, &ack); err == nil {
				if err := h.store.AckEnvelopes(ctx, c.deviceID, ack.IDs); err != nil && !errors.Is(err, context.Canceled) {
					h.log.Warn("ws ack failed", "device", c.deviceID, "err", err)
				}
			}
		case "pong":
			select {
			case c.pong <- struct{}{}:
			default:
			}
		case "ping":
			c.enqueue(mustJSON(api.Frame{Type: "pong"}))
		default:
			// Unknown frame types are ignored for forward compatibility.
		}
	}
}
