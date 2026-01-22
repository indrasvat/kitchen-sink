package manager

import (
	"context"
	"os/exec"
	"time"

	"github.com/indrasvat/sarasa/internal/logger"
)

func init() {
	Register("pipx", NewPipx)
}

// Pipx implements the Manager interface for pipx.
type Pipx struct {
	opts *Options
}

// NewPipx creates a new pipx manager.
func NewPipx(opts *Options) Manager {
	return &Pipx{opts: opts}
}

func (p *Pipx) Name() string {
	return "pipx"
}

func (p *Pipx) IsAvailable() bool {
	_, err := exec.LookPath("pipx")
	return err == nil
}

func (p *Pipx) SetSkipList(packages []string) {
	p.opts.SkipList = packages
}

func (p *Pipx) CheckOutdated(_ context.Context) ([]Package, error) {
	// pipx doesn't have a native "outdated" command
	// We return an empty list and let Upgrade handle everything
	// since pipx upgrade-all is idempotent
	return nil, nil
}

func (p *Pipx) Upgrade(ctx context.Context, dryRun bool) (*UpgradeResult, error) {
	log := logger.WithManager(p.Name())
	result := &UpgradeResult{}

	if dryRun {
		log.Info("Would run pipx upgrade-all", "action", "upgrade", "dry_run", true)
		return result, nil
	}

	logger.LogStart(p.Name())

	start := time.Now()
	cmd := exec.CommandContext(ctx, "pipx", "upgrade-all")
	output, err := cmd.CombinedOutput()
	duration := time.Since(start).Milliseconds()

	if err != nil {
		log.Error("pipx upgrade-all failed",
			"action", "upgrade",
			"error", err.Error(),
			"output", string(output),
			"duration_ms", duration,
		)
		return result, err
	}

	// pipx upgrade-all outputs text, not JSON
	// We log success without detailed package info
	log.Info("pipx upgrade-all completed",
		"action", "complete",
		"duration_ms", duration,
	)

	return result, nil
}

func (p *Pipx) Cleanup(_ context.Context) error {
	// pipx doesn't have a cleanup command
	return nil
}
