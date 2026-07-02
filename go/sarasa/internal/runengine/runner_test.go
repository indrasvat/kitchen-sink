package runengine

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/indrasvat/sarasa/internal/manager"
)

func TestRunnerRunsManagersConcurrentlyAndReturnsInputOrder(t *testing.T) {
	firstStarted := make(chan struct{})
	releaseFirst := make(chan struct{})

	slow := &fakeManager{
		name: "slow",
		upgrade: func(context.Context, bool) (*manager.UpgradeResult, error) {
			close(firstStarted)
			<-releaseFirst
			return &manager.UpgradeResult{
				Upgraded: []manager.Package{{Name: "slow-pkg"}},
			}, nil
		},
	}
	fast := &fakeManager{
		name: "fast",
		upgrade: func(context.Context, bool) (*manager.UpgradeResult, error) {
			select {
			case <-firstStarted:
			case <-time.After(time.Second):
				t.Fatal("fast manager did not start after slow manager")
			}
			close(releaseFirst)
			return &manager.UpgradeResult{
				Upgraded: []manager.Package{{Name: "fast-pkg"}},
			}, nil
		},
	}

	output := Runner{}.Run(context.Background(), []manager.Manager{slow, fast})

	if len(output.Managers) != 2 {
		t.Fatalf("got %d manager results, want 2", len(output.Managers))
	}
	if output.Managers[0].Name != "slow" || output.Managers[1].Name != "fast" {
		t.Fatalf("manager order = [%s %s], want [slow fast]", output.Managers[0].Name, output.Managers[1].Name)
	}
	if output.Summary.Upgraded != 2 {
		t.Fatalf("Summary.Upgraded = %d, want 2", output.Summary.Upgraded)
	}
}

func TestRunnerIsolatesManagerErrors(t *testing.T) {
	output := Runner{}.Run(context.Background(), []manager.Manager{
		&fakeManager{name: "bad", err: errors.New("boom")},
		&fakeManager{name: "good", result: &manager.UpgradeResult{
			Upgraded: []manager.Package{{Name: "ok"}},
		}},
	})

	if output.Success {
		t.Fatal("output.Success = true, want false")
	}
	if output.Summary.ManagerErrors != 1 {
		t.Fatalf("ManagerErrors = %d, want 1", output.Summary.ManagerErrors)
	}
	if output.Summary.Upgraded != 1 {
		t.Fatalf("Upgraded = %d, want 1", output.Summary.Upgraded)
	}
}

func TestRunnerRunsCleanupAfterAllUpgradesFinish(t *testing.T) {
	firstUpgradeStarted := make(chan struct{})
	releaseFirstUpgrade := make(chan struct{})
	firstUpgradeDone := make(chan struct{})

	first := &fakeManager{
		name: "first",
		upgrade: func(context.Context, bool) (*manager.UpgradeResult, error) {
			close(firstUpgradeStarted)
			<-releaseFirstUpgrade
			close(firstUpgradeDone)
			return &manager.UpgradeResult{}, nil
		},
	}
	secondCleanupChecked := make(chan struct{})
	second := &fakeManager{
		name: "second",
		upgrade: func(context.Context, bool) (*manager.UpgradeResult, error) {
			<-firstUpgradeStarted
			return &manager.UpgradeResult{}, nil
		},
		cleanup: func(context.Context) error {
			select {
			case <-firstUpgradeDone:
			default:
				t.Fatal("cleanup started before all upgrades finished")
			}
			close(secondCleanupChecked)
			return nil
		},
	}

	go func() {
		time.Sleep(50 * time.Millisecond)
		close(releaseFirstUpgrade)
	}()
	output := Runner{}.Run(context.Background(), []manager.Manager{first, second})
	if !output.Success {
		t.Fatalf("output.Success = false, want true: %+v", output)
	}
	select {
	case <-secondCleanupChecked:
	case <-time.After(time.Second):
		t.Fatal("second cleanup did not run")
	}
}

type fakeManager struct {
	name    string
	result  *manager.UpgradeResult
	err     error
	upgrade func(context.Context, bool) (*manager.UpgradeResult, error)
	cleanup func(context.Context) error
}

func (f *fakeManager) Name() string { return f.name }

func (f *fakeManager) IsAvailable() bool { return true }

func (f *fakeManager) CheckOutdated(context.Context) ([]manager.Package, error) { return nil, nil }

func (f *fakeManager) Upgrade(ctx context.Context, dryRun bool) (*manager.UpgradeResult, error) {
	if f.upgrade != nil {
		return f.upgrade(ctx, dryRun)
	}
	if f.result != nil || f.err != nil {
		return f.result, f.err
	}
	return &manager.UpgradeResult{}, nil
}

func (f *fakeManager) Cleanup(ctx context.Context) error {
	if f.cleanup != nil {
		return f.cleanup(ctx)
	}
	return nil
}

func (f *fakeManager) SetSkipList([]string) {}
