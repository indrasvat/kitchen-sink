package cmd

import (
	"bytes"
	"strings"
	"testing"
)

func TestRootHelpIncludesCustomManager(t *testing.T) {
	t.Setenv("NO_COLOR", "1")

	var out bytes.Buffer
	rootCmd.SetOut(&out)
	t.Cleanup(func() {
		rootCmd.SetOut(nil)
	})

	styledHelp(rootCmd, nil)
	help := out.String()

	if !strings.Contains(rootCmd.Long, "custom tools") {
		t.Fatalf("root long description should mention custom tools: %q", rootCmd.Long)
	}

	const managers = "brew · volta · npm · pipx · bun · skills · custom"
	if !strings.Contains(help, managers) {
		t.Fatalf("root help should include custom manager list %q, got:\n%s", managers, help)
	}
}
