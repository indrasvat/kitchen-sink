package ui

import (
	"os"

	"golang.org/x/term"
)

// OutputMode represents the type of output to use.
type OutputMode int

const (
	// ModeTUI uses the full interactive bubbletea TUI.
	ModeTUI OutputMode = iota
	// ModeStyled uses lipgloss styling but no interactivity.
	ModeStyled
	// ModePlain uses plain text with no colors or styling.
	ModePlain
)

// DetectOutputMode determines the appropriate output mode based on environment.
func DetectOutputMode() OutputMode {
	// Check for NO_COLOR environment variable
	if _, ok := os.LookupEnv("NO_COLOR"); ok {
		return ModePlain
	}

	// Check for CI environment
	if isCI() {
		return ModePlain
	}

	// Check if stdout is a terminal
	if !term.IsTerminal(int(os.Stdout.Fd())) {
		return ModePlain
	}

	// Full TUI mode
	return ModeTUI
}

// isCI checks if we're running in a CI environment.
func isCI() bool {
	ciEnvVars := []string{
		"CI",
		"CONTINUOUS_INTEGRATION",
		"GITHUB_ACTIONS",
		"GITLAB_CI",
		"CIRCLECI",
		"TRAVIS",
		"JENKINS_URL",
		"BUILDKITE",
	}

	for _, env := range ciEnvVars {
		if _, ok := os.LookupEnv(env); ok {
			return true
		}
	}
	return false
}

// IsTTY returns true if stdout is a terminal.
func IsTTY() bool {
	return term.IsTerminal(int(os.Stdout.Fd()))
}

// SupportsColor returns true if the terminal supports colors.
func SupportsColor() bool {
	if _, ok := os.LookupEnv("NO_COLOR"); ok {
		return false
	}
	return IsTTY()
}
