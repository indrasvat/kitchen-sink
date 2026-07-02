package cmd

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/indrasvat/sarasa/internal/config"
	"github.com/indrasvat/sarasa/internal/manager"
)

type fakeRunManager struct {
	name        string
	upgrade     *manager.UpgradeResult
	upgradeFunc func(context.Context, bool) (*manager.UpgradeResult, error)
	upgradeErr  error
	cleanupErr  error
	available   bool
	skipList    []string
	mu          sync.Mutex
}

func (f *fakeRunManager) Name() string { return f.name }

func (f *fakeRunManager) IsAvailable() bool { return f.available }

func (f *fakeRunManager) CheckOutdated(context.Context) ([]manager.Package, error) {
	return nil, nil
}

func (f *fakeRunManager) Upgrade(ctx context.Context, dryRun bool) (*manager.UpgradeResult, error) {
	if f.upgradeFunc != nil {
		return f.upgradeFunc(ctx, dryRun)
	}
	if f.upgradeErr != nil {
		return nil, f.upgradeErr
	}
	return f.upgrade, nil
}

func (f *fakeRunManager) Cleanup(context.Context) error { return f.cleanupErr }

func (f *fakeRunManager) SetSkipList(packages []string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.skipList = append([]string(nil), packages...)
}

func TestRunJSONDryRunUsesWouldUpgrade(t *testing.T) {
	name := "test-run-json-dry"
	manager.Register(name, func(*manager.Options) manager.Manager {
		return &fakeRunManager{
			name:      name,
			available: true,
			upgrade: &manager.UpgradeResult{
				Skipped: []manager.Package{{
					Name:    "demo",
					Current: "1.0.0",
					Latest:  "1.1.0",
				}},
			},
		}
	})

	cfg := config.DefaultConfig()
	var out bytes.Buffer
	err := runRunJSON(
		[]string{name},
		&manager.Options{DryRun: true, Config: cfg},
		&configWrapper{cfg: cfg},
		&out,
	)
	if err != nil {
		t.Fatalf("runRunJSON() error = %v", err)
	}

	var got RunOutput
	if err := json.Unmarshal(out.Bytes(), &got); err != nil {
		t.Fatalf("invalid JSON output: %v\n%s", err, out.String())
	}
	if !got.DryRun || !got.Success {
		t.Fatalf("unexpected envelope: %+v", got)
	}
	if got.Summary.WouldUpgrade != 1 {
		t.Fatalf("Summary.WouldUpgrade = %d, want 1", got.Summary.WouldUpgrade)
	}
	if len(got.Managers) != 1 || len(got.Managers[0].WouldUpgrade) != 1 {
		t.Fatalf("missing would_upgrade package: %+v", got.Managers)
	}
	if len(got.Managers[0].Skipped) != 0 {
		t.Fatalf("dry-run JSON should expose skipped as would_upgrade, got %+v", got.Managers[0].Skipped)
	}
}

func TestRunJSONReportsManagerFailures(t *testing.T) {
	name := "test-run-json-failure"
	manager.Register(name, func(*manager.Options) manager.Manager {
		return &fakeRunManager{
			name:       name,
			available:  true,
			upgradeErr: errors.New("upgrade failed"),
		}
	})

	cfg := config.DefaultConfig()
	var out bytes.Buffer
	err := runRunJSON(
		[]string{name},
		&manager.Options{Config: cfg},
		&configWrapper{cfg: cfg},
		&out,
	)
	if err == nil {
		t.Fatal("runRunJSON() error = nil, want failure")
	}

	var got RunOutput
	if err := json.Unmarshal(out.Bytes(), &got); err != nil {
		t.Fatalf("invalid JSON output: %v\n%s", err, out.String())
	}
	if got.Success {
		t.Fatalf("Success = true, want false: %+v", got)
	}
	if got.Summary.ManagerErrors != 1 {
		t.Fatalf("ManagerErrors = %d, want 1", got.Summary.ManagerErrors)
	}
	if len(got.Managers) != 1 || got.Managers[0].Error != "upgrade failed" {
		t.Fatalf("missing manager error: %+v", got.Managers)
	}
}

func TestRunJSONRunsManagersConcurrentlyWithStableOrder(t *testing.T) {
	firstStarted := make(chan struct{})
	releaseFirst := make(chan struct{})

	first := "test-run-json-concurrent-first"
	second := "test-run-json-concurrent-second"
	manager.Register(first, func(*manager.Options) manager.Manager {
		return &fakeRunManager{
			name:      first,
			available: true,
			upgradeFunc: func(context.Context, bool) (*manager.UpgradeResult, error) {
				close(firstStarted)
				<-releaseFirst
				return &manager.UpgradeResult{
					Upgraded: []manager.Package{{Name: "first-pkg"}},
				}, nil
			},
		}
	})
	manager.Register(second, func(*manager.Options) manager.Manager {
		return &fakeRunManager{
			name:      second,
			available: true,
			upgradeFunc: func(context.Context, bool) (*manager.UpgradeResult, error) {
				select {
				case <-firstStarted:
				case <-time.After(time.Second):
					t.Fatal("second manager did not overlap first manager")
				}
				close(releaseFirst)
				return &manager.UpgradeResult{
					Upgraded: []manager.Package{{Name: "second-pkg"}},
				}, nil
			},
		}
	})

	cfg := config.DefaultConfig()
	var out bytes.Buffer
	err := runRunJSON(
		[]string{first, second},
		&manager.Options{Config: cfg},
		&configWrapper{cfg: cfg},
		&out,
	)
	if err != nil {
		t.Fatalf("runRunJSON() error = %v", err)
	}

	var got RunOutput
	if err := json.Unmarshal(out.Bytes(), &got); err != nil {
		t.Fatalf("invalid JSON output: %v\n%s", err, out.String())
	}
	if len(got.Managers) != 2 {
		t.Fatalf("got %d managers, want 2", len(got.Managers))
	}
	if got.Managers[0].Name != first || got.Managers[1].Name != second {
		t.Fatalf("manager order = [%s %s], want [%s %s]", got.Managers[0].Name, got.Managers[1].Name, first, second)
	}
}

func TestRunJSONPreservesOrderWithUnavailableManager(t *testing.T) {
	first := "test-run-json-order-first"
	missing := "test-run-json-order-missing"
	second := "test-run-json-order-second"
	manager.Register(first, func(*manager.Options) manager.Manager {
		return &fakeRunManager{
			name:      first,
			available: true,
			upgrade: &manager.UpgradeResult{
				Upgraded: []manager.Package{{Name: "first-pkg"}},
			},
		}
	})
	manager.Register(missing, func(*manager.Options) manager.Manager {
		return &fakeRunManager{name: missing}
	})
	manager.Register(second, func(*manager.Options) manager.Manager {
		return &fakeRunManager{
			name:      second,
			available: true,
			upgrade: &manager.UpgradeResult{
				Upgraded: []manager.Package{{Name: "second-pkg"}},
			},
		}
	})

	cfg := config.DefaultConfig()
	var out bytes.Buffer
	err := runRunJSON(
		[]string{first, missing, second},
		&manager.Options{Config: cfg},
		&configWrapper{cfg: cfg},
		&out,
	)
	if err != nil {
		t.Fatalf("runRunJSON() error = %v", err)
	}

	var got RunOutput
	if err := json.Unmarshal(out.Bytes(), &got); err != nil {
		t.Fatalf("invalid JSON output: %v\n%s", err, out.String())
	}
	if len(got.Managers) != 3 {
		t.Fatalf("got %d managers, want 3", len(got.Managers))
	}
	for i, want := range []string{first, missing, second} {
		if got.Managers[i].Name != want {
			t.Fatalf("manager[%d] = %q, want %q; output=%+v", i, got.Managers[i].Name, want, got.Managers)
		}
	}
	if got.Managers[1].Available {
		t.Fatalf("middle manager should be unavailable: %+v", got.Managers[1])
	}
}

func TestRunPlainNonDryRunShowsSkippedSummary(t *testing.T) {
	oldDryRun := runDryRun
	oldSkipCleanup := runSkipCleanup
	runDryRun = false
	runSkipCleanup = true
	t.Cleanup(func() {
		runDryRun = oldDryRun
		runSkipCleanup = oldSkipCleanup
	})

	mgr := &fakeRunManager{
		name:      "brew",
		available: true,
		upgrade: &manager.UpgradeResult{
			Skipped: []manager.Package{{
				Name:       "demo-cask",
				Current:    "1.0.0",
				Latest:     "1.1.0",
				Method:     "cask",
				SkipReason: "requires manual cask app cleanup or admin lease",
			}},
		},
	}
	cfg := config.DefaultConfig()

	readPipe, writePipe, err := os.Pipe()
	if err != nil {
		t.Fatalf("pipe: %v", err)
	}
	oldStdout := os.Stdout
	os.Stdout = writePipe
	t.Cleanup(func() { os.Stdout = oldStdout })

	err = runRunPlain([]manager.Manager{mgr}, &configWrapper{cfg: cfg}, false)
	_ = writePipe.Close()
	outputBytes, readErr := io.ReadAll(readPipe)
	if err != nil {
		t.Fatalf("runRunPlain failed: %v", err)
	}
	if readErr != nil {
		t.Fatalf("read stdout: %v", readErr)
	}

	output := string(outputBytes)
	for _, want := range []string{"demo-cask", "skipped", "requires manual cask app cleanup or admin lease", "1 skipped"} {
		if !strings.Contains(output, want) {
			t.Fatalf("output missing %q:\n%s", want, output)
		}
	}
	if strings.Contains(output, "All up to date") {
		t.Fatalf("skipped-only run should not report all up to date:\n%s", output)
	}
}

func TestRunPlainRunsManagersConcurrentlyWithStableOutputOrder(t *testing.T) {
	oldDryRun := runDryRun
	oldSkipCleanup := runSkipCleanup
	runDryRun = false
	runSkipCleanup = true
	t.Cleanup(func() {
		runDryRun = oldDryRun
		runSkipCleanup = oldSkipCleanup
	})

	firstStarted := make(chan struct{})
	releaseFirst := make(chan struct{})
	first := &fakeRunManager{
		name:      "brew",
		available: true,
		upgradeFunc: func(context.Context, bool) (*manager.UpgradeResult, error) {
			close(firstStarted)
			<-releaseFirst
			return &manager.UpgradeResult{
				Upgraded: []manager.Package{{Name: "first-pkg", Current: "1.0.0", Latest: "1.1.0"}},
			}, nil
		},
	}
	second := &fakeRunManager{
		name:      "custom",
		available: true,
		upgradeFunc: func(context.Context, bool) (*manager.UpgradeResult, error) {
			select {
			case <-firstStarted:
			case <-time.After(time.Second):
				t.Fatal("second manager did not overlap first manager")
			}
			close(releaseFirst)
			return &manager.UpgradeResult{
				Upgraded: []manager.Package{{Name: "second-pkg", Current: "1.0.0", Latest: "1.1.0"}},
			}, nil
		},
	}

	cfg := config.DefaultConfig()
	readPipe, writePipe, err := os.Pipe()
	if err != nil {
		t.Fatalf("pipe: %v", err)
	}
	oldStdout := os.Stdout
	os.Stdout = writePipe
	t.Cleanup(func() { os.Stdout = oldStdout })

	err = runRunPlain([]manager.Manager{first, second}, &configWrapper{cfg: cfg}, false)
	_ = writePipe.Close()
	outputBytes, readErr := io.ReadAll(readPipe)
	if err != nil {
		t.Fatalf("runRunPlain failed: %v", err)
	}
	if readErr != nil {
		t.Fatalf("read stdout: %v", readErr)
	}

	output := string(outputBytes)
	firstIndex := strings.Index(output, "BREW")
	secondIndex := strings.Index(output, "CUSTOM")
	if firstIndex == -1 || secondIndex == -1 {
		t.Fatalf("missing manager headers:\n%s", output)
	}
	if firstIndex > secondIndex {
		t.Fatalf("plain output order is not input order:\n%s", output)
	}
}

func TestRunCommandHasJSONFlag(t *testing.T) {
	if runCmd.Flags().Lookup("json") == nil {
		t.Fatal("run command missing --json flag")
	}
}
