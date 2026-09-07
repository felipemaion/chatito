// Package janitor runs the periodic expiration of envelopes, blobs and invites.
package janitor

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"sync/atomic"
	"time"

	"github.com/felipemaion/chatito/server/internal/api"
	"github.com/felipemaion/chatito/server/internal/store"
)

const defaultInterval = time.Hour

// Options tunes the janitor.
type Options struct {
	Interval time.Duration    // default 1h
	Now      func() time.Time // default time.Now
	Logger   *slog.Logger
}

// Stats counts what one sweep removed.
type Stats struct {
	Envelopes int64
	Blobs     int
	Invites   int64
}

// Janitor sweeps expired data from the store.
type Janitor struct {
	store    *store.Store
	interval time.Duration
	now      func() time.Time
	log      *slog.Logger
	runs     atomic.Int64
}

// New creates a janitor for st.
func New(st *store.Store, opts Options) *Janitor {
	j := &Janitor{store: st, interval: opts.Interval, now: opts.Now, log: opts.Logger}
	if j.interval <= 0 {
		j.interval = defaultInterval
	}
	if j.now == nil {
		j.now = time.Now
	}
	if j.log == nil {
		j.log = slog.Default()
	}
	return j
}

// Runs returns how many sweeps have executed.
func (j *Janitor) Runs() int64 { return j.runs.Load() }

// RunOnce performs a single sweep. It keeps going after individual failures
// and returns the combined error.
func (j *Janitor) RunOnce(ctx context.Context) (Stats, error) {
	defer j.runs.Add(1)
	now := j.now()
	var st Stats
	var errs []error
	n, err := j.store.ExpireEnvelopes(ctx, now.Add(-api.EnvelopeTTL))
	if err != nil {
		errs = append(errs, err)
	}
	st.Envelopes = n
	b, err := j.store.ExpireBlobs(ctx, now)
	if err != nil {
		errs = append(errs, err)
	}
	st.Blobs = b
	b, err = j.store.DeleteDeliveredBlobs(ctx)
	if err != nil {
		errs = append(errs, err)
	}
	st.Blobs += b
	i, err := j.store.ExpireInvites(ctx, now)
	if err != nil {
		errs = append(errs, err)
	}
	st.Invites = i
	if len(errs) > 0 {
		return st, fmt.Errorf("janitor: %w", errors.Join(errs...))
	}
	return st, nil
}

// Run sweeps immediately and then every interval until ctx is cancelled.
func (j *Janitor) Run(ctx context.Context) {
	ticker := time.NewTicker(j.interval)
	defer ticker.Stop()
	for {
		st, err := j.RunOnce(ctx)
		if err != nil {
			j.log.Error("janitor sweep failed", "err", err)
		} else if st.Envelopes+int64(st.Blobs)+st.Invites > 0 {
			j.log.Info("janitor sweep", "envelopes", st.Envelopes, "blobs", st.Blobs, "invites", st.Invites)
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}
