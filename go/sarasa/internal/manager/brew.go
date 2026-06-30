package manager

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/indrasvat/sarasa/internal/jsonutil"
	"github.com/indrasvat/sarasa/internal/logger"
	"github.com/indrasvat/sarasa/internal/process"
)

func init() {
	Register("brew", NewBrew)
}

// Brew implements the Manager interface for Homebrew.
type Brew struct {
	opts *Options
}

const (
	brewMethodFormula = "formula"
	brewMethodCask    = "cask"
)

var brewAppDir = "/Applications"

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
	_, err := process.LookPath("brew")
	return err == nil
}

func (b *Brew) SetSkipList(packages []string) {
	b.opts.SkipList = packages
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
	brewPath, err := process.LookPath("brew")
	if err != nil {
		return nil, err
	}

	// First run brew update
	updateCmd := exec.CommandContext(ctx, brewPath, "update")
	process.Configure(updateCmd, brewEnv())
	if err := updateCmd.Run(); err != nil {
		return nil, fmt.Errorf("brew update failed: %w", err)
	}

	// Get outdated packages
	args := []string{"outdated", "--json=v2"}
	if b.opts.Greedy {
		args = append(args, "--greedy")
	}

	cmd := exec.CommandContext(ctx, brewPath, args...)
	process.Configure(cmd, brewEnv())
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
			Method:  brewMethodFormula,
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
			Method:  brewMethodCask,
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
		if reason := b.deferReason(ctx, pkg); reason != "" {
			pkg.SkipReason = reason
			logger.LogSkipped(b.Name(), pkg.Name, reason)
			result.Skipped = append(result.Skipped, pkg)
			continue
		}

		start := time.Now()
		args := append([]string{"upgrade"}, brewKindArg(pkg)...)
		args = append(args, pkg.Name)
		cmd := exec.CommandContext(ctx, "brew", args...)
		if brewPath, err := process.LookPath("brew"); err == nil {
			cmd = exec.CommandContext(ctx, brewPath, args...)
		}
		process.Configure(cmd, brewEnv())
		output, err := cmd.CombinedOutput()
		duration := time.Since(start).Milliseconds()

		if err != nil {
			if reason := brewDeferredReason(pkg, string(output)); reason != "" {
				log.Warn("brew upgrade deferred",
					"package", pkg.Name,
					"reason", reason,
					"output", string(output),
				)
				pkg.SkipReason = reason
				logger.LogSkipped(b.Name(), pkg.Name, reason)
				result.Skipped = append(result.Skipped, pkg)
				continue
			}
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
		newVersion, verifyErr := b.getInstalledVersion(ctx, pkg)
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
func (b *Brew) getInstalledVersion(ctx context.Context, pkg Package) (string, error) {
	brewPath, err := process.LookPath("brew")
	if err != nil {
		return "", err
	}
	args := append([]string{"info", "--json=v2"}, brewKindArg(pkg)...)
	args = append(args, pkg.Name)
	cmd := exec.CommandContext(ctx, brewPath, args...)
	process.Configure(cmd, brewEnv())
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
	brewPath, err := process.LookPath("brew")
	if err != nil {
		return err
	}
	duCmd := exec.CommandContext(ctx, brewPath, "--cache")
	process.Configure(duCmd, brewEnv())
	cacheDir, err := duCmd.Output()
	if err != nil {
		return fmt.Errorf("failed to get cache dir: %w", err)
	}

	// Run cleanup
	cleanupCmd := exec.CommandContext(ctx, brewPath, "cleanup")
	process.Configure(cleanupCmd, brewEnv())
	if err := cleanupCmd.Run(); err != nil {
		return fmt.Errorf("brew cleanup failed: %w", err)
	}

	// Run autoremove
	autoremoveCmd := exec.CommandContext(ctx, brewPath, "autoremove")
	process.Configure(autoremoveCmd, brewEnv())
	if err := autoremoveCmd.Run(); err != nil {
		log.Warn("brew autoremove failed", "error", err.Error())
	}

	// Estimate freed space (simplified)
	logger.LogCleanup(b.Name(), 0) // Would need to calculate actual freed space
	_ = strings.TrimSpace(string(cacheDir))

	return nil
}

func brewEnv() map[string]string {
	return map[string]string{
		"HOMEBREW_NO_ASK":       "1",
		"HOMEBREW_NO_ENV_HINTS": "1",
	}
}

func (b *Brew) deferReason(ctx context.Context, pkg Package) string {
	if pkg.Method != brewMethodCask {
		return ""
	}
	targetDirs, err := b.caskAppTargetDirs(ctx, pkg.Name)
	if err != nil {
		if !dirWritable(brewAppDir) {
			return "cask app target requires admin/write access"
		}
		return ""
	}
	for _, targetDir := range targetDirs {
		if !dirWritable(targetDir) {
			return "cask app target requires admin/write access"
		}
	}
	return ""
}

func (b *Brew) caskAppTargetDirs(ctx context.Context, name string) ([]string, error) {
	brewPath, err := process.LookPath("brew")
	if err != nil {
		return nil, err
	}
	cmd := exec.CommandContext(ctx, brewPath, "info", "--json=v2", "--cask", name)
	process.Configure(cmd, brewEnv())
	output, err := cmd.Output()
	if err != nil {
		return nil, err
	}

	var result struct {
		Casks []struct {
			Artifacts []map[string]json.RawMessage `json:"artifacts"`
		} `json:"casks"`
	}
	if err := jsonutil.Parse("brew", "info", output, &result); err != nil {
		return nil, err
	}

	var targetDirs []string
	for _, cask := range result.Casks {
		for _, artifact := range cask.Artifacts {
			if _, ok := artifact["app"]; !ok {
				continue
			}
			targetDir := brewAppDir
			if targetRaw, ok := artifact["target"]; ok {
				var target string
				if err := json.Unmarshal(targetRaw, &target); err == nil && target != "" {
					targetDir = caskTargetDir(target)
				}
			}
			if appRaw, ok := artifact["app"]; ok {
				if nestedTarget := nestedAppTarget(appRaw); nestedTarget != "" {
					targetDir = caskTargetDir(nestedTarget)
				}
			}
			targetDirs = append(targetDirs, targetDir)
		}
	}
	return targetDirs, nil
}

func brewKindArg(pkg Package) []string {
	switch pkg.Method {
	case brewMethodFormula:
		return []string{"--formula"}
	case brewMethodCask:
		return []string{"--cask"}
	default:
		return nil
	}
}

func brewDeferredReason(pkg Package, output string) string {
	if pkg.Method != brewMethodCask {
		return ""
	}
	text := strings.ToLower(output)
	switch {
	case strings.Contains(text, "sudo: a terminal is required") ||
		strings.Contains(text, "sudo: a password is required") ||
		strings.Contains(text, "which may request your password"):
		return "requires sudo/admin credentials"
	case strings.Contains(text, "there is already an app at"):
		return "requires manual cask app cleanup or admin lease"
	case strings.Contains(text, "refusing to load formula") && strings.Contains(text, "untrusted tap"):
		return "requires explicit brew tap trust"
	default:
		return ""
	}
}

func dirWritable(path string) bool {
	file, err := os.CreateTemp(path, ".sarasa-write-test-*")
	if err != nil {
		return false
	}
	name := file.Name()
	_ = file.Close()
	_ = os.Remove(name)
	return true
}

func expandHomePath(path string) string {
	if path == "~" {
		homeDir, _ := os.UserHomeDir()
		return homeDir
	}
	if strings.HasPrefix(path, "~/") {
		homeDir, _ := os.UserHomeDir()
		return filepath.Join(homeDir, path[2:])
	}
	return path
}

func caskTargetDir(target string) string {
	target = expandHomePath(target)
	if filepath.IsAbs(target) {
		return filepath.Dir(target)
	}
	return brewAppDir
}

func nestedAppTarget(raw json.RawMessage) string {
	var values []json.RawMessage
	if err := json.Unmarshal(raw, &values); err != nil {
		return ""
	}
	for _, value := range values {
		var options map[string]string
		if err := json.Unmarshal(value, &options); err != nil {
			continue
		}
		if target := strings.TrimSpace(options["target"]); target != "" {
			return target
		}
	}
	return ""
}
