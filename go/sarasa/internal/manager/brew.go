package manager

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
	"time"

	"github.com/indrasvat/sarasa/internal/jsonutil"
	"github.com/indrasvat/sarasa/internal/logger"
)

func init() {
	Register("brew", NewBrew)
}

// Brew implements the Manager interface for Homebrew.
type Brew struct {
	opts *Options
}

// NewBrew creates a new Homebrew manager.
func NewBrew(opts *Options) Manager {
	return &Brew{
		opts: opts,
	}
}

func (b *Brew) Name() string {
	return "brew"
}

func (b *Brew) IsAvailable() bool {
	_, err := exec.LookPath("brew")
	return err == nil
}

// brewOutdatedJSON represents the JSON output of `brew outdated --json=v2`.
type brewOutdatedJSON struct {
	Formulae []brewFormula `json:"formulae"`
	Casks    []brewCask    `json:"casks"`
}

type brewFormula struct {
	Name              string                 `json:"name"`
	InstalledVersions jsonutil.StringOrSlice `json:"installed_versions"`
	CurrentVersion    string                 `json:"current_version"`
	PinnedVersion     string                 `json:"pinned_version"`
}

type brewCask struct {
	Name              string                 `json:"name"`
	InstalledVersions jsonutil.StringOrSlice `json:"installed_versions"`
	CurrentVersion    string                 `json:"current_version"`
}

func (b *Brew) CheckOutdated(ctx context.Context) ([]Package, error) {
	// First run brew update
	updateCmd := exec.CommandContext(ctx, "brew", "update")
	if err := updateCmd.Run(); err != nil {
		return nil, fmt.Errorf("brew update failed: %w", err)
	}

	// Get outdated packages
	args := []string{"outdated", "--json=v2"}
	if b.opts.Greedy {
		args = append(args, "--greedy")
	}

	cmd := exec.CommandContext(ctx, "brew", args...)
	output, err := cmd.Output()
	if err != nil {
		// brew outdated returns exit code 0 even with outdated packages
		if len(output) == 0 {
			return nil, fmt.Errorf("brew outdated failed: %w", err)
		}
	}

	if len(output) == 0 {
		return nil, nil
	}

	var outdated brewOutdatedJSON
	if err := jsonutil.Parse("brew", "outdated", output, &outdated); err != nil {
		return nil, err
	}

	var packages []Package

	// Add formulae
	for _, f := range outdated.Formulae {
		if b.opts.ShouldSkip(f.Name) {
			continue
		}
		packages = append(packages, Package{
			Name:    f.Name,
			Current: f.InstalledVersions.First(),
			Latest:  f.CurrentVersion,
		})
	}

	// Add casks
	for _, c := range outdated.Casks {
		if b.opts.ShouldSkip(c.Name) {
			continue
		}
		packages = append(packages, Package{
			Name:    c.Name,
			Current: c.InstalledVersions.First(),
			Latest:  c.CurrentVersion,
		})
	}

	return packages, nil
}

func (b *Brew) Upgrade(ctx context.Context, dryRun bool) (*UpgradeResult, error) {
	log := logger.WithManager(b.Name())
	result := &UpgradeResult{}

	outdated, err := b.CheckOutdated(ctx)
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
	logger.LogOutdated(b.Name(), names)

	if dryRun {
		result.Skipped = outdated
		return result, nil
	}

	// Upgrade all packages
	for _, pkg := range outdated {
		if b.opts.ShouldSkip(pkg.Name) {
			logger.LogSkipped(b.Name(), pkg.Name, "in skip list")
			result.Skipped = append(result.Skipped, pkg)
			continue
		}

		start := time.Now()
		cmd := exec.CommandContext(ctx, "brew", "upgrade", pkg.Name)
		output, err := cmd.CombinedOutput()
		duration := time.Since(start).Milliseconds()

		if err != nil {
			log.Error("brew upgrade failed",
				"package", pkg.Name,
				"error", err.Error(),
				"output", string(output),
			)
			logger.LogUpgradeError(b.Name(), pkg.Name, err, duration)
			result.Failed = append(result.Failed, pkg)
			continue
		}

		// Verify upgrade by checking installed version
		newVersion, verifyErr := b.getInstalledVersion(ctx, pkg.Name)
		if verifyErr != nil {
			log.Warn("Could not verify upgrade",
				"package", pkg.Name,
				"error", verifyErr.Error(),
			)
		}

		if newVersion != "" && newVersion == pkg.Current {
			log.Error("brew upgrade completed but version unchanged",
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
			logger.LogUpgrade(b.Name(), pkg.Name, pkg.Current, actualNew, duration)
			result.Upgraded = append(result.Upgraded, pkg)
		}
	}

	return result, nil
}

// getInstalledVersion returns the currently installed version of a brew package.
func (b *Brew) getInstalledVersion(ctx context.Context, name string) (string, error) {
	cmd := exec.CommandContext(ctx, "brew", "info", "--json=v2", name)
	output, err := cmd.Output()
	if err != nil {
		return "", err
	}

	var result struct {
		Formulae []struct {
			Installed []struct {
				Version string `json:"version"`
			} `json:"installed"`
		} `json:"formulae"`
		Casks []struct {
			Installed jsonutil.StringOrSlice `json:"installed"`
		} `json:"casks"`
	}

	if err := jsonutil.Parse("brew", "info", output, &result); err != nil {
		return "", err
	}

	// Check formulae
	if len(result.Formulae) > 0 && len(result.Formulae[0].Installed) > 0 {
		return result.Formulae[0].Installed[0].Version, nil
	}

	// Check casks
	if len(result.Casks) > 0 {
		return result.Casks[0].Installed.First(), nil
	}

	return "", nil
}

func (b *Brew) Cleanup(ctx context.Context) error {
	log := logger.WithManager(b.Name())

	// Get current cache size before cleanup
	duCmd := exec.CommandContext(ctx, "brew", "--cache")
	cacheDir, err := duCmd.Output()
	if err != nil {
		return fmt.Errorf("failed to get cache dir: %w", err)
	}

	// Run cleanup
	cleanupCmd := exec.CommandContext(ctx, "brew", "cleanup")
	if err := cleanupCmd.Run(); err != nil {
		return fmt.Errorf("brew cleanup failed: %w", err)
	}

	// Run autoremove
	autoremoveCmd := exec.CommandContext(ctx, "brew", "autoremove")
	if err := autoremoveCmd.Run(); err != nil {
		log.Warn("brew autoremove failed", "error", err.Error())
	}

	// Estimate freed space (simplified)
	logger.LogCleanup(b.Name(), 0) // Would need to calculate actual freed space
	_ = strings.TrimSpace(string(cacheDir))

	return nil
}
