package manager

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
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

func TestCustomMissingPolicySkipByDefault(t *testing.T) {
	cfg := config.DefaultConfig()
	cfg.Custom.Tools = []config.CustomToolConfig{
		{
			Name:    "missing-skip",
			Binary:  "__sarasa_missing_binary__",
			Latest:  config.CustomLatestConfig{Value: "1.0.0"},
			Upgrade: config.CustomActionConfig{Shell: "printf should-not-run"},
		},
	}

	got, err := NewCustom(&Options{Config: cfg}).CheckOutdated(context.Background())
	if err != nil {
		t.Fatalf("CheckOutdated failed: %v", err)
	}
	if len(got) != 0 {
		t.Fatalf("expected missing skip policy to report no packages, got %d", len(got))
	}
}

func TestCustomMissingPolicyInstallDryRun(t *testing.T) {
	cfg := config.DefaultConfig()
	cfg.Custom.Tools = []config.CustomToolConfig{
		{
			Name:    "missing-install",
			Binary:  "__sarasa_missing_binary__",
			Missing: "install",
			Latest:  config.CustomLatestConfig{Value: "1.2.3"},
			Upgrade: config.CustomActionConfig{Shell: "printf should-not-run"},
		},
	}

	result, err := NewCustom(&Options{Config: cfg}).Upgrade(context.Background(), true)
	if err != nil {
		t.Fatalf("Upgrade dry-run failed: %v", err)
	}
	if len(result.Skipped) != 1 {
		t.Fatalf("expected 1 skipped package, got %d", len(result.Skipped))
	}
	pkg := result.Skipped[0]
	if pkg.Name != "missing-install" {
		t.Errorf("Name = %q, want missing-install", pkg.Name)
	}
	if pkg.Current != customNotInstalled {
		t.Errorf("Current = %q, want %q", pkg.Current, customNotInstalled)
	}
	if pkg.Latest != "1.2.3" {
		t.Errorf("Latest = %q, want 1.2.3", pkg.Latest)
	}
	if pkg.Method != "pinned / shell" {
		t.Errorf("Method = %q, want pinned / shell", pkg.Method)
	}
}

func TestCustomMissingPolicyInstallRunsAndVerifies(t *testing.T) {
	tmpDir := t.TempDir()
	versionFile := filepath.Join(tmpDir, "installed-version.txt")

	cfg := config.DefaultConfig()
	cfg.Custom.StateDir = filepath.Join(tmpDir, "state")
	cfg.Custom.Tools = []config.CustomToolConfig{
		{
			Name:    "bootstrap-tool",
			Binary:  "__sarasa_missing_binary__",
			Missing: "install",
			Latest:  config.CustomLatestConfig{Value: "2.0.0"},
			Upgrade: config.CustomActionConfig{
				Argv: []string{"sh", "-c", "printf '2.0.0' > \"$1\"", "sarasa-test", versionFile},
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
	if result.Upgraded[0].Current != customNotInstalled {
		t.Errorf("Current = %q, want %q", result.Upgraded[0].Current, customNotInstalled)
	}
	data, err := os.ReadFile(versionFile)
	if err != nil {
		t.Fatalf("read version file: %v", err)
	}
	if string(data) != "2.0.0" {
		t.Errorf("version file = %q, want 2.0.0", data)
	}
	if _, err := os.Stat(filepath.Join(cfg.Custom.StateDir, "bootstrap-tool.json")); err != nil {
		t.Errorf("expected state file to be written: %v", err)
	}
}

func TestCustomMissingPolicyInstallVerifiesUserLocalBinaryFromSparsePath(t *testing.T) {
	home := t.TempDir()
	binDir := filepath.Join(home, ".local", "bin")
	if err := os.MkdirAll(binDir, 0755); err != nil {
		t.Fatalf("create bin dir: %v", err)
	}
	t.Setenv("HOME", home)
	t.Setenv("PATH", "/usr/bin:/bin")

	toolPath := filepath.Join(binDir, "sarasa-path-tool")
	installScript := "printf '#!/bin/sh\\necho v2.0.0\\n' > " + toolPath + " && chmod +x " + toolPath

	cfg := config.DefaultConfig()
	cfg.Custom.StateDir = filepath.Join(home, ".local", "state", "sarasa", "custom")
	cfg.Custom.Tools = []config.CustomToolConfig{
		{
			Name:    "sarasa-path-tool",
			Binary:  "sarasa-path-tool",
			Missing: "install",
			Latest:  config.CustomLatestConfig{Value: "v2.0.0"},
			Upgrade: config.CustomActionConfig{Shell: installScript},
			Verify: config.CustomProbeConfig{
				Argv:  []string{"sarasa-path-tool", "--version"},
				Regex: `v?[0-9]+\.[0-9]+\.[0-9]+`,
			},
		},
	}

	result, err := NewCustom(&Options{Config: cfg}).Upgrade(context.Background(), false)
	if err != nil {
		t.Fatalf("Upgrade failed: %v", err)
	}
	if len(result.Upgraded) != 1 {
		t.Fatalf("expected 1 upgraded package, got %d failed=%d", len(result.Upgraded), len(result.Failed))
	}
	if result.Upgraded[0].Latest != "v2.0.0" {
		t.Errorf("Latest = %q, want v2.0.0", result.Upgraded[0].Latest)
	}
}

func TestCustomMissingPolicyFail(t *testing.T) {
	cfg := config.DefaultConfig()
	cfg.Custom.Tools = []config.CustomToolConfig{
		{
			Name:    "missing-fail",
			Binary:  "__sarasa_missing_binary__",
			Missing: "fail",
			Latest:  config.CustomLatestConfig{Value: "1.0.0"},
		},
	}

	_, err := NewCustom(&Options{Config: cfg}).CheckOutdated(context.Background())
	if err == nil {
		t.Fatal("expected missing fail policy to return an error")
	}
	if !strings.Contains(err.Error(), "missing-fail") {
		t.Fatalf("expected error to mention tool name, got %v", err)
	}
}

func TestCustomMissingPolicyInvalid(t *testing.T) {
	cfg := config.DefaultConfig()
	cfg.Custom.Tools = []config.CustomToolConfig{
		{
			Name:    "missing-invalid",
			Binary:  "__sarasa_missing_binary__",
			Missing: "explode",
			Latest:  config.CustomLatestConfig{Value: "1.0.0"},
		},
	}

	_, err := NewCustom(&Options{Config: cfg}).CheckOutdated(context.Background())
	if err == nil {
		t.Fatal("expected invalid missing policy to return an error")
	}
	if !strings.Contains(err.Error(), "unknown missing policy") {
		t.Fatalf("expected unknown policy error, got %v", err)
	}
}

func TestLatestGitHubReleaseUsesGHToken(t *testing.T) {
	t.Setenv("GITHUB_TOKEN", "")
	t.Setenv("GH_TOKEN", "gh-secret")

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/repos/indrasvat/demo/releases/latest" {
			t.Fatalf("unexpected path %q", r.URL.Path)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer gh-secret" {
			t.Fatalf("Authorization = %q, want Bearer gh-secret", got)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"tag_name":"v1.2.3"}`))
	}))
	defer server.Close()

	oldBaseURL := githubAPIBaseURL
	oldClient := githubHTTPClient
	githubAPIBaseURL = server.URL
	githubHTTPClient = server.Client()
	t.Cleanup(func() {
		githubAPIBaseURL = oldBaseURL
		githubHTTPClient = oldClient
	})

	got, err := latestGitHubRelease(context.Background(), "indrasvat/demo")
	if err != nil {
		t.Fatalf("latestGitHubRelease failed: %v", err)
	}
	if got != "v1.2.3" {
		t.Fatalf("latestGitHubRelease = %q, want v1.2.3", got)
	}
}

func TestLatestGitHubReleaseFallsBackToGHOnForbidden(t *testing.T) {
	t.Setenv("GITHUB_TOKEN", "")
	t.Setenv("GH_TOKEN", "")

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, "rate limited", http.StatusForbidden)
	}))
	defer server.Close()

	tmpDir := t.TempDir()
	ghPath := filepath.Join(tmpDir, "gh")
	if err := os.WriteFile(ghPath, []byte("#!/bin/sh\nprintf 'v9.8.7\\n'\n"), 0755); err != nil {
		t.Fatalf("write fake gh: %v", err)
	}
	t.Setenv("PATH", tmpDir)

	oldBaseURL := githubAPIBaseURL
	oldClient := githubHTTPClient
	githubAPIBaseURL = server.URL
	githubHTTPClient = server.Client()
	t.Cleanup(func() {
		githubAPIBaseURL = oldBaseURL
		githubHTTPClient = oldClient
	})

	got, err := latestGitHubRelease(context.Background(), "indrasvat/demo")
	if err != nil {
		t.Fatalf("latestGitHubRelease failed: %v", err)
	}
	if got != "v9.8.7" {
		t.Fatalf("latestGitHubRelease = %q, want v9.8.7", got)
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
