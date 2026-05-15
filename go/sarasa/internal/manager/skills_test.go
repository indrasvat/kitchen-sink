package manager

import (
	"os"
	"path/filepath"
	"testing"
)

const testSkillGhGhent = "gh-ghent"

func TestParseSkillsCheckOutput_Empty(t *testing.T) {
	packages, unparsed := parseSkillsCheckOutput("")
	if len(packages) != 0 {
		t.Errorf("expected 0 packages, got %d", len(packages))
	}
	if len(unparsed) != 0 {
		t.Errorf("expected 0 unparsed, got %d", len(unparsed))
	}
}

func TestParseSkillsCheckOutput_NoUpdates(t *testing.T) {
	output := `Checking for skill updates...
Checking 5 skill(s) for updates...

All skills are up to date`

	packages, unparsed := parseSkillsCheckOutput(output)
	if len(packages) != 0 {
		t.Errorf("expected 0 packages, got %d", len(packages))
	}
	if len(unparsed) != 0 {
		t.Errorf("expected 0 unparsed, got %d", len(unparsed))
	}
}

func TestParseSkillsCheckOutput_SingleUpdate(t *testing.T) {
	output := `Checking for skill updates...
Checking 10 skill(s) for updates...

1 update(s) available:

  ↑ gh-ghent
    source: indrasvat/gh-ghent

Run npx skills update to update all skills`

	packages, unparsed := parseSkillsCheckOutput(output)
	if len(packages) != 1 {
		t.Fatalf("expected 1 package, got %d", len(packages))
	}
	if packages[0].Name != testSkillGhGhent {
		t.Errorf("expected name=gh-ghent, got %s", packages[0].Name)
	}
	if packages[0].Current != "indrasvat/gh-ghent" {
		t.Errorf("expected current=indrasvat/gh-ghent, got %s", packages[0].Current)
	}
	if packages[0].Latest != "update available" {
		t.Errorf("expected latest='update available', got %s", packages[0].Latest)
	}
	if packages[0].IsMajor {
		t.Error("expected IsMajor=false")
	}
	if len(unparsed) != 0 {
		t.Errorf("expected 0 unparsed, got %d: %v", len(unparsed), unparsed)
	}
}

func TestParseSkillsCheckOutput_MultipleUpdates(t *testing.T) {
	output := `Checking for skill updates...
Checking 21 skill(s) for updates...

2 update(s) available:

  ↑ cass
    source: Dicklesworthstone/coding_agent_session_search
  ↑ gh-ghent
    source: indrasvat/gh-ghent

Run npx skills update to update all skills`

	packages, unparsed := parseSkillsCheckOutput(output)
	if len(packages) != 2 {
		t.Fatalf("expected 2 packages, got %d", len(packages))
	}
	if packages[0].Name != "cass" {
		t.Errorf("expected first name=cass, got %s", packages[0].Name)
	}
	if packages[0].Current != "Dicklesworthstone/coding_agent_session_search" {
		t.Errorf("expected first source=Dicklesworthstone/coding_agent_session_search, got %s", packages[0].Current)
	}
	if packages[1].Name != testSkillGhGhent {
		t.Errorf("expected second name=gh-ghent, got %s", packages[1].Name)
	}
	if len(unparsed) != 0 {
		t.Errorf("expected 0 unparsed, got %d: %v", len(unparsed), unparsed)
	}
}

func TestParseSkillsCheckOutput_WithErrorSection(t *testing.T) {
	// Real-world output: updates + "could not check" entries
	output := `Checking for skill updates...
Checking 21 skill(s) for updates...

2 update(s) available:

  ↑ cass
    source: Dicklesworthstone/coding_agent_session_search
  ↑ gh-ghent
    source: indrasvat/gh-ghent

Run npx skills update to update all skills

Could not check 1 skill(s) (may need reinstall)

  ✗ hugging-face-paper-pages
    source: huggingface/skills`

	packages, unparsed := parseSkillsCheckOutput(output)
	if len(packages) != 2 {
		t.Fatalf("expected 2 packages (errors excluded), got %d", len(packages))
	}
	if packages[0].Name != "cass" {
		t.Errorf("expected first name=cass, got %s", packages[0].Name)
	}
	if packages[1].Name != testSkillGhGhent {
		t.Errorf("expected second name=gh-ghent, got %s", packages[1].Name)
	}
	if len(unparsed) != 0 {
		t.Errorf("expected 0 unparsed, got %d: %v", len(unparsed), unparsed)
	}
}

func TestParseSkillsCheckOutput_WithANSICodes(t *testing.T) {
	// Output with ANSI color codes wrapped around text
	output := "\033[1mChecking for skill updates...\033[0m\n" +
		"Checking 5 skill(s) for updates...\n\n" +
		"\033[32m1 update(s) available:\033[0m\n\n" +
		"  \033[33m↑\033[0m \033[1mmy-skill\033[0m\n" +
		"    source: owner/repo\n\n" +
		"Run npx skills update to update all skills"

	packages, unparsed := parseSkillsCheckOutput(output)
	if len(packages) != 1 {
		t.Fatalf("expected 1 package, got %d", len(packages))
	}
	if packages[0].Name != "my-skill" {
		t.Errorf("expected name=my-skill, got %s", packages[0].Name)
	}
	if packages[0].Current != "owner/repo" {
		t.Errorf("expected current=owner/repo, got %s", packages[0].Current)
	}
	if len(unparsed) != 0 {
		t.Errorf("expected 0 unparsed, got %d: %v", len(unparsed), unparsed)
	}
}

func TestParseSkillsCheckOutput_UpdateWithoutSource(t *testing.T) {
	// Edge case: update entry with no following source line
	output := `Checking for skill updates...
Checking 3 skill(s) for updates...

1 update(s) available:

  ↑ orphan-skill

Run npx skills update to update all skills`

	packages, _ := parseSkillsCheckOutput(output)
	if len(packages) != 1 {
		t.Fatalf("expected 1 package, got %d", len(packages))
	}
	if packages[0].Name != "orphan-skill" {
		t.Errorf("expected name=orphan-skill, got %s", packages[0].Name)
	}
	if packages[0].Current != customUnknown {
		t.Errorf("expected current=unknown for orphan, got %s", packages[0].Current)
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
