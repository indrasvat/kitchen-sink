package runlock

import (
	"errors"
	"path/filepath"
	"testing"
)

func TestAcquireAtFailsFastWhenAlreadyLocked(t *testing.T) {
	path := filepath.Join(t.TempDir(), "run.lock")
	first, err := AcquireAt(path)
	if err != nil {
		t.Fatalf("first AcquireAt failed: %v", err)
	}
	t.Cleanup(func() { _ = first.Close() })

	second, err := AcquireAt(path)
	if err == nil {
		_ = second.Close()
		t.Fatal("second AcquireAt succeeded, want ErrAlreadyRunning")
	}
	if !errors.Is(err, ErrAlreadyRunning) {
		t.Fatalf("second AcquireAt error = %v, want ErrAlreadyRunning", err)
	}
}

func TestAcquireAtReleasesOnClose(t *testing.T) {
	path := filepath.Join(t.TempDir(), "run.lock")
	first, err := AcquireAt(path)
	if err != nil {
		t.Fatalf("first AcquireAt failed: %v", err)
	}
	if err := first.Close(); err != nil {
		t.Fatalf("Close failed: %v", err)
	}

	second, err := AcquireAt(path)
	if err != nil {
		t.Fatalf("second AcquireAt failed after close: %v", err)
	}
	t.Cleanup(func() { _ = second.Close() })
}
