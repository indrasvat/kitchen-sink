package cmd

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/spf13/cobra"

	"github.com/indrasvat/sarasa/internal/logger"
	"github.com/indrasvat/sarasa/internal/manager"
)

var (
	runManagers    string
	runDryRun      bool
	runNoMajor     bool
	runSkipCleanup bool
)

var runCmd = &cobra.Command{
	Use:   "run",
	Short: "Run package upgrades",
	Long: `Run package upgrades for all or specified package managers.

Examples:
  sarasa run                          # Run all available managers
  sarasa run --managers=brew,pipx     # Run specific managers
  sarasa run --dry-run                # Show what would be upgraded
  sarasa run --no-major               # Skip major version upgrades (npm)
  sarasa run --skip-cleanup           # Skip cleanup phase`,
	RunE: runRun,
}

func init() {
	rootCmd.AddCommand(runCmd)

	runCmd.Flags().StringVar(&runManagers, "managers", "", "comma-separated list of managers to run")
	runCmd.Flags().BoolVar(&runDryRun, "dry-run", false, "show what would be upgraded without making changes")
	runCmd.Flags().BoolVar(&runNoMajor, "no-major", false, "skip major version upgrades (npm only)")
	runCmd.Flags().BoolVar(&runSkipCleanup, "skip-cleanup", false, "skip cleanup phase")
}

func runRun(_ *cobra.Command, _ []string) error {
	ctx := context.Background()
	cfg := GetConfig()
	log := logger.Get()

	// Build manager options
	opts := &manager.Options{
		DryRun:      runDryRun,
		SkipMajor:   runNoMajor || cfg.NPM.SkipMajor,
		SkipCleanup: runSkipCleanup,
		Greedy:      cfg.Brew.Greedy,
	}

	// Determine which managers to run
	var managerNames []string
	switch {
	case runManagers != "":
		managerNames = strings.Split(runManagers, ",")
	case len(cfg.Managers) > 0:
		managerNames = cfg.Managers
	default:
		managerNames = manager.List()
	}

	// Get managers
	managers, err := manager.GetMultiple(managerNames, opts)
	if err != nil {
		return err
	}

	if len(managers) == 0 {
		fmt.Println("No package managers available")
		return nil
	}

	log.Info("Starting sarasa run",
		"managers", managerNames,
		"dry_run", runDryRun,
	)

	// Run upgrades for each manager
	totalUpgraded := 0
	totalFailed := 0
	overallStart := time.Now()

	for _, m := range managers {
		// Set skip list for this manager
		opts.SkipList = cfg.GetSkipList(m.Name())

		fmt.Printf("\n=== %s ===\n", m.Name())
		logger.LogStart(m.Name())

		start := time.Now()

		// Run upgrade
		result, err := m.Upgrade(ctx, runDryRun)
		if err != nil {
			log.Error("Manager upgrade failed",
				"manager", m.Name(),
				"error", err.Error(),
			)
			fmt.Printf("Error: %v\n", err)
			continue
		}

		// Print results
		if len(result.Upgraded) > 0 {
			fmt.Printf("Upgraded:\n")
			for _, pkg := range result.Upgraded {
				fmt.Printf("  %s: %s -> %s\n", pkg.Name, pkg.Current, pkg.Latest)
			}
		}

		if len(result.Failed) > 0 {
			fmt.Printf("Failed:\n")
			for _, pkg := range result.Failed {
				fmt.Printf("  %s\n", pkg.Name)
			}
		}

		if len(result.Skipped) > 0 && runDryRun {
			fmt.Printf("Would upgrade:\n")
			for _, pkg := range result.Skipped {
				fmt.Printf("  %s: %s -> %s\n", pkg.Name, pkg.Current, pkg.Latest)
			}
		}

		totalUpgraded += len(result.Upgraded)
		totalFailed += len(result.Failed)

		// Run cleanup
		if !runDryRun && !runSkipCleanup {
			if err := m.Cleanup(ctx); err != nil {
				log.Warn("Cleanup failed",
					"manager", m.Name(),
					"error", err.Error(),
				)
			}
		}

		duration := time.Since(start).Milliseconds()
		logger.LogComplete(m.Name(), len(result.Upgraded), len(result.Failed), duration)
	}

	// Summary
	overallDuration := time.Since(overallStart)
	fmt.Printf("\n=== Summary ===\n")
	fmt.Printf("Upgraded: %d packages\n", totalUpgraded)
	fmt.Printf("Failed: %d packages\n", totalFailed)
	fmt.Printf("Duration: %s\n", overallDuration.Round(time.Second))

	return nil
}
