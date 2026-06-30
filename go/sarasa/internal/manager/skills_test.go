package manager

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

const testSkillGhGhent = "gh-ghent"

func TestSkillsCheckOutdatedUnsupported(t *testing.T) {
	m := NewSkills(&Options{})

	got, err := m.CheckOutdated(context.Background())
	if !errors.Is(err, errSkillsReadOnlyCheckUnsupported) {
		t.Fatalf("expected unsupported check error, got %v", err)
	}
	if got != nil {
		t.Fatalf("expected nil package list, got %v", got)
	}
}

func TestSkillsDryRunUnsupported(t *testing.T) {
	m := NewSkills(&Options{})

	got, err := m.Upgrade(context.Background(), true)
	if !errors.Is(err, errSkillsReadOnlyCheckUnsupported) {
		t.Fatalf("expected unsupported dry-run error, got %v", err)
	}
	if got == nil {
		t.Fatal("expected non-nil result")
	}
	if len(got.Upgraded) != 0 || len(got.Failed) != 0 || len(got.Skipped) != 0 {
		t.Fatalf("expected empty result, got %+v", got)
	}
}

func TestSkillsUpdateArgs_GlobalNonInteractive(t *testing.T) {
	got := skillsUpdateArgs(nil)
	expected := []string{"update", "--global", "--yes"}
	assertStringSliceEqual(t, got, expected)
}

func TestSkillsUpdateArgs_WithSpecificSkills(t *testing.T) {
	got := skillsUpdateArgs([]string{"cass", testSkillGhGhent})
	expected := []string{"update", "--global", "--yes", "cass", testSkillGhGhent}
	assertStringSliceEqual(t, got, expected)
}

func TestSkillsUpdateTargetsHonorsSkipList(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	lockPath := filepath.Join(home, ".agents", ".skill-lock.json")
	if err := os.MkdirAll(filepath.Dir(lockPath), 0o755); err != nil {
		t.Fatal(err)
	}
	lock := `{
  "version": 3,
  "skills": {
    "shux": {},
    "cass": {},
    "gh-ghent": {}
  }
}`
	if err := os.WriteFile(lockPath, []byte(lock), 0o644); err != nil {
		t.Fatal(err)
	}

	m := &Skills{opts: &Options{SkipList: []string{"shux"}}}
	targets, skipped, err := m.updateTargets()
	if err != nil {
		t.Fatal(err)
	}

	assertStringSliceEqual(t, targets, []string{"cass", testSkillGhGhent})
	if len(skipped) != 1 {
		t.Fatalf("expected 1 skipped package, got %v", skipped)
	}
	if skipped[0].Name != "shux" || skipped[0].SkipReason != "in skip list" {
		t.Fatalf("unexpected skipped package: %+v", skipped[0])
	}
}

func TestParseSkillsUpdateOutput_NoUpdates(t *testing.T) {
	output := `Checking for skill updates...

Checking skills from source: indrasvat/shux
✓ All global skills are up to date`

	upgraded, failed, skipped, unparsed := parseSkillsUpdateOutput(output)
	if len(upgraded) != 0 || len(failed) != 0 || len(skipped) != 0 || len(unparsed) != 0 {
		t.Fatalf("expected empty result, got upgraded=%v failed=%v skipped=%v unparsed=%v", upgraded, failed, skipped, unparsed)
	}
}

func TestParseSkillsUpdateOutput_UpdatedAndFailed(t *testing.T) {
	output := `Checking for skill updates...

Found 2 global update(s)

Updating cass...
  ✓ Updated cass
Updating gh-ghent...
  ✗ Failed to update gh-ghent

✓ Updated 1 skill(s)
Failed to update 1 skill(s)`

	upgraded, failed, skipped, unparsed := parseSkillsUpdateOutput(output)
	if len(upgraded) != 1 {
		t.Fatalf("expected 1 upgraded package, got %v", upgraded)
	}
	if upgraded[0].Name != "cass" {
		t.Fatalf("expected cass upgraded, got %s", upgraded[0].Name)
	}
	if len(failed) != 1 {
		t.Fatalf("expected 1 failed package, got %v", failed)
	}
	if failed[0].Name != testSkillGhGhent {
		t.Fatalf("expected gh-ghent failed, got %s", failed[0].Name)
	}
	if len(skipped) != 0 {
		t.Fatalf("expected 0 skipped packages, got %v", skipped)
	}
	if len(unparsed) != 0 {
		t.Fatalf("expected 0 unparsed lines, got %v", unparsed)
	}
}

func TestParseSkillsUpdateOutput_SkippedUncheckable(t *testing.T) {
	output := `Checking for skill updates...

2 skill(s) cannot be checked automatically:
  • local-one (Local path)
  • legacy-one, legacy-two (No skill path recorded)
    To update: npx skills add owner/repo -g -y`

	upgraded, failed, skipped, unparsed := parseSkillsUpdateOutput(output)
	if len(upgraded) != 0 || len(failed) != 0 {
		t.Fatalf("expected no upgraded/failed packages, got upgraded=%v failed=%v", upgraded, failed)
	}
	if len(skipped) != 3 {
		t.Fatalf("expected 3 skipped packages, got %v", skipped)
	}
	if skipped[0].Name != "local-one" || skipped[0].SkipReason != "Local path" {
		t.Fatalf("unexpected first skipped package: %+v", skipped[0])
	}
	if skipped[1].Name != "legacy-one" || skipped[2].Name != "legacy-two" {
		t.Fatalf("unexpected grouped skipped packages: %+v", skipped)
	}
	if len(unparsed) != 0 {
		t.Fatalf("expected 0 unparsed lines, got %v", unparsed)
	}
}

func TestParseSkillsUpdateOutput_DeletedUpstreamWarning(t *testing.T) {
	output := `Checking for skill updates...

Warning: The following skills from google-labs-code/stitch-skills appear to have been deleted upstream:
  • react:components
Skipping deletion in non-interactive mode.
✓ All global skills are up to date`

	upgraded, failed, skipped, unparsed := parseSkillsUpdateOutput(output)
	if len(upgraded) != 0 || len(failed) != 0 || len(skipped) != 0 || len(unparsed) != 0 {
		t.Fatalf("expected warning-only output to parse cleanly, got upgraded=%v failed=%v skipped=%v unparsed=%v", upgraded, failed, skipped, unparsed)
	}
}

func TestStripANSI(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"no ansi", "no ansi"},
		{"\033[1mbold\033[0m", "bold"},
		{"\033[32m↑\033[0m \033[1mskill\033[0m", "↑ skill"},
		{"", ""},
	}

	for _, tt := range tests {
		got := stripANSI(tt.input)
		if got != tt.expected {
			t.Errorf("stripANSI(%q) = %q, want %q", tt.input, got, tt.expected)
		}
	}
}

func TestSkillLockFilePath_Default(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", "")

	path := skillLockFilePath()
	homeDir, _ := os.UserHomeDir()
	expected := filepath.Join(homeDir, ".agents", ".skill-lock.json")
	if path != expected {
		t.Errorf("expected %s, got %s", expected, path)
	}
}

func TestSkillLockFilePath_XDG(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", "/tmp/xdg-test")

	path := skillLockFilePath()
	expected := filepath.Join("/tmp/xdg-test", "skills", ".skill-lock.json")
	if path != expected {
		t.Errorf("expected %s, got %s", expected, path)
	}
}

func assertStringSliceEqual(t *testing.T, got, expected []string) {
	t.Helper()
	if len(got) != len(expected) {
		t.Fatalf("expected %v, got %v", expected, got)
	}
	for i := range expected {
		if got[i] != expected[i] {
			t.Fatalf("expected %v, got %v", expected, got)
		}
	}
}
