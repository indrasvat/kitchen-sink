package scheduler

import (
	"path/filepath"
	"strings"
	"testing"
)

func TestDefaultEnvironmentPathIncludesUserLocalAndBinaryDir(t *testing.T) {
	home := t.TempDir()
	binDir := filepath.Join(home, "tools", "bin")
	t.Setenv("HOME", home)
	t.Setenv("PATH", "/usr/bin:/bin:/usr/bin")

	got := DefaultEnvironmentPath(filepath.Join(binDir, "sarasa"))
	parts := strings.Split(got, ":")

	wantPrefix := []string{
		binDir,
		filepath.Join(home, ".local", "bin"),
		filepath.Join(home, "bin"),
		filepath.Join(home, "go", "bin"),
	}
	if len(parts) < len(wantPrefix) {
		t.Fatalf("PATH too short: %q", got)
	}
	for i, want := range wantPrefix {
		if parts[i] != want {
			t.Fatalf("PATH[%d] = %q, want %q in %q", i, parts[i], want, got)
		}
	}

	if strings.Count(got, "/usr/bin") != 1 {
		t.Fatalf("expected /usr/bin to be deduplicated once in %q", got)
	}
}

func TestGeneratePlistRendersConfiguredEnvironmentPath(t *testing.T) {
	plist, err := GeneratePlist(&Config{
		Label:           LaunchAgentLabel,
		BinaryPath:      "/tmp/sarasa",
		LogDir:          "/tmp/logs",
		EnvironmentPath: "/tmp/bin:/usr/bin:/bin",
		Times:           []ScheduleTime{{Hour: 9, Minute: 30}},
	})
	if err != nil {
		t.Fatalf("GeneratePlist() error = %v", err)
	}

	text := string(plist)
	for _, want := range []string{
		"<string>/tmp/sarasa</string>",
		"<integer>9</integer>",
		"<integer>30</integer>",
		"<string>/tmp/bin:/usr/bin:/bin</string>",
		"<key>LowPriorityIO</key>",
		"<true/>",
	} {
		if !strings.Contains(text, want) {
			t.Fatalf("plist missing %q:\n%s", want, text)
		}
	}
}
