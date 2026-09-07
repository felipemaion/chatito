package ws

import "testing"

// TestConnMarkSentDedup guards the fix for the race between the initial
// pending flush and a concurrent Notify for the same envelope: whichever
// path calls markSent first must win, the other must be skipped.
func TestConnMarkSentDedup(t *testing.T) {
	c := &conn{}
	if !c.markSent("env_1") {
		t.Fatal("first mark of env_1 should send")
	}
	if c.markSent("env_1") {
		t.Fatal("second mark of env_1 must not send again")
	}
	if !c.markSent("env_2") {
		t.Fatal("a different id should still send")
	}
}
