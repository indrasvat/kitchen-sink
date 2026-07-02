package fakemanager

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"time"

	"github.com/indrasvat/sarasa/internal/manager"
)

var (
	barrier = newStartBarrier()
	eventMu sync.Mutex
)

// RegisterBuiltins replaces real package managers with deterministic fakes.
func RegisterBuiltins() {
	expected := 3
	if raw := os.Getenv("SARASA_SHUX_EXPECTED_MANAGERS"); raw != "" {
		if parsed, err := strconv.Atoi(raw); err == nil && parsed > 0 {
			expected = parsed
		}
	}
	barrier.expected = expected

	manager.Register(manager.ManagerBrew, func(opts *manager.Options) manager.Manager {
		return &fake{name: manager.ManagerBrew, opts: opts}
	})
	manager.Register(manager.ManagerVolta, func(opts *manager.Options) manager.Manager {
		return &fake{name: manager.ManagerVolta, opts: opts}
	})
	manager.Register(manager.ManagerPipx, func(opts *manager.Options) manager.Manager {
		return &fake{name: manager.ManagerPipx, opts: opts}
	})
}

type fake struct {
	name string
	opts *manager.Options
}

func (f *fake) Name() string { return f.name }

func (f *fake) IsAvailable() bool { return true }

func (f *fake) CheckOutdated(context.Context) ([]manager.Package, error) { return nil, nil }

func (f *fake) Upgrade(ctx context.Context, dryRun bool) (*manager.UpgradeResult, error) {
	if err := barrier.start(ctx, f.name); err != nil {
		return nil, err
	}
	defer barrier.done(f.name)

	switch f.name {
	case manager.ManagerBrew:
		return &manager.UpgradeResult{
			Upgraded: []manager.Package{{
				Name:    "brew-upgraded",
				Current: "1.0.0",
				Latest:  "1.1.0",
				Method:  "formula",
			}},
			Skipped: []manager.Package{{
				Name:       "skip-me",
				Current:    "2.0.0",
				Latest:     "2.1.0",
				Method:     "cask",
				SkipReason: "in skip list",
			}},
		}, nil
	case manager.ManagerVolta:
		return &manager.UpgradeResult{
			Failed: []manager.Package{{
				Name:    "volta-failed",
				Current: "3.0.0",
				Latest:  "3.1.0",
			}},
		}, nil
	default:
		return &manager.UpgradeResult{}, nil
	}
}

func (f *fake) Cleanup(context.Context) error { return nil }

func (f *fake) SetSkipList(packages []string) {
	if f.opts == nil {
		f.opts = &manager.Options{}
	}
	f.opts.SkipList = append([]string(nil), packages...)
}

type startBarrier struct {
	mu       sync.Mutex
	expected int
	started  int
	ready    chan struct{}
}

func newStartBarrier() *startBarrier {
	return &startBarrier{expected: 3, ready: make(chan struct{})}
}

func (b *startBarrier) start(ctx context.Context, name string) error {
	b.mu.Lock()
	b.started++
	_ = writeEvent(name, "start")
	if b.started >= b.expected {
		select {
		case <-b.ready:
		default:
			close(b.ready)
		}
	}
	ready := b.ready
	b.mu.Unlock()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-time.After(10 * time.Second):
		return context.DeadlineExceeded
	case <-ready:
		return nil
	}
}

func (b *startBarrier) done(name string) {
	_ = writeEvent(name, "done")
}

func writeEvent(name, event string) error {
	path := os.Getenv("SARASA_SHUX_EVENTS")
	if path == "" {
		return nil
	}
	eventMu.Lock()
	defer eventMu.Unlock()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	file, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	if err := json.NewEncoder(file).Encode(map[string]string{
		"manager": name,
		"event":   event,
	}); err != nil {
		_ = file.Close()
		return err
	}
	return file.Close()
}
