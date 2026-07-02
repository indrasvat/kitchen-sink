package runlock

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
)

var ErrAlreadyRunning = errors.New("another sarasa run is already in progress")

// Lock is an acquired process-level Sarasa run lock.
type Lock struct {
	file *os.File
}

// Acquire obtains the default non-blocking run lock.
func Acquire() (*Lock, error) {
	return AcquireAt(defaultPath())
}

// AcquireAt obtains a non-blocking run lock at path.
func AcquireAt(path string) (*Lock, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, fmt.Errorf("create lock directory: %w", err)
	}
	file, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return nil, fmt.Errorf("open run lock: %w", err)
	}
	if err := lockFile(file); err != nil {
		_ = file.Close()
		return nil, err
	}
	return &Lock{file: file}, nil
}

// Close releases the run lock.
func (l *Lock) Close() error {
	if l == nil || l.file == nil {
		return nil
	}
	err := unlockFile(l.file)
	closeErr := l.file.Close()
	l.file = nil
	if err != nil {
		return err
	}
	return closeErr
}

func defaultPath() string {
	if xdg := os.Getenv("XDG_CACHE_HOME"); xdg != "" {
		return filepath.Join(xdg, "sarasa", "run.lock")
	}
	homeDir, _ := os.UserHomeDir()
	return filepath.Join(homeDir, "Library", "Caches", "sarasa", "run.lock")
}
