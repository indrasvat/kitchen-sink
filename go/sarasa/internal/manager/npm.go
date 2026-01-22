package manager

import (
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strings"
	"time"

	"github.com/indrasvat/sarasa/internal/jsonutil"
	"github.com/indrasvat/sarasa/internal/logger"
)

func init() {
	Register("npm", NewNPM)
}

// NPM implements the Manager interface for npm global packages.
type NPM struct {
	opts *Options
}

// NewNPM creates a new npm manager.
func NewNPM(opts *Options) Manager {
	return &NPM{opts: opts}
}

func (n *NPM) Name() string {
	return "npm"
}

func (n *NPM) IsAvailable() bool {
	npmPath, err := exec.LookPath("npm")
	if err != nil {
		return false
	}
	// Skip if Volta is managing npm - Volta handles global packages differently
	// and npm outdated -g reports stale data from the Node image
	if strings.Contains(npmPath, ".volta") {
		return false
	}
	return true
}

// npmOutdatedPackage represents a package in npm outdated JSON output.
type npmOutdatedPackage struct {
	Current  string `json:"current"`
	Wanted   string `json:"wanted"`
	Latest   string `json:"latest"`
	Location string `json:"location"`
}

func (n *NPM) CheckOutdated(ctx context.Context) ([]Package, error) {
	cmd := exec.CommandContext(ctx, "npm", "outdated", "-g", "--json")
	output, err := cmd.Output()

	// npm outdated returns exit code 1 when there are outdated packages
	if err != nil {
		exitErr := &exec.ExitError{}
		if errors.As(err, &exitErr) {
			// Exit code 1 is expected when outdated packages exist
			if exitErr.ExitCode() != 1 {
				return nil, fmt.Errorf("npm outdated failed: %w", err)
			}
		}
	}

	if len(output) == 0 {
		return nil, nil
	}

	var outdated map[string]npmOutdatedPackage
	if err := jsonutil.Parse("npm", "outdated", output, &outdated); err != nil {
		return nil, err
	}

	var packages []Package
	for name, pkg := range outdated {
		if n.opts.ShouldSkip(name) {
			continue
		}

		p := Package{
			Name:    name,
			Current: pkg.Current,
			Latest:  pkg.Latest,
			IsMajor: isMajorUpgrade(pkg.Current, pkg.Latest),
		}

		// Skip major upgrades if configured
		if n.opts.SkipMajor && p.IsMajor {
			continue
		}

		packages = append(packages, p)
	}

	return packages, nil
}

func (n *NPM) Upgrade(ctx context.Context, dryRun bool) (*UpgradeResult, error) {
	log := logger.WithManager(n.Name())
	result := &UpgradeResult{}

	outdated, err := n.CheckOutdated(ctx)
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
	logger.LogOutdated(n.Name(), names)

	if dryRun {
		result.Skipped = outdated
		return result, nil
	}

	// Upgrade each package individually using npm install -g pkg@latest
	// This allows crossing major versions
	for _, pkg := range outdated {
		if n.opts.ShouldSkip(pkg.Name) {
			logger.LogSkipped(n.Name(), pkg.Name, "in skip list")
			result.Skipped = append(result.Skipped, pkg)
			continue
		}

		if n.opts.SkipMajor && pkg.IsMajor {
			logger.LogSkipped(n.Name(), pkg.Name, "major version upgrade")
			result.Skipped = append(result.Skipped, pkg)
			continue
		}

		start := time.Now()
		cmd := exec.CommandContext(ctx, "npm", "install", "-g", pkg.Name+"@latest")
		output, err := cmd.CombinedOutput()
		duration := time.Since(start).Milliseconds()

		if err != nil {
			log.Error("npm install failed",
				"package", pkg.Name,
				"error", err.Error(),
				"output", string(output),
			)
			logger.LogUpgradeError(n.Name(), pkg.Name, err, duration)
			result.Failed = append(result.Failed, pkg)
			continue
		}

		// Verify the upgrade actually happened by checking the current version
		newVersion, verifyErr := n.getPackageVersion(ctx, pkg.Name)
		if verifyErr != nil {
			log.Warn("Could not verify upgrade",
				"package", pkg.Name,
				"error", verifyErr.Error(),
			)
		}

		if newVersion != "" && newVersion == pkg.Current {
			// Version didn't change - upgrade didn't actually work
			log.Error("npm install completed but version unchanged",
				"package", pkg.Name,
				"expected", pkg.Latest,
				"actual", newVersion,
				"output", string(output),
			)
			result.Failed = append(result.Failed, pkg)
		} else {
			logger.LogUpgrade(n.Name(), pkg.Name, pkg.Current, pkg.Latest, duration)
			result.Upgraded = append(result.Upgraded, pkg)
		}
	}

	return result, nil
}

func (n *NPM) Cleanup(_ context.Context) error {
	// npm doesn't have a cleanup command for global packages
	return nil
}

// getPackageVersion returns the currently installed version of a global npm package.
func (n *NPM) getPackageVersion(ctx context.Context, name string) (string, error) {
	cmd := exec.CommandContext(ctx, "npm", "list", "-g", name, "--json", "--depth=0")
	output, err := cmd.Output()
	if err != nil {
		return "", err
	}

	var result struct {
		Dependencies map[string]struct {
			Version string `json:"version"`
		} `json:"dependencies"`
	}

	if err := jsonutil.Parse("npm", "list", output, &result); err != nil {
		return "", err
	}

	if dep, ok := result.Dependencies[name]; ok {
		return dep.Version, nil
	}

	return "", nil
}

// isMajorUpgrade checks if an upgrade crosses a major version boundary.
func isMajorUpgrade(current, latest string) bool {
	currentMajor := getMajorVersion(current)
	latestMajor := getMajorVersion(latest)
	return currentMajor != latestMajor && currentMajor != "" && latestMajor != ""
}

// getMajorVersion extracts the major version from a semver string.
func getMajorVersion(version string) string {
	// Remove leading 'v' if present
	version = strings.TrimPrefix(version, "v")

	// Split by '.' and return first part
	parts := strings.Split(version, ".")
	if len(parts) > 0 {
		return parts[0]
	}
	return ""
}
