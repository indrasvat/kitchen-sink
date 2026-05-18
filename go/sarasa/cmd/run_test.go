package cmd

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"testing"

	"github.com/indrasvat/sarasa/internal/config"
	"github.com/indrasvat/sarasa/internal/manager"
)

type fakeRunManager struct {
	name       string
	upgrade    *manager.UpgradeResult
	upgradeErr error
	cleanupErr error
	available  bool
	skipList   []string
}

func (f *fakeRunManager) Name() string { return f.name }

func (f *fakeRunManager) IsAvailable() bool { return f.available }

func (f *fakeRunManager) CheckOutdated(context.Context) ([]manager.Package, error) {
	return nil, nil
}

func (f *fakeRunManager) Upgrade(context.Context, bool) (*manager.UpgradeResult, error) {
	if f.upgradeErr != nil {
		return nil, f.upgradeErr
	}
	return f.upgrade, nil
}

func (f *fakeRunManager) Cleanup(context.Context) error { return f.cleanupErr }

func (f *fakeRunManager) SetSkipList(packages []string) { f.skipList = packages }

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

func TestRunCommandHasJSONFlag(t *testing.T) {
	if runCmd.Flags().Lookup("json") == nil {
		t.Fatal("run command missing --json flag")
	}
}
