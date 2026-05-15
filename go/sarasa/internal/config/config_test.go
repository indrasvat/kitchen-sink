package config_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/indrasvat/sarasa/internal/config"
)

func TestDefaultConfig(t *testing.T) {
	cfg := config.DefaultConfig()

	// Check default managers
	expectedManagers := []string{"brew", "volta", "pipx", "bun", "skills"}
	if len(cfg.Managers) != len(expectedManagers) {
		t.Errorf("expected %d managers, got %d", len(expectedManagers), len(cfg.Managers))
	}
	for i, m := range expectedManagers {
		if cfg.Managers[i] != m {
			t.Errorf("expected manager[%d]=%s, got %s", i, m, cfg.Managers[i])
		}
	}

	// Check default schedule times (every 2 hours)
	expectedTimes := []string{
		"00:00", "02:00", "04:00", "06:00",
		"08:00", "10:00", "12:00", "14:00",
		"16:00", "18:00", "20:00", "22:00",
	}
	if len(cfg.Schedule.Times) != len(expectedTimes) {
		t.Errorf("expected %d schedule times, got %d", len(expectedTimes), len(cfg.Schedule.Times))
	}

	// Check logging defaults
	if cfg.Logging.RetentionDays != 30 {
		t.Errorf("expected RetentionDays=30, got %d", cfg.Logging.RetentionDays)
	}
	if cfg.Logging.Level != "info" {
		t.Errorf("expected Level=info, got %s", cfg.Logging.Level)
	}

	// Check manager-specific defaults
	if cfg.Brew.Greedy {
		t.Error("expected Brew.Greedy=false")
	}
	if cfg.NPM.SkipMajor {
		t.Error("expected NPM.SkipMajor=false")
	}
	if cfg.Volta.SkipMajor {
		t.Error("expected Volta.SkipMajor=false")
	}
	if cfg.Custom.DefaultTimeout != "10m" {
		t.Errorf("expected Custom.DefaultTimeout=10m, got %s", cfg.Custom.DefaultTimeout)
	}
	if cfg.Custom.StateDir == "" {
		t.Error("expected Custom.StateDir to be set")
	}
}

func TestIsManagerEnabled(t *testing.T) {
	cfg := config.DefaultConfig()

	// Check enabled managers
	for _, m := range []string{"brew", "volta", "pipx", "bun", "skills"} {
		if !cfg.IsManagerEnabled(m) {
			t.Errorf("expected %s to be enabled", m)
		}
	}

	// Check disabled managers
	if cfg.IsManagerEnabled("npm") {
		t.Error("expected npm to be disabled in default config")
	}

	// Check unknown manager
	if cfg.IsManagerEnabled("unknown") {
		t.Error("expected unknown to be disabled")
	}
}

func TestIsManagerEnabled_EmptyList(t *testing.T) {
	cfg := config.DefaultConfig()
	cfg.Managers = []string{}

	// When list is empty, all managers should be enabled
	for _, m := range []string{"brew", "npm", "volta", "pipx", "bun", "anything"} {
		if !cfg.IsManagerEnabled(m) {
			t.Errorf("expected %s to be enabled when managers list is empty", m)
		}
	}
}

func TestGetSkipList(t *testing.T) {
	cfg := config.DefaultConfig()
	cfg.Skip.Brew = []string{"pkg1", "pkg2"}
	cfg.Skip.NPM = []string{"npm-pkg"}
	cfg.Skip.Volta = []string{"volta-pkg"}
	cfg.Skip.Pipx = []string{"pipx-pkg"}
	cfg.Skip.Bun = []string{"bun-pkg"}
	cfg.Skip.Skills = []string{"skills-pkg"}
	cfg.Skip.Custom = []string{"custom-pkg"}

	tests := []struct {
		manager  string
		expected []string
	}{
		{"brew", []string{"pkg1", "pkg2"}},
		{"npm", []string{"npm-pkg"}},
		{"volta", []string{"volta-pkg"}},
		{"pipx", []string{"pipx-pkg"}},
		{"bun", []string{"bun-pkg"}},
		{"skills", []string{"skills-pkg"}},
		{"custom", []string{"custom-pkg"}},
		{"unknown", nil},
	}

	for _, tt := range tests {
		t.Run(tt.manager, func(t *testing.T) {
			got := cfg.GetSkipList(tt.manager)
			if len(got) != len(tt.expected) {
				t.Errorf("expected %d items, got %d", len(tt.expected), len(got))
				return
			}
			for i, v := range tt.expected {
				if got[i] != v {
					t.Errorf("expected item[%d]=%s, got %s", i, v, got[i])
				}
			}
		})
	}
}

func TestLoadFrom_CustomTools(t *testing.T) {
	tmpDir := t.TempDir()
	configPath := filepath.Join(tmpDir, "config.toml")

	configContent := `
managers = ["custom"]

[skip]
custom = ["skip-me"]

[custom]
state_dir = "~/Library/Application Support/sarasa/custom-state"
default_timeout = "30s"

[[custom.tools]]
name = "demo"
binary = "demo"
timeout = "1m"
allow_unchanged = true
current = { argv = ["demo", "--version"], regex = "v?[0-9]+\\.[0-9]+\\.[0-9]+" }
latest = { github_release = "indrasvat/demo" }
outdated = { mode = "always" }
upgrade = { shell = "curl -fsSL https://example.invalid/install.sh | VERSION=${latest} sh" }
verify = { argv = ["demo", "--version"], regex = "v?[0-9]+\\.[0-9]+\\.[0-9]+" }
`

	if err := os.WriteFile(configPath, []byte(configContent), 0644); err != nil {
		t.Fatalf("failed to write config: %v", err)
	}

	cfg, err := config.LoadFrom(configPath)
	if err != nil {
		t.Fatalf("failed to load config: %v", err)
	}

	if len(cfg.Custom.Tools) != 1 {
		t.Fatalf("expected 1 custom tool, got %d", len(cfg.Custom.Tools))
	}
	tool := cfg.Custom.Tools[0]
	if tool.Name != "demo" {
		t.Errorf("tool.Name = %q, want demo", tool.Name)
	}
	if !tool.AllowUnchanged {
		t.Error("expected allow_unchanged=true")
	}
	if tool.Latest.GitHubRelease != "indrasvat/demo" {
		t.Errorf("github_release = %q", tool.Latest.GitHubRelease)
	}
	if tool.Outdated.Mode != "always" {
		t.Errorf("outdated mode = %q", tool.Outdated.Mode)
	}
	if cfg.Custom.StateDir == "" || cfg.Custom.StateDir[0] == '~' {
		t.Errorf("expected expanded custom state dir, got %q", cfg.Custom.StateDir)
	}
	if !cfg.ShouldSkip("custom", "skip-me") {
		t.Error("expected custom skip list to apply")
	}
}

func TestShouldSkip(t *testing.T) {
	cfg := config.DefaultConfig()
	cfg.Skip.Brew = []string{"skip-this", "skip-that"}

	if !cfg.ShouldSkip("brew", "skip-this") {
		t.Error("expected skip-this to be skipped")
	}
	if !cfg.ShouldSkip("brew", "skip-that") {
		t.Error("expected skip-that to be skipped")
	}
	if cfg.ShouldSkip("brew", "keep-this") {
		t.Error("expected keep-this to not be skipped")
	}
	if cfg.ShouldSkip("npm", "skip-this") {
		t.Error("expected skip-this to not be skipped for npm")
	}
}

func TestLoadFrom_NotFound(t *testing.T) {
	cfg, err := config.LoadFrom("/nonexistent/path/config.toml")
	if err != nil {
		t.Errorf("expected no error for missing config, got %v", err)
	}
	if cfg == nil {
		t.Error("expected default config, got nil")
	}
}

func TestLoadFrom_ValidConfig(t *testing.T) {
	// Create temp config file
	tmpDir := t.TempDir()
	configPath := filepath.Join(tmpDir, "config.toml")

	configContent := `
managers = ["brew", "npm"]

[skip]
brew = ["skip1", "skip2"]

[schedule]
times = ["09:00", "17:00"]

[logging]
retention_days = 7
level = "debug"

[brew]
greedy = true

[npm]
skip_major = true
`

	if err := os.WriteFile(configPath, []byte(configContent), 0644); err != nil {
		t.Fatalf("failed to write config: %v", err)
	}

	cfg, err := config.LoadFrom(configPath)
	if err != nil {
		t.Fatalf("failed to load config: %v", err)
	}

	// Verify loaded values
	if len(cfg.Managers) != 2 || cfg.Managers[0] != "brew" || cfg.Managers[1] != "npm" {
		t.Errorf("unexpected managers: %v", cfg.Managers)
	}

	if len(cfg.Skip.Brew) != 2 {
		t.Errorf("expected 2 brew skip items, got %d", len(cfg.Skip.Brew))
	}

	if len(cfg.Schedule.Times) != 2 || cfg.Schedule.Times[0] != "09:00" {
		t.Errorf("unexpected schedule times: %v", cfg.Schedule.Times)
	}

	if cfg.Logging.RetentionDays != 7 {
		t.Errorf("expected RetentionDays=7, got %d", cfg.Logging.RetentionDays)
	}

	if cfg.Logging.Level != "debug" {
		t.Errorf("expected Level=debug, got %s", cfg.Logging.Level)
	}

	if !cfg.Brew.Greedy {
		t.Error("expected Brew.Greedy=true")
	}

	if !cfg.NPM.SkipMajor {
		t.Error("expected NPM.SkipMajor=true")
	}
}

func TestLoadFrom_VoltaSkipList(t *testing.T) {
	tmpDir := t.TempDir()
	configPath := filepath.Join(tmpDir, "config.toml")

	configContent := `
[skip]
volta = ["agent-browser", "@google/gemini-cli"]
`

	if err := os.WriteFile(configPath, []byte(configContent), 0644); err != nil {
		t.Fatalf("failed to write config: %v", err)
	}

	cfg, err := config.LoadFrom(configPath)
	if err != nil {
		t.Fatalf("failed to load config: %v", err)
	}

	skipList := cfg.GetSkipList("volta")
	if len(skipList) != 2 {
		t.Fatalf("expected 2 volta skip items, got %d", len(skipList))
	}
	if skipList[0] != "agent-browser" {
		t.Errorf("expected first skip item to be agent-browser, got %s", skipList[0])
	}
	if skipList[1] != "@google/gemini-cli" {
		t.Errorf("expected second skip item to be @google/gemini-cli, got %s", skipList[1])
	}

	// Verify ShouldSkip works end-to-end from loaded config
	if !cfg.ShouldSkip("volta", "agent-browser") {
		t.Error("expected agent-browser to be skipped for volta")
	}
	if !cfg.ShouldSkip("volta", "@google/gemini-cli") {
		t.Error("expected @google/gemini-cli to be skipped for volta")
	}
	if cfg.ShouldSkip("volta", "wrangler") {
		t.Error("expected wrangler to not be skipped for volta")
	}
	// Skip list is per-manager
	if cfg.ShouldSkip("npm", "agent-browser") {
		t.Error("expected agent-browser to not be skipped for npm")
	}
}

func TestSaveAndLoad(t *testing.T) {
	tmpDir := t.TempDir()
	configPath := filepath.Join(tmpDir, "sarasa", "config.toml")

	cfg := config.DefaultConfig()
	cfg.Managers = []string{"brew", "volta"}
	cfg.Skip.Brew = []string{"imagemagick"}
	cfg.Brew.Greedy = true

	if err := config.SaveTo(cfg, configPath); err != nil {
		t.Fatalf("failed to save config: %v", err)
	}

	loaded, err := config.LoadFrom(configPath)
	if err != nil {
		t.Fatalf("failed to load config: %v", err)
	}

	if len(loaded.Managers) != 2 {
		t.Errorf("expected 2 managers, got %d", len(loaded.Managers))
	}

	if len(loaded.Skip.Brew) != 1 || loaded.Skip.Brew[0] != "imagemagick" {
		t.Errorf("unexpected skip list: %v", loaded.Skip.Brew)
	}

	if !loaded.Brew.Greedy {
		t.Error("expected Brew.Greedy=true after load")
	}
}
