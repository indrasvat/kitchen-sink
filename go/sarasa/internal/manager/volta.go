package manager

import (
	"bufio"
	"context"
	"fmt"
	"os/exec"
	"regexp"
	"strings"
	"time"

	"github.com/indrasvat/sarasa/internal/logger"
)

func init() {
	Register("volta", NewVolta)
}

// Volta implements the Manager interface for Volta-managed npm packages.
type Volta struct {
	opts *Options
}

// NewVolta creates a new Volta manager.
func NewVolta(opts *Options) Manager {
	return &Volta{opts: opts}
}

func (v *Volta) Name() string {
	return "volta"
}

func (v *Volta) IsAvailable() bool {
	_, err := exec.LookPath("volta")
	return err == nil
}

// voltaPackage represents a parsed Volta package entry.
type voltaPackage struct {
	name    string
	version string
}

// packageRegex matches "package name@version / ..." lines from volta list.
var packageRegex = regexp.MustCompile(`^package\s+(@?[^@]+)@([^\s/]+)`)

// parseVoltaList parses the output of `volta list --format plain`.
// Returns packages and any lines that couldn't be parsed (for debugging).
func parseVoltaList(output string) ([]voltaPackage, []string) {
	var packages []voltaPackage
	var unparsedLines []string
	scanner := bufio.NewScanner(strings.NewReader(output))

	for scanner.Scan() {
		line := scanner.Text()
		// Only process lines starting with "package " (not runtime or package-manager)
		if !strings.HasPrefix(line, "package ") {
			continue
		}
		// Only process default packages (user-installed)
		if !strings.Contains(line, "(default)") {
			continue
		}

		matches := packageRegex.FindStringSubmatch(line)
		if len(matches) >= 3 {
			packages = append(packages, voltaPackage{
				name:    matches[1],
				version: matches[2],
			})
		} else {
			// Track lines that look like packages but couldn't be parsed
			unparsedLines = append(unparsedLines, line)
		}
	}

	return packages, unparsedLines
}

// getLatestVersion queries npm registry for the latest version of a package.
func (v *Volta) getLatestVersion(ctx context.Context, name string) (string, error) {
	cmd := exec.CommandContext(ctx, "npm", "view", name, "version")
	output, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("npm view failed for %s: %w", name, err)
	}
	return strings.TrimSpace(string(output)), nil
}

func (v *Volta) CheckOutdated(ctx context.Context) ([]Package, error) {
	log := logger.WithManager(v.Name())

	// Get list of installed Volta packages
	cmd := exec.CommandContext(ctx, "volta", "list", "--format", "plain")
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("volta list failed: %w", err)
	}

	installed, unparsed := parseVoltaList(string(output))

	// Log any lines that couldn't be parsed (format may have changed)
	if len(unparsed) > 0 {
		log.Warn("Some volta list lines could not be parsed - format may have changed",
			"unparsed_count", len(unparsed),
			"unparsed_lines", unparsed,
			"raw_output", string(output),
		)
	}

	if len(installed) == 0 {
		return nil, nil
	}

	var packages []Package
	for _, pkg := range installed {
		if v.opts.ShouldSkip(pkg.name) {
			continue
		}

		// Query npm for latest version
		latest, err := v.getLatestVersion(ctx, pkg.name)
		if err != nil {
			// Log but continue - package might not be on npm
			continue
		}

		if latest != pkg.version {
			p := Package{
				Name:    pkg.name,
				Current: pkg.version,
				Latest:  latest,
				IsMajor: isMajorUpgrade(pkg.version, latest),
			}

			if v.opts.SkipMajor && p.IsMajor {
				continue
			}

			packages = append(packages, p)
		}
	}

	return packages, nil
}

func (v *Volta) Upgrade(ctx context.Context, dryRun bool) (*UpgradeResult, error) {
	log := logger.WithManager(v.Name())
	result := &UpgradeResult{}

	outdated, err := v.CheckOutdated(ctx)
	if err != nil {
		return nil, err
	}

	if len(outdated) == 0 {
		log.Info("No outdated packages", "action", "upgrade")
		return result, nil
	}

	// Log outdated packages
	names := make([]string, len(outdated))
	for i, p := range outdated {
		names[i] = p.Name
	}
	logger.LogOutdated(v.Name(), names)

	if dryRun {
		result.Skipped = outdated
		return result, nil
	}

	// Upgrade each package
	for _, pkg := range outdated {
		if v.opts.ShouldSkip(pkg.Name) {
			logger.LogSkipped(v.Name(), pkg.Name, "in skip list")
			result.Skipped = append(result.Skipped, pkg)
			continue
		}

		if v.opts.SkipMajor && pkg.IsMajor {
			logger.LogSkipped(v.Name(), pkg.Name, "major version upgrade")
			result.Skipped = append(result.Skipped, pkg)
			continue
		}

		start := time.Now()
		cmd := exec.CommandContext(ctx, "volta", "install", pkg.Name+"@latest")
		output, err := cmd.CombinedOutput()
		duration := time.Since(start).Milliseconds()

		if err != nil {
			log.Error("volta install failed",
				"package", pkg.Name,
				"error", err.Error(),
				"output", string(output),
			)
			logger.LogUpgradeError(v.Name(), pkg.Name, err, duration)
			result.Failed = append(result.Failed, pkg)
			continue
		}

		// Verify the upgrade
		newVersion, verifyErr := v.getInstalledVersion(ctx, pkg.Name)
		if verifyErr != nil {
			log.Warn("Could not verify upgrade",
				"package", pkg.Name,
				"error", verifyErr.Error(),
			)
		}

		if newVersion != "" && newVersion == pkg.Current {
			log.Error("volta install completed but version unchanged",
				"package", pkg.Name,
				"expected", pkg.Latest,
				"actual", newVersion,
			)
			result.Failed = append(result.Failed, pkg)
		} else {
			actualNew := pkg.Latest
			if newVersion != "" {
				actualNew = newVersion
			}
			logger.LogUpgrade(v.Name(), pkg.Name, pkg.Current, actualNew, duration)
			result.Upgraded = append(result.Upgraded, pkg)
		}
	}

	return result, nil
}

func (v *Volta) Cleanup(_ context.Context) error {
	// Volta doesn't have a cleanup command
	return nil
}

// getInstalledVersion returns the currently installed version of a Volta package.
func (v *Volta) getInstalledVersion(ctx context.Context, name string) (string, error) {
	cmd := exec.CommandContext(ctx, "volta", "list", "--format", "plain")
	output, err := cmd.Output()
	if err != nil {
		return "", err
	}

	packages, _ := parseVoltaList(string(output))
	for _, pkg := range packages {
		if pkg.name == name {
			return pkg.version, nil
		}
	}

	return "", nil
}
