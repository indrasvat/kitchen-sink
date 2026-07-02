package manager_test

import (
	"context"
	"slices"
	"testing"

	"github.com/indrasvat/sarasa/internal/manager"
)

func TestOptions_ShouldSkip(t *testing.T) {
	opts := &manager.Options{
		SkipList: []string{"pkg1", "pkg2", "pkg3"},
	}

	tests := []struct {
		pkg      string
		expected bool
	}{
		{"pkg1", true},
		{"pkg2", true},
		{"pkg3", true},
		{"pkg4", false},
		{"", false},
		{"PKG1", false}, // case sensitive
	}

	for _, tt := range tests {
		t.Run(tt.pkg, func(t *testing.T) {
			got := opts.ShouldSkip(tt.pkg)
			if got != tt.expected {
				t.Errorf("ShouldSkip(%q) = %v, want %v", tt.pkg, got, tt.expected)
			}
		})
	}
}

func TestOptions_ShouldSkip_EmptyList(t *testing.T) {
	opts := &manager.Options{
		SkipList: []string{},
	}

	if opts.ShouldSkip("anything") {
		t.Error("ShouldSkip should return false with empty list")
	}
}

func TestOptions_ShouldSkip_NilList(t *testing.T) {
	opts := &manager.Options{
		SkipList: nil,
	}

	if opts.ShouldSkip("anything") {
		t.Error("ShouldSkip should return false with nil list")
	}
}

func TestGetMultipleClonesOptionsPerManager(t *testing.T) {
	nameA := "test-options-clone-a"
	nameB := "test-options-clone-b"

	manager.Register(nameA, func(opts *manager.Options) manager.Manager {
		return &optionInspectManager{name: nameA, opts: opts}
	})
	manager.Register(nameB, func(opts *manager.Options) manager.Manager {
		return &optionInspectManager{name: nameB, opts: opts}
	})

	managers, err := manager.GetMultiple([]string{nameA, nameB}, &manager.Options{
		SkipList: []string{"base"},
	})
	if err != nil {
		t.Fatalf("GetMultiple failed: %v", err)
	}
	if len(managers) != 2 {
		t.Fatalf("got %d managers, want 2", len(managers))
	}

	first := managers[0].(*optionInspectManager)
	second := managers[1].(*optionInspectManager)
	if first.opts == second.opts {
		t.Fatal("managers share the same *Options pointer")
	}

	first.SetSkipList([]string{"first-only"})
	if second.opts.ShouldSkip("first-only") {
		t.Fatal("SetSkipList on first manager leaked into second manager")
	}
	if !second.opts.ShouldSkip("base") {
		t.Fatal("cloned options did not preserve original skip list")
	}
}

func TestManagerListOrderIsDeterministic(t *testing.T) {
	names := manager.List()
	if !slices.IsSorted(names) {
		t.Fatalf("manager.List() is not sorted: %v", names)
	}
}

type optionInspectManager struct {
	name string
	opts *manager.Options
}

func (m *optionInspectManager) Name() string { return m.name }

func (m *optionInspectManager) IsAvailable() bool { return true }

func (m *optionInspectManager) CheckOutdated(context.Context) ([]manager.Package, error) {
	return nil, nil
}

func (m *optionInspectManager) Upgrade(context.Context, bool) (*manager.UpgradeResult, error) {
	return &manager.UpgradeResult{}, nil
}

func (m *optionInspectManager) Cleanup(context.Context) error { return nil }

func (m *optionInspectManager) SetSkipList(packages []string) { m.opts.SkipList = packages }
