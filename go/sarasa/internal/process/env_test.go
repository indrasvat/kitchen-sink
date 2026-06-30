package process

import (
	"bytes"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestConfigureAddsUserLocalPathAndClosesStdin(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("PATH", "/usr/bin:/bin")

	cmd := exec.Command("/bin/sh", "-c", "printf '%s' \"$PATH\"; read value || printf '\\nEOF'")
	Configure(cmd, nil)

	var stdout bytes.Buffer
	cmd.Stdout = &stdout
	if err := cmd.Run(); err != nil {
		t.Fatalf("command failed: %v", err)
	}

	output := stdout.String()
	if !strings.Contains(output, filepath.Join(home, ".local", "bin")) {
		t.Fatalf("PATH missing user-local bin: %q", output)
	}
	if !strings.HasSuffix(output, "\nEOF") {
		t.Fatalf("stdin was not closed: %q", output)
	}
}
