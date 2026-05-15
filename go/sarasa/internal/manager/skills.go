package manager

import (
	"bufio"
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/indrasvat/sarasa/internal/logger"
)

func init() {
	Register("skills", NewSkills)
}

// Skills implements the Manager interface for Vercel agentic skills (npx skills).
type Skills struct {
	opts *Options
}

// NewSkills creates a new skills manager.
func NewSkills(opts *Options) Manager {
	return &Skills{opts: opts}
}

func (s *Skills) Name() string {
	return "skills"
}

func (s *Skills) IsAvailable() bool {
	if _, err := exec.LookPath("npx"); err != nil {
		return false
	}
	_, err := os.Stat(skillLockFilePath())
	return err == nil
}

func (s *Skills) SetSkipList(packages []string) {
	s.opts.SkipList = packages
}

func (s *Skills) CheckOutdated(ctx context.Context) ([]Package, error) {
	log := logger.WithManager(s.Name())

	cmd := exec.CommandContext(ctx, "npx", "skills", "check")
	output, err := cmd.CombinedOutput()
	if err != nil {
		log.Debug("npx skills check returned non-zero",
			"error", err.Error(),
			"output", string(output),
			"action", "check_outdated",
		)
		// npx skills check may exit non-zero but still produce useful output
		if len(output) == 0 {
			return nil, nil
		}
	}

	if len(output) == 0 {
		return nil, nil
	}

	packages, unparsed := parseSkillsCheckOutput(string(output))
	if len(unparsed) > 0 {
		log.Debug("Unparsed lines from npx skills check",
			"unparsed_count", len(unparsed),
		)
	}

	// Apply skip list filtering
	var filtered []Package
	for _, pkg := range packages {
		if s.opts.ShouldSkip(pkg.Name) {
			continue
		}
		filtered = append(filtered, pkg)
	}

	return filtered, nil
}

func (s *Skills) Upgrade(ctx context.Context, dryRun bool) (*UpgradeResult, error) {
	log := logger.WithManager(s.Name())
	result := &UpgradeResult{}

	// Pre-check outdated skills for reporting (honors skip list).
	// Note: CheckOutdated may return (nil, nil) on transient failures,
	// so we don't use this to gate the update — only for result reporting.
	outdated, _ := s.CheckOutdated(ctx)

	if dryRun {
		result.Skipped = outdated
		log.Info("Would run npx skills update", "action", "upgrade", "dry_run", true)
		return result, nil
	}

	logger.LogStart(s.Name())

	start := time.Now()
	cmd := exec.CommandContext(ctx, "npx", "skills", "update")
	output, err := cmd.CombinedOutput()
	duration := time.Since(start).Milliseconds()

	if err != nil {
		log.Error("npx skills update failed",
			"action", "upgrade",
			"error", err.Error(),
			"output", string(output),
			"duration_ms", duration,
		)
		result.Failed = outdated
		return result, err
	}

	// Populate result with pre-checked outdated packages so the
	// TUI and plain renderers report what was upgraded.
	result.Upgraded = outdated

	log.Info("npx skills update completed",
		"action", "complete",
		"upgraded", len(result.Upgraded),
		"duration_ms", duration,
	)

	return result, nil
}

func (s *Skills) Cleanup(_ context.Context) error {
	return nil
}

// skillLockFilePath returns the path to the global skills lock file.
func skillLockFilePath() string {
	if xdg := os.Getenv("XDG_STATE_HOME"); xdg != "" {
		return filepath.Join(xdg, "skills", ".skill-lock.json")
	}
	homeDir, _ := os.UserHomeDir()
	return filepath.Join(homeDir, ".agents", ".skill-lock.json")
}

// ansiPattern matches ANSI escape sequences for stripping.
var ansiPattern = regexp.MustCompile(`\x1b\[[0-9;]*[a-zA-Z]`)

// stripANSI removes ANSI escape sequences from a string.
func stripANSI(s string) string {
	return ansiPattern.ReplaceAllString(s, "")
}

// parseSkillsCheckOutput parses the output of `npx skills check`.
//
// Expected format:
//
//	Checking for skill updates...
//	Checking N skill(s) for updates...
//
//	M update(s) available:
//
//	  ↑ skill-name
//	    source: owner/repo
//
//	Run npx skills update to update all skills
//
//	Could not check N skill(s) (may need reinstall)
//
//	  ✗ skill-name
//	    source: owner/repo
func parseSkillsCheckOutput(output string) (packages []Package, unparsed []string) {
	scanner := bufio.NewScanner(strings.NewReader(output))

	// Track whether we're in the "updates available" section vs the "could not check" section
	inUpdates := false
	inErrors := false
	var pendingName string

	for scanner.Scan() {
		line := stripANSI(scanner.Text())
		trimmed := strings.TrimSpace(line)

		// Skip empty lines
		if trimmed == "" {
			continue
		}

		// Detect section boundaries
		if strings.Contains(trimmed, "update(s) available") {
			inUpdates = true
			inErrors = false
			continue
		}
		if strings.Contains(trimmed, "Could not check") {
			inUpdates = false
			inErrors = true
			continue
		}

		// Skip informational lines
		if strings.HasPrefix(trimmed, "Checking") ||
			strings.HasPrefix(trimmed, "Run npx skills") ||
			strings.HasPrefix(trimmed, "All skills are up to date") {
			continue
		}

		// Parse update entries: "↑ skill-name"
		if inUpdates && strings.HasPrefix(trimmed, "↑") {
			pendingName = strings.TrimSpace(strings.TrimPrefix(trimmed, "↑"))
			continue
		}

		// Parse source line after an update entry
		if inUpdates && pendingName != "" && strings.HasPrefix(trimmed, "source:") {
			source := strings.TrimSpace(strings.TrimPrefix(trimmed, "source:"))
			packages = append(packages, Package{
				Name:    pendingName,
				Current: source,
				Latest:  "update available",
				IsMajor: false,
			})
			pendingName = ""
			continue
		}

		// Skip error section entries (✗ lines and their sources)
		if inErrors && (strings.HasPrefix(trimmed, "✗") || strings.HasPrefix(trimmed, "source:")) {
			continue
		}

		// Track unparsed lines (excluding the ones we intentionally skip)
		if inUpdates || inErrors {
			unparsed = append(unparsed, trimmed)
		}
	}

	// Handle case where an update entry had no source line
	if pendingName != "" {
		packages = append(packages, Package{
			Name:    pendingName,
			Current: customUnknown,
			Latest:  "update available",
			IsMajor: false,
		})
	}

	return packages, unparsed
}
