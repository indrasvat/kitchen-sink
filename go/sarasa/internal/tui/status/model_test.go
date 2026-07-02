package status

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/indrasvat/sarasa/internal/manager"
)

func TestStatusCleanupStartsOnlyAfterAllUpgradesFinish(t *testing.T) {
	first := "test-status-cleanup-first"
	second := "test-status-cleanup-second"
	firstSpy := registerCleanupSpy(t, first)
	secondSpy := registerCleanupSpy(t, second)

	model := newUpgradeModel(first, second)
	model = updateStatusModel(t, model, upgradeManagerDoneMsg{name: first, result: &manager.UpgradeResult{}})
	if firstSpy.cleanupCalls() != 0 || secondSpy.cleanupCalls() != 0 {
		t.Fatalf("cleanup calls before all upgrades finished: first=%d second=%d", firstSpy.cleanupCalls(), secondSpy.cleanupCalls())
	}

	next, cmd := model.Update(upgradeManagerDoneMsg{name: second, result: &manager.UpgradeResult{}})
	model = next.(Model)
	if cmd == nil {
		t.Fatal("cleanup command missing after final upgrade")
	}
	if model.state != stateCleaningUp {
		t.Fatalf("state = %v, want stateCleaningUp", model.state)
	}

	msg := runStatusCleanupCommand(t, cmd)
	cleanupMsg, ok := msg.(cleanupDoneMsg)
	if !ok {
		t.Fatalf("cleanup command returned %T, want cleanupDoneMsg", msg)
	}
	if len(cleanupMsg.errors) != 0 {
		t.Fatalf("cleanup errors = %+v, want none", cleanupMsg.errors)
	}
	if firstSpy.cleanupCalls() != 1 || secondSpy.cleanupCalls() != 1 {
		t.Fatalf("cleanup calls = first:%d second:%d, want 1 each", firstSpy.cleanupCalls(), secondSpy.cleanupCalls())
	}

	model = updateStatusModel(t, model, cleanupMsg)
	if model.state != stateUpgraded {
		t.Fatalf("state = %v, want stateUpgraded", model.state)
	}
}

func TestStatusCleanupSkipsManagersWithUpgradeErrors(t *testing.T) {
	failed := "test-status-cleanup-failed"
	ok := "test-status-cleanup-ok"
	failedSpy := registerCleanupSpy(t, failed)
	okSpy := registerCleanupSpy(t, ok)

	model := newUpgradeModel(failed, ok)
	model = updateStatusModel(t, model, upgradeManagerDoneMsg{name: failed, err: errors.New("upgrade failed")})

	next, cmd := model.Update(upgradeManagerDoneMsg{name: ok, result: &manager.UpgradeResult{}})
	model = next.(Model)
	if cmd == nil {
		t.Fatal("cleanup command missing after final upgrade")
	}
	msg := runStatusCleanupCommand(t, cmd)
	cleanupMsg, okMsg := msg.(cleanupDoneMsg)
	if !okMsg {
		t.Fatalf("cleanup command returned %T, want cleanupDoneMsg", msg)
	}
	if len(cleanupMsg.errors) != 0 {
		t.Fatalf("cleanup errors = %+v, want none", cleanupMsg.errors)
	}
	if failedSpy.cleanupCalls() != 0 || okSpy.cleanupCalls() != 1 {
		t.Fatalf("cleanup calls = failed:%d ok:%d, want 0 and 1", failedSpy.cleanupCalls(), okSpy.cleanupCalls())
	}

	model = updateStatusModel(t, model, cleanupMsg)
	if model.state != stateUpgraded {
		t.Fatalf("state = %v, want stateUpgraded", model.state)
	}
}

func newUpgradeModel(names ...string) Model {
	model := New(names, &manager.Options{}, nil)
	model.state = stateUpgrading
	model.startTime = time.Now()
	model.upgradeResults = make(map[string]*upgradeResult, len(names))
	model.upgradeOrder = append([]string(nil), names...)
	model.activeCount = len(names)
	for _, name := range names {
		model.upgradeResults[name] = &upgradeResult{Name: name, Status: "upgrading"}
	}
	return model
}

func updateStatusModel(t *testing.T, model Model, msg tea.Msg) Model {
	t.Helper()
	next, cmd := model.Update(msg)
	if cmd != nil {
		t.Fatalf("unexpected command for %T", msg)
	}
	return next.(Model)
}

func registerCleanupSpy(t *testing.T, name string) *statusCleanupSpy {
	t.Helper()
	spy := &statusCleanupSpy{name: name}
	manager.Register(name, func(*manager.Options) manager.Manager { return spy })
	return spy
}

func runStatusCleanupCommand(t *testing.T, cmd tea.Cmd) tea.Msg {
	t.Helper()
	msg := cmd()
	batch, ok := msg.(tea.BatchMsg)
	if !ok {
		return msg
	}
	for _, batched := range batch {
		if batched == nil {
			continue
		}
		msg := batched()
		if _, ok := msg.(cleanupDoneMsg); ok {
			return msg
		}
	}
	t.Fatal("cleanup command not found in batch")
	return nil
}

type statusCleanupSpy struct {
	name string
	mu   sync.Mutex
	n    int
}

func (m *statusCleanupSpy) Name() string { return m.name }

func (m *statusCleanupSpy) IsAvailable() bool { return true }

func (m *statusCleanupSpy) CheckOutdated(context.Context) ([]manager.Package, error) {
	return nil, nil
}

func (m *statusCleanupSpy) Upgrade(context.Context, bool) (*manager.UpgradeResult, error) {
	return &manager.UpgradeResult{}, nil
}

func (m *statusCleanupSpy) Cleanup(context.Context) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.n++
	return nil
}

func (m *statusCleanupSpy) SetSkipList([]string) {}

func (m *statusCleanupSpy) cleanupCalls() int {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.n
}
