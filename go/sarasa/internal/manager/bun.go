package manager

import (
	"bufio"
	"context"
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

func (b *Bun) CheckOutdated(ctx context.Context) ([]Package, error) {
	// bun doesn't have a native outdated command for global packages
	// We list global packages and then check each one
	// bun pm ls -g outputs package names

	cmd := exec.CommandContext(ctx, "bun", "pm", "ls", "-g")
	output, err := cmd.Output()
	if err != nil {
		// No global packages or command failed - return empty list
		return []Package{}, nil //nolint:nilerr // intentional: empty list on error
	}

	var packages []Package
	scanner := bufio.NewScanner(strings.NewReader(string(output)))
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "/") {
			continue
		}

		// Parse package name and version (format varies)
		// Common formats: "package@version" or just "package"
		name := line
		version := ""
		if idx := strings.LastIndex(line, "@"); idx > 0 {
			name = line[:idx]
			version = line[idx+1:]
		}

		if b.opts.ShouldSkip(name) {
			continue
		}

		packages = append(packages, Package{
			Name:    name,
			Current: version,
			Latest:  "", // bun doesn't provide latest version info easily
		})
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
		log.Info("No global packages found", "action", "upgrade")
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

	// bun uses the same command for install and upgrade
	for _, pkg := range packages {
		if b.opts.ShouldSkip(pkg.Name) {
			logger.LogSkipped(b.Name(), pkg.Name, "in skip list")
			result.Skipped = append(result.Skipped, pkg)
			continue
		}

		start := time.Now()
		cmd := exec.CommandContext(ctx, "bun", "install", "-g", pkg.Name)
		err := cmd.Run()
		duration := time.Since(start).Milliseconds()

		if err != nil {
			logger.LogUpgradeError(b.Name(), pkg.Name, err, duration)
			result.Failed = append(result.Failed, pkg)
		} else {
			logger.LogUpgrade(b.Name(), pkg.Name, pkg.Current, pkg.Latest, duration)
			result.Upgraded = append(result.Upgraded, pkg)
		}
	}

	return result, nil
}

func (b *Bun) Cleanup(_ context.Context) error {
	// bun doesn't have a cleanup command for global packages
	return nil
}
