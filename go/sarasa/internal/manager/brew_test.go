package manager

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestShouldDeferBrewCaskWhenAppDirIsNotWritable(t *testing.T) {
	oldAppDir := brewAppDir
	brewAppDir = t.TempDir() + "/missing"
	t.Cleanup(func() { brewAppDir = oldAppDir })

	brewDir := t.TempDir()
	brewPath := filepath.Join(brewDir, "brew")
	if err := os.WriteFile(brewPath, []byte(`#!/bin/sh
cat <<'JSON'
{"casks":[{"artifacts":[{"app":["Demo.app"]}]}]}
JSON
`), 0755); err != nil {
		t.Fatalf("write fake brew: %v", err)
	}
	t.Setenv("PATH", brewDir)

	b := NewBrew(&Options{}).(*Brew)
	if got := b.deferReason(context.Background(), brewPath, Package{Name: "iterm2", Method: brewMethodCask}); got == "" {
		t.Fatal("expected cask to be deferred when app dir is not writable")
	}
	if got := b.deferReason(context.Background(), brewPath, Package{Name: "git", Method: brewMethodFormula}); got != "" {
		t.Fatal("expected formula to remain upgradeable")
	}
}

func TestShouldNotDeferCaskWithoutAppArtifacts(t *testing.T) {
	brewDir := t.TempDir()
	brewPath := filepath.Join(brewDir, "brew")
	if err := os.WriteFile(brewPath, []byte(`#!/bin/sh
cat <<'JSON'
{"casks":[{"artifacts":[{"binary":["tool"],"target":"/opt/homebrew/bin/tool"}]}]}
JSON
`), 0755); err != nil {
		t.Fatalf("write fake brew: %v", err)
	}
	t.Setenv("PATH", brewDir)

	b := NewBrew(&Options{}).(*Brew)
	if got := b.deferReason(context.Background(), brewPath, Package{Name: "tool-cask", Method: brewMethodCask}); got != "" {
		t.Fatal("expected non-app cask to remain upgradeable")
	}
}

func TestCaskAppTargetDirsParsesNestedTarget(t *testing.T) {
	oldAppDir := brewAppDir
	appDir := t.TempDir()
	brewAppDir = appDir
	t.Cleanup(func() { brewAppDir = oldAppDir })

	brewDir := t.TempDir()
	brewPath := filepath.Join(brewDir, "brew")
	if err := os.WriteFile(brewPath, []byte(`#!/bin/sh
cat <<'JSON'
{"casks":[{"artifacts":[{"app":["Foo.app",{"target":"Bar.app"}]}]}]}
JSON
`), 0755); err != nil {
		t.Fatalf("write fake brew: %v", err)
	}
	t.Setenv("PATH", brewDir)

	b := NewBrew(&Options{}).(*Brew)
	got, err := b.caskAppTargetDirs(context.Background(), brewPath, "foo")
	if err != nil {
		t.Fatalf("caskAppTargetDirs failed: %v", err)
	}
	if len(got) != 1 || got[0] != appDir {
		t.Fatalf("target dirs = %v, want [%s]", got, appDir)
	}
}

func TestCaskAppTargetDirsPreservesResolvedTopLevelTarget(t *testing.T) {
	userAppDir := t.TempDir()
	brewDir := t.TempDir()
	brewPath := filepath.Join(brewDir, "brew")
	if err := os.WriteFile(brewPath, []byte(fmt.Sprintf(`#!/bin/sh
cat <<'JSON'
{"casks":[{"artifacts":[{"app":["Foo.app",{"target":"Bar.app"}],"target":%q}]}]}
JSON
`, filepath.Join(userAppDir, "Bar.app"))), 0755); err != nil {
		t.Fatalf("write fake brew: %v", err)
	}
	t.Setenv("PATH", brewDir)

	b := NewBrew(&Options{}).(*Brew)
	got, err := b.caskAppTargetDirs(context.Background(), brewPath, "foo")
	if err != nil {
		t.Fatalf("caskAppTargetDirs failed: %v", err)
	}
	if len(got) != 1 || got[0] != userAppDir {
		t.Fatalf("target dirs = %v, want [%s]", got, userAppDir)
	}
}

func TestCaskTargetDirExpandsKnownTokens(t *testing.T) {
	prefix := t.TempDir()
	home := t.TempDir()
	t.Setenv("HOMEBREW_PREFIX", prefix)
	t.Setenv("HOME", home)

	tests := []struct {
		name   string
		target string
		want   string
	}{
		{"homebrew prefix", "$HOMEBREW_PREFIX/bin/fig", filepath.Join(prefix, "bin")},
		{"braced homebrew prefix", "${HOMEBREW_PREFIX}/bin/fig", filepath.Join(prefix, "bin")},
		{"home", "$HOME/Applications/Foo.app", filepath.Join(home, "Applications")},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, ok := caskTargetDir(tt.target)
			if !ok {
				t.Fatal("expected target to resolve")
			}
			if got != tt.want {
				t.Fatalf("target dir = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestCaskTargetDirRejectsUnknownTokens(t *testing.T) {
	if got, ok := caskTargetDir("$UNKNOWN_APPDIR/Foo.app"); ok {
		t.Fatalf("unknown token resolved to %q", got)
	}
}

func TestBrewKindArg(t *testing.T) {
	tests := []struct {
		name string
		pkg  Package
		want string
	}{
		{"formula", Package{Method: brewMethodFormula}, "--formula"},
		{"cask", Package{Method: brewMethodCask}, "--cask"},
		{"unknown", Package{}, ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := brewKindArg(tt.pkg)
			if tt.want == "" {
				if len(got) != 0 {
					t.Fatalf("brewKindArg() = %v, want empty", got)
				}
				return
			}
			if len(got) != 1 || got[0] != tt.want {
				t.Fatalf("brewKindArg() = %v, want [%s]", got, tt.want)
			}
		})
	}
}

func TestBrewDeferredReason(t *testing.T) {
	tests := []struct {
		name   string
		output string
		want   string
	}{
		{
			name:   "sudo password",
			output: "sudo: a terminal is required to read the password\nsudo: a password is required",
			want:   "requires sudo/admin credentials",
		},
		{
			name:   "existing app",
			output: "Error: zed: It seems there is already an App at '/opt/homebrew/Caskroom/zed/0.228.0/Zed.app'.",
			want:   "requires manual cask app cleanup or admin lease",
		},
		{
			name:   "timeout",
			output: "command timed out after 30m0s: signal: killed",
			want:   "requires manual cask upgrade after command timeout",
		},
		{
			name:   "untrusted tap",
			output: "Error: Refusing to load formula cloudflare/cloudflare/warp from untrusted tap cloudflare/cloudflare.",
			want:   "requires explicit brew tap trust",
		},
		{
			name:   "ordinary error",
			output: "Error: download failed",
			want:   "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := brewDeferredReason(Package{Method: brewMethodCask}, tt.output)
			if got != tt.want {
				t.Fatalf("brewDeferredReason() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestBrewDeferredReasonDoesNotHideFormulaFailures(t *testing.T) {
	output := "Error: Refusing to load formula cloudflare/cloudflare/warp from untrusted tap cloudflare/cloudflare."
	if got := brewDeferredReason(Package{Method: brewMethodFormula}, output); got != "" {
		t.Fatalf("formula failure deferred as %q", got)
	}
}

func TestBrewUpgradeFailureTextIncludesTimeoutError(t *testing.T) {
	text := brewUpgradeFailureText(nil, fmt.Errorf("command timed out after 30m0s: signal: killed"))
	got := brewDeferredReason(Package{Method: brewMethodCask}, text)
	if got != "requires manual cask upgrade after command timeout" {
		t.Fatalf("brewDeferredReason() = %q, want timeout deferral", got)
	}
}

func TestBrewUpgradeDefersCaskUpgradeFailure(t *testing.T) {
	tmpDir := t.TempDir()
	appDir := filepath.Join(tmpDir, "Applications")
	if err := os.MkdirAll(appDir, 0755); err != nil {
		t.Fatalf("create app dir: %v", err)
	}
	logPath := filepath.Join(tmpDir, "brew-args.log")
	brewDir := filepath.Join(tmpDir, "bin")
	if err := os.MkdirAll(brewDir, 0755); err != nil {
		t.Fatalf("create brew dir: %v", err)
	}
	brewPath := filepath.Join(brewDir, "brew")
	script := fmt.Sprintf(`#!/bin/sh
printf '%%s\n' "$*" >> %q
case "$1" in
  update)
    exit 0
    ;;
  outdated)
    cat <<'JSON'
{"formulae":[],"casks":[{"name":"demo","installed_versions":["1.0.0"],"current_version":"1.1.0"}]}
JSON
    exit 0
    ;;
  info)
    cat <<'JSON'
{"casks":[{"installed":"1.0.0","artifacts":[{"app":["Demo.app"],"target":%q}]}]}
JSON
    exit 0
    ;;
  upgrade)
    printf "Error: demo: It seems there is already an App at '/opt/homebrew/Caskroom/demo/1.0.0/Demo.app'.\n" >&2
    exit 1
    ;;
esac
exit 1
`, logPath, filepath.Join(appDir, "Demo.app"))
	if err := os.WriteFile(brewPath, []byte(script), 0755); err != nil {
		t.Fatalf("write fake brew: %v", err)
	}
	t.Setenv("PATH", brewDir)

	result, err := NewBrew(&Options{}).Upgrade(context.Background(), false)
	if err != nil {
		t.Fatalf("Upgrade failed: %v", err)
	}
	if len(result.Failed) != 0 {
		t.Fatalf("expected no failures, got %+v", result.Failed)
	}
	if len(result.Skipped) != 1 {
		t.Fatalf("expected 1 skipped package, got %+v", result.Skipped)
	}
	if result.Skipped[0].SkipReason != "requires manual cask app cleanup or admin lease" {
		t.Fatalf("SkipReason = %q", result.Skipped[0].SkipReason)
	}

	logBytes, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatalf("read brew args log: %v", err)
	}
	logText := string(logBytes)
	for _, want := range []string{"info --json=v2 --cask demo", "upgrade --cask demo"} {
		if !strings.Contains(logText, want) {
			t.Fatalf("brew args missing %q:\n%s", want, logText)
		}
	}
}
