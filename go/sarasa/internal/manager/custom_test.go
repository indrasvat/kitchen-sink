package manager

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/indrasvat/sarasa/internal/config"
)

func TestCustomCheckOutdatedValueLatest(t *testing.T) {
	cfg := config.DefaultConfig()
	cfg.Custom.Tools = []config.CustomToolConfig{
		{
			Name: "demo-tool",
			Current: config.CustomProbeConfig{
				Argv:  []string{"sh", "-c", "printf 'demo-tool v1.0.0'"},
				Regex: `v?[0-9]+\.[0-9]+\.[0-9]+`,
			},
			Latest: config.CustomLatestConfig{
				Value: "v1.2.0",
			},
			Upgrade: config.CustomActionConfig{
				Shell: "printf upgraded",
			},
		},
	}

	m := NewCustom(&Options{Config: cfg})
	got, err := m.CheckOutdated(context.Background())
	if err != nil {
		t.Fatalf("CheckOutdated failed: %v", err)
	}
	if len(got) != 1 {
		t.Fatalf("expected 1 outdated package, got %d", len(got))
	}
	if got[0].Name != "demo-tool" {
		t.Errorf("Name = %q, want demo-tool", got[0].Name)
	}
	if got[0].Current != "v1.0.0" {
		t.Errorf("Current = %q, want v1.0.0", got[0].Current)
	}
	if got[0].Latest != "v1.2.0" {
		t.Errorf("Latest = %q, want v1.2.0", got[0].Latest)
	}
	if got[0].Method != "pinned / shell" {
		t.Errorf("Method = %q, want pinned / shell", got[0].Method)
	}
}

func TestCustomUpgradeRunsAndVerifies(t *testing.T) {
	tmpDir := t.TempDir()
	versionFile := filepath.Join(tmpDir, "version.txt")
	if err := os.WriteFile(versionFile, []byte("1.0.0"), 0644); err != nil {
		t.Fatalf("write version file: %v", err)
	}

	cfg := config.DefaultConfig()
	cfg.Custom.StateDir = filepath.Join(tmpDir, "state")
	cfg.Custom.Tools = []config.CustomToolConfig{
		{
			Name: "file-tool",
			Current: config.CustomProbeConfig{
				Argv: []string{"cat", versionFile},
			},
			Latest: config.CustomLatestConfig{
				Value: "1.1.0",
			},
			Upgrade: config.CustomActionConfig{
				Argv: []string{"sh", "-c", "printf '1.1.0' > " + versionFile},
			},
			Verify: config.CustomProbeConfig{
				Argv: []string{"cat", versionFile},
			},
		},
	}

	result, err := NewCustom(&Options{Config: cfg}).Upgrade(context.Background(), false)
	if err != nil {
		t.Fatalf("Upgrade failed: %v", err)
	}
	if len(result.Upgraded) != 1 {
		t.Fatalf("expected 1 upgraded package, got %d", len(result.Upgraded))
	}
	data, err := os.ReadFile(versionFile)
	if err != nil {
		t.Fatalf("read version file: %v", err)
	}
	if string(data) != "1.1.0" {
		t.Errorf("version file = %q, want 1.1.0", data)
	}
	if _, err := os.Stat(filepath.Join(cfg.Custom.StateDir, "file-tool.json")); err != nil {
		t.Errorf("expected state file to be written: %v", err)
	}
}

func TestCustomUpgradeDryRunDoesNotRunAction(t *testing.T) {
	tmpDir := t.TempDir()
	versionFile := filepath.Join(tmpDir, "version.txt")
	if err := os.WriteFile(versionFile, []byte("1.0.0"), 0644); err != nil {
		t.Fatalf("write version file: %v", err)
	}

	cfg := config.DefaultConfig()
	cfg.Custom.Tools = []config.CustomToolConfig{
		{
			Name:    "dry-run-tool",
			Current: config.CustomProbeConfig{Argv: []string{"cat", versionFile}},
			Latest:  config.CustomLatestConfig{Value: "1.1.0"},
			Upgrade: config.CustomActionConfig{Argv: []string{"sh", "-c", "printf '1.1.0' > " + versionFile}},
		},
	}

	result, err := NewCustom(&Options{Config: cfg}).Upgrade(context.Background(), true)
	if err != nil {
		t.Fatalf("Upgrade dry-run failed: %v", err)
	}
	if len(result.Skipped) != 1 {
		t.Fatalf("expected 1 skipped package, got %d", len(result.Skipped))
	}
	data, err := os.ReadFile(versionFile)
	if err != nil {
		t.Fatalf("read version file: %v", err)
	}
	if string(data) != "1.0.0" {
		t.Errorf("dry-run changed version file to %q", data)
	}
}

func TestCustomCleanupRespectsSkipListAndAvailability(t *testing.T) {
	tmpDir := t.TempDir()
	skippedFile := filepath.Join(tmpDir, "skipped.txt")
	missingFile := filepath.Join(tmpDir, "missing.txt")
	activeFile := filepath.Join(tmpDir, "active.txt")

	cfg := config.DefaultConfig()
	cfg.Custom.Tools = []config.CustomToolConfig{
		{
			Name: "skipped-tool",
			Cleanup: config.CustomActionConfig{
				Argv: []string{"sh", "-c", "printf skipped > \"$1\"", "sarasa-test", skippedFile},
			},
		},
		{
			Name:   "missing-tool",
			Binary: "__sarasa_missing_binary__",
			Cleanup: config.CustomActionConfig{
				Argv: []string{"sh", "-c", "printf missing > \"$1\"", "sarasa-test", missingFile},
			},
		},
		{
			Name: "active-tool",
			Cleanup: config.CustomActionConfig{
				Argv: []string{"sh", "-c", "printf active > \"$1\"", "sarasa-test", activeFile},
			},
		},
	}

	opts := &Options{
		Config:   cfg,
		SkipList: []string{"skipped-tool"},
	}
	if err := NewCustom(opts).Cleanup(context.Background()); err != nil {
		t.Fatalf("Cleanup failed: %v", err)
	}

	if _, err := os.Stat(skippedFile); !os.IsNotExist(err) {
		t.Fatalf("skipped cleanup ran, stat error: %v", err)
	}
	if _, err := os.Stat(missingFile); !os.IsNotExist(err) {
		t.Fatalf("unavailable cleanup ran, stat error: %v", err)
	}
	if data, err := os.ReadFile(activeFile); err != nil {
		t.Fatalf("active cleanup did not run: %v", err)
	} else if string(data) != "active" {
		t.Fatalf("active cleanup wrote %q, want active", data)
	}
}

func TestVersionGreater(t *testing.T) {
	tests := []struct {
		latest  string
		current string
		want    bool
	}{
		{"v1.2.0", "v1.1.9", true},
		{"1.2.0", "1.2.0", false},
		{"1.2.0", "1.3.0", false},
		{"2026.05.15", "2025.12.31", true},
		{"new", "old", true},
	}

	for _, tt := range tests {
		t.Run(tt.latest+"_vs_"+tt.current, func(t *testing.T) {
			if got := versionGreater(tt.latest, tt.current); got != tt.want {
				t.Errorf("versionGreater(%q, %q) = %v, want %v", tt.latest, tt.current, got, tt.want)
			}
		})
	}
}
