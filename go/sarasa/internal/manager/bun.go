package manager

import (
	"bufio"
	"context"
	"fmt"
	"os/exec"
	"strings"
	"time"

	"github.com/indrasvat/sarasa/internal/logger"
)

func init() {
	Register("bun", NewBun)
}

// Bun implements the Manager interface for bun global packages.
type Bun struct {
	opts *Options
}

// NewBun creates a new bun manager.
func NewBun(opts *Options) Manager {
	return &Bun{opts: opts}
}

func (b *Bun) Name() string {
	return "bun"
}

func (b *Bun) IsAvailable() bool {
	_, err := exec.LookPath("bun")
	return err == nil
}

func (b *Bun) SetSkipList(packages []string) {
	b.opts.SkipList = packages
}

// bunPackage represents a parsed bun outdated entry.
type bunPackage struct {
	name    string
	current string
	update  string
	latest  string
}

// parseBunOutdated parses the output of `bun outdated -g`.
// Returns packages and any lines that couldn't be parsed (for debugging).
//
// Expected formats (bun uses different characters for TTY vs non-TTY):
//
// TTY (Unicode box-drawing):
//
//	bun outdated v1.3.6 (d530ed99)
//	┌─────────────┬─────────┬────────┬────────┐
//	│ Package     │ Current │ Update │ Latest │
//	├─────────────┼─────────┼────────┼────────┤
//	│ opencode-ai │ 1.1.33  │ 1.1.36 │ 1.1.36 │
//	└─────────────┴─────────┴────────┴────────┘
//
// Non-TTY (ASCII):
//
//	bun outdated v1.3.6 (d530ed99)
//	|-----------------------------------------|
//	| Package     | Current | Update | Latest |
//	|-------------|---------|--------|--------|
//	| opencode-ai | 1.1.33  | 1.1.36 | 1.1.36 |
//	|-----------------------------------------|
func parseBunOutdated(output string) ([]bunPackage, []string) {
	var packages []bunPackage
	var unparsedLines []string
	scanner := bufio.NewScanner(strings.NewReader(output))

	for scanner.Scan() {
		line := scanner.Text()

		// Skip empty lines
		if line == "" {
			continue
		}

		// Determine separator character (Unicode │ or ASCII |)
		var sep string
		switch {
		case strings.Contains(line, "│"):
			sep = "│"
		case strings.Contains(line, "|"):
			sep = "|"
		default:
			// No column separator found, skip this line
			continue
		}

		// Skip separator rows:
		// - Unicode: contains ┌├└─┬┼┴
		// - ASCII: line is mostly dashes like "|-----|-----|"
		if strings.ContainsAny(line, "┌├└─┬┼┴") {
			continue
		}
		if sep == "|" && strings.Count(line, "-") > strings.Count(line, " ") {
			continue
		}

		// Parse data row
		parts := strings.Split(line, sep)

		// After split by │, expect: ["", " opencode-ai ", " 1.1.33  ", " 1.1.36 ", " 1.1.36 ", ""]
		// That's 6 parts: empty + 4 columns + empty
		if len(parts) < 5 {
			unparsedLines = append(unparsedLines, line)
			continue
		}

		// Extract and trim each column
		name := strings.TrimSpace(parts[1])
		current := strings.TrimSpace(parts[2])
		update := strings.TrimSpace(parts[3])
		latest := strings.TrimSpace(parts[4])

		// Skip header row (contains column titles)
		if name == "Package" || current == "Current" {
			continue
		}

		// Validate we have actual package data
		if name == "" {
			unparsedLines = append(unparsedLines, line)
			continue
		}

		packages = append(packages, bunPackage{
			name:    name,
			current: current,
			update:  update,
			latest:  latest,
		})
	}

	return packages, unparsedLines
}

func (b *Bun) CheckOutdated(ctx context.Context) ([]Package, error) {
	log := logger.WithManager(b.Name())

	// Use bun outdated -g to get only outdated global packages
	cmd := exec.CommandContext(ctx, "bun", "outdated", "-g")
	output, err := cmd.Output()
	if err != nil {
		// Log the error but don't fail - might just be no packages
		log.Debug("bun outdated -g command failed",
			"error", err.Error(),
			"output", string(output),
			"action", "check_outdated",
		)
		// If there's output despite error, try to parse it
		if len(output) == 0 {
			return []Package{}, nil
		}
	}

	if len(output) == 0 {
		log.Debug("No outdated global packages", "action", "check_outdated")
		return []Package{}, nil
	}

	outdated, unparsed := parseBunOutdated(string(output))

	// Log any lines that couldn't be parsed (format may have changed)
	if len(unparsed) > 0 {
		log.Warn("Failed to parse some bun outdated output lines",
			"unparsed_count", len(unparsed),
			"unparsed_lines", unparsed,
			"raw_output", string(output),
			"hint", "bun CLI output format may have changed - check for bun updates",
		)
	}

	if len(outdated) == 0 {
		return []Package{}, nil
	}

	var packages []Package
	for _, pkg := range outdated {
		if b.opts.ShouldSkip(pkg.name) {
			continue
		}

		p := Package{
			Name:    pkg.name,
			Current: pkg.current,
			Latest:  pkg.latest,
			IsMajor: isMajorUpgrade(pkg.current, pkg.latest),
		}

		if b.opts.SkipMajor && p.IsMajor {
			continue
		}

		packages = append(packages, p)
	}

	return packages, nil
}

func (b *Bun) Upgrade(ctx context.Context, dryRun bool) (*UpgradeResult, error) {
	log := logger.WithManager(b.Name())
	result := &UpgradeResult{}

	packages, err := b.CheckOutdated(ctx)
	if err != nil {
		return nil, err
	}

	if len(packages) == 0 {
		log.Info("No outdated global packages", "action", "upgrade")
		return result, nil
	}

	// Log packages
	names := make([]string, len(packages))
	for i, p := range packages {
		names[i] = p.Name
	}
	logger.LogOutdated(b.Name(), names)

	if dryRun {
		result.Skipped = packages
		return result, nil
	}

	// Upgrade each package
	for _, pkg := range packages {
		if b.opts.ShouldSkip(pkg.Name) {
			logger.LogSkipped(b.Name(), pkg.Name, "in skip list")
			result.Skipped = append(result.Skipped, pkg)
			continue
		}

		if b.opts.SkipMajor && pkg.IsMajor {
			logger.LogSkipped(b.Name(), pkg.Name, "major version upgrade")
			result.Skipped = append(result.Skipped, pkg)
			continue
		}

		start := time.Now()
		installCmd := exec.CommandContext(ctx, "bun", "install", "-g", pkg.Name)
		output, cmdErr := installCmd.CombinedOutput()
		duration := time.Since(start).Milliseconds()

		if cmdErr != nil {
			log.Error("bun install -g failed",
				"package", pkg.Name,
				"current_version", pkg.Current,
				"target_version", pkg.Latest,
				"error", cmdErr.Error(),
				"output", string(output),
				"command", fmt.Sprintf("bun install -g %s", pkg.Name),
			)
			logger.LogUpgradeError(b.Name(), pkg.Name, cmdErr, duration)
			result.Failed = append(result.Failed, pkg)
			continue
		}

		// Verify the upgrade succeeded by checking the new version
		newVersion := b.getInstalledVersion(ctx, pkg.Name)
		if newVersion != "" && newVersion == pkg.Current {
			log.Error("bun install completed but version unchanged",
				"package", pkg.Name,
				"expected_version", pkg.Latest,
				"actual_version", newVersion,
				"output", string(output),
			)
			result.Failed = append(result.Failed, pkg)
		} else {
			actualNew := pkg.Latest
			if newVersion != "" {
				actualNew = newVersion
			}
			logger.LogUpgrade(b.Name(), pkg.Name, pkg.Current, actualNew, duration)
			result.Upgraded = append(result.Upgraded, pkg)
		}
	}

	return result, nil
}

// getInstalledVersion returns the currently installed version of a bun global package.
// Returns empty string if the package is not found or on error.
func (b *Bun) getInstalledVersion(ctx context.Context, name string) string {
	cmd := exec.CommandContext(ctx, "bun", "pm", "ls", "-g")
	output, err := cmd.Output()
	if err != nil {
		return ""
	}

	// Parse output to find the package version
	// Format: "└── package-name@version" or "├── package-name@version"
	scanner := bufio.NewScanner(strings.NewReader(string(output)))
	for scanner.Scan() {
		line := scanner.Text()

		// Strip tree-drawing characters (└── or ├──)
		line = strings.TrimSpace(line)
		line = strings.TrimPrefix(line, "└── ")
		line = strings.TrimPrefix(line, "├── ")

		// Check if this line is for our package
		if strings.HasPrefix(line, name+"@") {
			// Extract version from "package@version"
			if idx := strings.LastIndex(line, "@"); idx > 0 {
				return line[idx+1:]
			}
		}
	}

	return ""
}

func (b *Bun) Cleanup(_ context.Context) error {
	// bun doesn't have a cleanup command for global packages
	return nil
}
