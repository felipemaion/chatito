package api

import (
	"sync"
	"time"
)

// rateLimiter is a fixed-window (1 minute) counter per key.
type rateLimiter struct {
	mu      sync.Mutex
	limit   func() int
	now     func() time.Time
	windows map[string]*window
}

type window struct {
	start time.Time
	count int
}

func newRateLimiter(limit func() int, now func() time.Time) *rateLimiter {
	return &rateLimiter{limit: limit, now: now, windows: map[string]*window{}}
}

// allow records one request for key. When the limit is exceeded it returns
// (secondsUntilReset, false).
func (l *rateLimiter) allow(key string) (int, bool) {
	limit := l.limit()
	if limit <= 0 {
		return 0, true
	}
	now := l.now()
	l.mu.Lock()
	defer l.mu.Unlock()
	w := l.windows[key]
	if w == nil || now.Sub(w.start) >= time.Minute {
		w = &window{start: now}
		l.windows[key] = w
		if len(l.windows) > 10000 { // bound memory: drop stale windows
			for k, o := range l.windows {
				if now.Sub(o.start) >= time.Minute {
					delete(l.windows, k)
				}
			}
		}
	}
	if w.count >= limit {
		retry := int((time.Minute - now.Sub(w.start)).Seconds()) + 1
		return retry, false
	}
	w.count++
	return 0, true
}
