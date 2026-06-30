package manager

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/indrasvat/sarasa/internal/logger"
	"github.com/indrasvat/sarasa/internal/process"
)

func init() {
	Register("skills", NewSkills)
}

// Skills implements the Manager interface for Vercel agentic skills (npx skills).
type Skills struct {
	opts *Options
}

var errSkillsReadOnlyCheckUnsupported = errors.New("skills CLI does not provide a read-only update check; run skills without dry-run to update")

// NewSkills creates a new skills manager.
func NewSkills(opts *Options) Manager {
	return &Skills{opts: opts}
}

func (s *Skills) Name() string {
	return "skills"
}

func (s *Skills) IsAvailable() bool {
	if _, err := process.LookPath("npx"); err != nil {
		return false
	}
	_, err := os.Stat(skillLockFilePath())
	return err == nil
}

func (s *Skills) SetSkipList(packages []string) {
	if s.opts == nil {
		s.opts = &Options{}
	}
	s.opts.SkipList = packages
}

func (s *Skills) CheckOutdated(ctx context.Context) ([]Package, error) {
	_ = ctx
	return nil, errSkillsReadOnlyCheckUnsupported
}

func (s *Skills) Upgrade(ctx context.Context, dryRun bool) (*UpgradeResult, error) {
	log := logger.WithManager(s.Name())
	result := &UpgradeResult{}

	if dryRun {
		log.Info("Skipping skills dry-run because the skills CLI has no read-only check command",
			"action", "upgrade",
			"dry_run", true,
		)
		return result, errSkillsReadOnlyCheckUnsupported
	}

	targetSkills, skipped, err := s.updateTargets()
	if err != nil {
		return nil, err
	}
	result.Skipped = append(result.Skipped, skipped...)
	if len(targetSkills) == 0 && len(skipped) > 0 {
		log.Info("All tracked skills are in skip list", "action", "upgrade", "skipped", len(skipped))
		return result, nil
	}

	args := skillsUpdateArgs(targetSkills)
	cmd, commandLabel, err := s.command(ctx, args...)
	if err != nil {
		return nil, err
	}
	start := time.Now()
	output, err := cmd.CombinedOutput()
	duration := time.Since(start).Milliseconds()

	upgraded, failed, cliSkipped, unparsed := parseSkillsUpdateOutput(string(output))
	result.Upgraded = append(result.Upgraded, upgraded...)
	result.Failed = append(result.Failed, failed...)
	result.Skipped = append(result.Skipped, cliSkipped...)
	if len(unparsed) > 0 {
		log.Debug("Unparsed lines from skills update",
			"unparsed_count", len(unparsed),
		)
	}

	if err != nil {
		if len(result.Failed) == 0 {
			result.Failed = append(result.Failed, Package{
				Name:    "skills",
				Current: customUnknown,
				Latest:  "update failed",
			})
		}
		log.Error("skills update failed",
			"action", "upgrade",
			"command", commandLabel,
			"error", err.Error(),
			"output", string(output),
			"duration_ms", duration,
		)
		return result, err
	}

	log.Info("skills update completed",
		"action", "complete",
		"command", commandLabel,
		"upgraded", len(result.Upgraded),
		"failed", len(result.Failed),
		"skipped", len(result.Skipped),
		"duration_ms", duration,
	)

	return result, nil
}

func (s *Skills) Cleanup(_ context.Context) error {
	return nil
}

func (s *Skills) command(ctx context.Context, args ...string) (*exec.Cmd, string, error) {
	npxPath, err := process.LookPath("npx")
	if err != nil {
		return nil, "", err
	}
	cmdArgs := append([]string{"--yes", "skills"}, args...)
	cmd := exec.CommandContext(ctx, npxPath, cmdArgs...)
	process.Configure(cmd, nil)
	return cmd, strings.Join(append([]string{npxPath}, cmdArgs...), " "), nil
}

func skillsUpdateArgs(skills []string) []string {
	args := make([]string, 0, 3+len(skills))
	args = append(args, "update", "--global", "--yes")
	args = append(args, skills...)
	return args
}

type skillLock struct {
	Skills map[string]json.RawMessage `json:"skills"`
}

func readSkillLockNames() ([]string, error) {
	data, err := os.ReadFile(skillLockFilePath())
	if err != nil {
		return nil, err
	}
	var lock skillLock
	if err := json.Unmarshal(data, &lock); err != nil {
		return nil, err
	}
	names := make([]string, 0, len(lock.Skills))
	for name := range lock.Skills {
		names = append(names, name)
	}
	sort.Strings(names)
	return names, nil
}

func (s *Skills) updateTargets() ([]string, []Package, error) {
	if s.opts == nil || len(s.opts.SkipList) == 0 {
		return nil, nil, nil
	}
	names, err := readSkillLockNames()
	if err != nil {
		return nil, nil, err
	}
	targets := make([]string, 0, len(names))
	skipped := make([]Package, 0, len(s.opts.SkipList))
	for _, name := range names {
		if s.opts.ShouldSkip(name) {
			skipped = append(skipped, Package{
				Name:       name,
				Current:    customUnknown,
				Latest:     customUnknown,
				SkipReason: "in skip list",
			})
			continue
		}
		targets = append(targets, name)
	}
	return targets, skipped, nil
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

func parseSkillsUpdateOutput(output string) (upgraded, failed, skipped []Package, unparsed []string) {
	scanner := bufio.NewScanner(strings.NewReader(output))
	inSkipped := false

	for scanner.Scan() {
		line := stripANSI(scanner.Text())
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}

		if strings.Contains(trimmed, "skill(s) cannot be checked automatically") {
			inSkipped = true
			continue
		}
		if strings.HasPrefix(trimmed, "To update:") {
			continue
		}

		if name, ok := parseUpdatedSkillLine(trimmed); ok {
			upgraded = append(upgraded, Package{
				Name:    name,
				Current: customUnknown,
				Latest:  "latest",
			})
			inSkipped = false
			continue
		}
		if name, ok := parseFailedSkillLine(trimmed); ok {
			failed = append(failed, Package{
				Name:    name,
				Current: customUnknown,
				Latest:  "update failed",
			})
			inSkipped = false
			continue
		}
		if inSkipped {
			parsed := parseSkippedSkillLine(trimmed)
			if len(parsed) > 0 {
				skipped = append(skipped, parsed...)
				continue
			}
		}

		if isSkillsUpdateInfoLine(trimmed) {
			continue
		}
		unparsed = append(unparsed, trimmed)
	}

	return upgraded, failed, skipped, unparsed
}

func parseUpdatedSkillLine(line string) (string, bool) {
	if !strings.HasPrefix(line, "✓") {
		return "", false
	}
	line = strings.TrimSpace(strings.TrimPrefix(line, "✓"))
	if !strings.HasPrefix(line, "Updated") {
		return "", false
	}
	line = strings.TrimSpace(strings.TrimPrefix(line, "Updated"))
	if line == "" || strings.Contains(line, "skill(s)") {
		return "", false
	}
	return strings.TrimSpace(line), true
}

func parseFailedSkillLine(line string) (string, bool) {
	if !strings.HasPrefix(line, "✗") {
		return "", false
	}
	line = strings.TrimSpace(strings.TrimPrefix(line, "✗"))
	if !strings.HasPrefix(line, "Failed to update") {
		return "", false
	}
	line = strings.TrimSpace(strings.TrimPrefix(line, "Failed to update"))
	if line == "" || strings.Contains(line, "skill(s)") {
		return "", false
	}
	return strings.TrimSpace(line), true
}

var skippedSkillPattern = regexp.MustCompile(`^•\s+(.+)\s+\(([^)]+)\)$`)

func parseSkippedSkillLine(line string) []Package {
	matches := skippedSkillPattern.FindStringSubmatch(line)
	if len(matches) != 3 {
		return nil
	}
	names := strings.Split(matches[1], ",")
	packages := make([]Package, 0, len(names))
	for _, name := range names {
		name = strings.TrimSpace(name)
		if name == "" {
			continue
		}
		packages = append(packages, Package{
			Name:       name,
			Current:    customUnknown,
			Latest:     customUnknown,
			SkipReason: matches[2],
		})
	}
	return packages
}

func isSkillsUpdateInfoLine(line string) bool {
	return strings.HasPrefix(line, "Checking for skill updates") ||
		strings.HasPrefix(line, "Checking skills from source:") ||
		strings.HasPrefix(line, "Warning:") ||
		strings.HasPrefix(line, "Skipping deletion in non-interactive mode") ||
		strings.Contains(line, "GitHub rate limit reached") ||
		strings.Contains(line, "set GITHUB_TOKEN") ||
		strings.HasPrefix(line, "Found ") ||
		strings.HasPrefix(line, "Updating ") ||
		strings.HasPrefix(line, "•") ||
		strings.HasPrefix(line, "✓ Updated ") ||
		strings.HasPrefix(line, "Failed to update ") ||
		strings.HasPrefix(line, "All global skills are up to date") ||
		strings.HasPrefix(line, "✓ All global skills are up to date")
}
