package runengine

import (
	"context"
	"sync"
	"time"

	"github.com/indrasvat/sarasa/internal/logger"
	"github.com/indrasvat/sarasa/internal/manager"
)

// ConfigProvider provides per-manager configuration.
type ConfigProvider interface {
	GetSkipList(manager string) []string
}

// ManagerResult contains one manager's run outcome.
type ManagerResult struct {
	Name         string
	Available    bool
	Duration     time.Duration
	Upgraded     []manager.Package
	Failed       []manager.Package
	Skipped      []manager.Package
	Error        error
	CleanupError error
}

// Summary contains aggregate run counts.
type Summary struct {
	Upgraded      int
	Failed        int
	Skipped       int
	WouldUpgrade  int
	ManagerErrors int
}

// Output is the complete result of a run.
type Output struct {
	DryRun   bool
	Success  bool
	Duration time.Duration
	Summary  Summary
	Managers []ManagerResult
}

// Runner executes manager upgrades.
type Runner struct {
	DryRun         bool
	SkipCleanup    bool
	MaxParallel    int
	ConfigProvider ConfigProvider
}

// Run executes managers concurrently and returns results in input order.
func (r Runner) Run(ctx context.Context, managers []manager.Manager) Output {
	start := time.Now()
	output := Output{
		DryRun:   r.DryRun,
		Success:  true,
		Managers: make([]ManagerResult, len(managers)),
	}
	if len(managers) == 0 {
		output.Duration = time.Since(start)
		return output
	}

	parallelism := r.MaxParallel
	if parallelism <= 0 || parallelism > len(managers) {
		parallelism = len(managers)
	}

	sem := make(chan struct{}, parallelism)
	var wg sync.WaitGroup
	for i, mgr := range managers {
		i, mgr := i, mgr
		output.Managers[i] = ManagerResult{Name: mgr.Name(), Available: true}
		wg.Add(1)
		go func() {
			defer wg.Done()
			select {
			case sem <- struct{}{}:
				defer func() { <-sem }()
			case <-ctx.Done():
				result := ManagerResult{Name: mgr.Name(), Available: true, Error: ctx.Err()}
				output.Managers[i] = result
				return
			}

			result := r.runOne(ctx, mgr)
			output.Managers[i] = result
		}()
	}
	wg.Wait()
	if !r.DryRun && !r.SkipCleanup && ctx.Err() == nil {
		for i, mgr := range managers {
			if output.Managers[i].Error != nil {
				continue
			}
			if err := mgr.Cleanup(ctx); err != nil {
				output.Managers[i].CleanupError = err
			}
		}
	}

	output.Duration = time.Since(start)
	output.Summary = reduce(output.Managers, r.DryRun)
	output.Success = output.Summary.Failed == 0 && output.Summary.ManagerErrors == 0
	return output
}

func (r Runner) runOne(ctx context.Context, mgr manager.Manager) ManagerResult {
	result := ManagerResult{Name: mgr.Name(), Available: true}
	if r.ConfigProvider != nil {
		mgr.SetSkipList(r.ConfigProvider.GetSkipList(mgr.Name()))
	}
	logger.LogStart(mgr.Name())
	start := time.Now()
	upgradeResult, err := mgr.Upgrade(ctx, r.DryRun)
	result.Duration = time.Since(start)
	if err != nil {
		result.Error = err
		logger.LogComplete(mgr.Name(), 0, 1, result.Duration.Milliseconds())
		return result
	}
	if upgradeResult == nil {
		upgradeResult = &manager.UpgradeResult{}
	}

	result.Upgraded = upgradeResult.Upgraded
	result.Failed = upgradeResult.Failed
	result.Skipped = upgradeResult.Skipped

	logger.LogComplete(mgr.Name(), len(result.Upgraded), len(result.Failed), result.Duration.Milliseconds())
	return result
}

func reduce(results []ManagerResult, dryRun bool) Summary {
	var summary Summary
	for _, result := range results {
		if result.Error != nil {
			summary.ManagerErrors++
		}
		if dryRun {
			summary.WouldUpgrade += len(result.Skipped)
		} else {
			summary.Skipped += len(result.Skipped)
		}
		summary.Upgraded += len(result.Upgraded)
		summary.Failed += len(result.Failed)
		if result.CleanupError != nil {
			summary.ManagerErrors++
		}
	}
	return summary
}
