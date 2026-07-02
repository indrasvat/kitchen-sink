package run

import (
	"context"
	"errors"
	"sync"
	"testing"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/indrasvat/sarasa/internal/manager"
)

func TestCleanupStartsOnlyAfterAllUpgradesFinish(t *testing.T) {
	first := &cleanupSpyManager{name: "first"}
	second := &cleanupSpyManager{name: "second"}

	model := New([]manager.Manager{first, second}, &manager.Options{}, nil, false, false)
	model = startManager(t, model, 0)
	model = startManager(t, model, 1)

	next, cmd := model.Update(managerDoneMsg{index: 0, result: &manager.UpgradeResult{}})
	model = next.(Model)
	if cmd != nil {
		t.Fatal("cleanup started before all upgrades finished")
	}
	if first.cleanupCalls() != 0 || second.cleanupCalls() != 0 {
		t.Fatalf("cleanup calls before all upgrades finished: first=%d second=%d", first.cleanupCalls(), second.cleanupCalls())
	}

	next, cmd = model.Update(managerDoneMsg{index: 1, result: &manager.UpgradeResult{}})
	model = next.(Model)
	if cmd == nil {
		t.Fatal("cleanup command missing after final upgrade")
	}
	if !model.cleaningUp || model.done {
		t.Fatalf("model state before cleanup = cleaningUp:%v done:%v, want cleaningUp:true done:false", model.cleaningUp, model.done)
	}

	msg := runCleanupCommand(t, cmd)
	cleanupMsg, ok := msg.(cleanupDoneMsg)
	if !ok {
		t.Fatalf("cleanup command returned %T, want cleanupDoneMsg", msg)
	}
	if len(cleanupMsg.errors) != 0 {
		t.Fatalf("cleanup errors = %+v, want none", cleanupMsg.errors)
	}
	if first.cleanupCalls() != 1 || second.cleanupCalls() != 1 {
		t.Fatalf("cleanup calls = first:%d second:%d, want 1 each", first.cleanupCalls(), second.cleanupCalls())
	}

	model = updateModel(t, model, cleanupMsg)
	if model.cleaningUp || model.running || !model.done {
		t.Fatalf("model state after cleanup = cleaningUp:%v running:%v done:%v, want false false true", model.cleaningUp, model.running, model.done)
	}
}

func TestCleanupSkipsManagersWithUpgradeErrors(t *testing.T) {
	failed := &cleanupSpyManager{name: "failed"}
	ok := &cleanupSpyManager{name: "ok"}

	model := New([]manager.Manager{failed, ok}, &manager.Options{}, nil, false, false)
	model = startManager(t, model, 0)
	model = startManager(t, model, 1)
	model = updateModel(t, model, managerDoneMsg{index: 0, err: errors.New("upgrade failed")})

	next, cmd := model.Update(managerDoneMsg{index: 1, result: &manager.UpgradeResult{}})
	model = next.(Model)
	if cmd == nil {
		t.Fatal("cleanup command missing after final upgrade")
	}

	msg := runCleanupCommand(t, cmd)
	cleanupMsg, okMsg := msg.(cleanupDoneMsg)
	if !okMsg {
		t.Fatalf("cleanup command returned %T, want cleanupDoneMsg", msg)
	}
	if len(cleanupMsg.errors) != 0 {
		t.Fatalf("cleanup errors = %+v, want none", cleanupMsg.errors)
	}
	if failed.cleanupCalls() != 0 || ok.cleanupCalls() != 1 {
		t.Fatalf("cleanup calls = failed:%d ok:%d, want 0 and 1", failed.cleanupCalls(), ok.cleanupCalls())
	}

	model = updateModel(t, model, cleanupMsg)
	if !model.done {
		t.Fatal("model.done = false, want true")
	}
}

func updateModel(t *testing.T, model Model, msg tea.Msg) Model {
	t.Helper()
	next, cmd := model.Update(msg)
	if cmd != nil {
		t.Fatalf("unexpected command for %T", msg)
	}
	return next.(Model)
}

func startManager(t *testing.T, model Model, index int) Model {
	t.Helper()
	next, cmd := model.Update(managerStartMsg{index: index})
	if cmd == nil {
		t.Fatalf("managerStartMsg[%d] did not return an upgrade command", index)
	}
	return next.(Model)
}

func runCleanupCommand(t *testing.T, cmd tea.Cmd) tea.Msg {
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

type cleanupSpyManager struct {
	name string
	mu   sync.Mutex
	n    int
}

func (m *cleanupSpyManager) Name() string { return m.name }

func (m *cleanupSpyManager) IsAvailable() bool { return true }

func (m *cleanupSpyManager) CheckOutdated(context.Context) ([]manager.Package, error) {
	return nil, nil
}

func (m *cleanupSpyManager) Upgrade(context.Context, bool) (*manager.UpgradeResult, error) {
	return &manager.UpgradeResult{}, nil
}

func (m *cleanupSpyManager) Cleanup(context.Context) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.n++
	return nil
}

func (m *cleanupSpyManager) SetSkipList([]string) {}

func (m *cleanupSpyManager) cleanupCalls() int {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.n
}
