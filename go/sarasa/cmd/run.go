package cmd

import (
	"context"
	"fmt"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/spf13/cobra"

	"github.com/indrasvat/sarasa/internal/logger"
	"github.com/indrasvat/sarasa/internal/manager"
	runTUI "github.com/indrasvat/sarasa/internal/tui/run"
	"github.com/indrasvat/sarasa/internal/ui"
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
		fmt.Println()
		fmt.Printf("  %s %s\n\n", ui.StyleWarning.Render(ui.IconWarning), ui.StyleMuted.Render("No package managers available"))
		return nil
	}

	log.Info("Starting sarasa run",
		"managers", managerNames,
		"dry_run", runDryRun,
	)

	// Detect output mode
	mode := ui.DetectOutputMode()

	// Wrap config to implement ManagerConfigProvider interface
	cfgWrapper := &configWrapper{cfg: cfg}

	switch mode {
	case ui.ModeTUI:
		return runRunTUI(managers, opts, cfgWrapper)
	case ui.ModeStyled, ui.ModePlain:
		return runRunPlain(managers, opts, cfgWrapper, mode == ui.ModeStyled)
	}

	return nil
}

func runRunTUI(managers []manager.Manager, opts *manager.Options, cfg runTUI.ManagerConfigProvider) error {
	model := runTUI.New(managers, opts, cfg, runDryRun, runSkipCleanup)
	p := tea.NewProgram(model, tea.WithAltScreen())

	finalModel, err := p.Run()
	if err != nil {
		return err
	}

	// Log results
	log := logger.Get()
	m := finalModel.(runTUI.Model)
	for _, result := range m.GetResults() {
		upgraded := 0
		failed := 0
		for _, pkg := range result.Packages {
			if pkg.Status == "success" {
				upgraded++
			} else if pkg.Status == "failed" {
				failed++
			}
		}
		logger.LogComplete(result.Name, upgraded, failed, result.Duration.Milliseconds())
	}

	totalUpgraded, totalFailed, _, totalDuration := m.GetStats()
	log.Info("Sarasa run completed",
		"total_upgraded", totalUpgraded,
		"total_failed", totalFailed,
		"duration_ms", totalDuration.Milliseconds(),
	)

	return nil
}

func runRunPlain(managers []manager.Manager, opts *manager.Options, cfg runTUI.ManagerConfigProvider, styled bool) error {
	ctx := context.Background()
	log := logger.Get()

	// Color helper
	c := func(code, text string) string {
		if !styled {
			return text
		}
		return code + text + "\033[0m"
	}

	// ANSI codes
	const (
		bold          = "\033[1m"
		dim           = "\033[2m"
		red           = "\033[31m"
		green         = "\033[32m"
		yellow        = "\033[33m"
		blue          = "\033[34m"
		brightCyan    = "\033[96m"
		brightGreen   = "\033[92m"
		brightYellow  = "\033[93m"
		brightMagenta = "\033[95m"
		white         = "\033[37m"
	)

	managerColor := func(name string) string {
		switch name {
		case "brew":
			return yellow
		case "npm":
			return red
		case "pipx":
			return blue
		case "bun":
			return brightMagenta
		default:
			return brightCyan
		}
	}

	// Print header
	fmt.Println()
	if runDryRun {
		fmt.Printf("  %s %s\n", c(brightMagenta, ui.IconDiamond), c(bold+brightMagenta, "SARASA DRY RUN"))
	} else {
		fmt.Printf("  %s %s\n", c(brightCyan, ui.IconDiamond), c(bold+brightCyan, "SARASA UPGRADE"))
	}
	fmt.Println(c(dim, "  ─────────────────────────────────────────"))
	fmt.Println()

	// Run upgrades for each manager
	totalUpgraded := 0
	totalFailed := 0
	totalSkipped := 0
	overallStart := time.Now()

	for _, m := range managers {
		// Set skip list for this manager
		opts.SkipList = cfg.GetSkipList(m.Name())

		mColor := managerColor(m.Name())
		icon := ""
		if styled {
			icon = ui.ManagerIcon(m.Name()) + " "
		}

		// Manager header
		fmt.Printf("  %s%s\n", icon, c(bold+mColor, strings.ToUpper(m.Name())))

		logger.LogStart(m.Name())
		start := time.Now()

		// Run upgrade
		result, err := m.Upgrade(ctx, runDryRun)
		duration := time.Since(start)

		if err != nil {
			log.Error("Manager upgrade failed",
				"manager", m.Name(),
				"error", err.Error(),
			)
			fmt.Printf("    %s %s\n\n", c(red, ui.IconCross), c(red, err.Error()))
			continue
		}

		// Print results
		hasOutput := false

		if len(result.Upgraded) > 0 {
			hasOutput = true
			for _, pkg := range result.Upgraded {
				fmt.Printf("    %s %s  %s %s %s\n",
					c(green, ui.IconCheck),
					c(bold+white, pkg.Name),
					c(dim, pkg.Current),
					c(dim, ui.IconArrow),
					c(brightGreen, pkg.Latest),
				)
			}
		}

		if len(result.Failed) > 0 {
			hasOutput = true
			for _, pkg := range result.Failed {
				fmt.Printf("    %s %s  %s\n",
					c(red, ui.IconCross),
					c(bold+white, pkg.Name),
					c(red, "upgrade failed"),
				)
			}
		}

		if len(result.Skipped) > 0 && runDryRun {
			hasOutput = true
			for _, pkg := range result.Skipped {
				majorTag := ""
				if pkg.IsMajor {
					majorTag = " " + c(bold+brightYellow, "[MAJOR]")
				}
				fmt.Printf("    %s %s  %s %s %s%s\n",
					c(brightMagenta, ui.IconTriangle),
					c(bold+white, pkg.Name),
					c(dim, pkg.Current),
					c(dim, ui.IconArrow),
					c(brightMagenta, pkg.Latest),
					majorTag,
				)
			}
		}

		if !hasOutput {
			fmt.Printf("    %s %s\n", c(green, ui.IconCheck), c(green, "Already up to date"))
		}

		totalUpgraded += len(result.Upgraded)
		totalFailed += len(result.Failed)
		totalSkipped += len(result.Skipped)

		// Run cleanup
		if !runDryRun && !runSkipCleanup {
			if err := m.Cleanup(ctx); err != nil {
				log.Warn("Cleanup failed",
					"manager", m.Name(),
					"error", err.Error(),
				)
			}
		}

		logger.LogComplete(m.Name(), len(result.Upgraded), len(result.Failed), duration.Milliseconds())
		fmt.Println()
	}

	// Summary
	overallDuration := time.Since(overallStart)
	fmt.Println(c(dim, "  ─────────────────────────────────────────"))
	fmt.Println()

	// Build summary parts
	var summaryParts []string

	if runDryRun {
		if totalSkipped > 0 {
			summaryParts = append(summaryParts, c(brightMagenta, fmt.Sprintf("%d to upgrade", totalSkipped)))
		} else {
			summaryParts = append(summaryParts, c(green, "All up to date"))
		}
	} else {
		if totalUpgraded > 0 {
			summaryParts = append(summaryParts, c(green, fmt.Sprintf("%d upgraded", totalUpgraded)))
		}
		if totalFailed > 0 {
			summaryParts = append(summaryParts, c(red, fmt.Sprintf("%d failed", totalFailed)))
		}
		if totalUpgraded == 0 && totalFailed == 0 {
			summaryParts = append(summaryParts, c(green, "All up to date"))
		}
	}

	// Duration
	durationStr := formatDuration(overallDuration)
	summaryParts = append(summaryParts, c(dim, durationStr))

	// Print summary
	summaryIcon := ui.IconSparkle
	if totalFailed > 0 {
		summaryIcon = ui.IconFailed
	}
	fmt.Printf("  %s  %s\n", summaryIcon, strings.Join(summaryParts, c(dim, " · ")))

	if runDryRun && totalSkipped > 0 {
		fmt.Printf("     Run %s to apply upgrades\n", c(brightCyan+bold, "sarasa run"))
	}

	fmt.Println()

	return nil
}

// formatDuration formats a duration nicely
func formatDuration(d time.Duration) string {
	if d < time.Second {
		return fmt.Sprintf("%dms", d.Milliseconds())
	}
	if d < time.Minute {
		return fmt.Sprintf("%.1fs", d.Seconds())
	}
	minutes := int(d.Minutes())
	seconds := int(d.Seconds()) % 60
	return fmt.Sprintf("%dm %ds", minutes, seconds)
}

// configWrapper wraps the config to implement ManagerConfigProvider
type configWrapper struct {
	cfg interface {
		GetSkipList(managerName string) []string
	}
}

func (w *configWrapper) GetSkipList(managerName string) []string {
	return w.cfg.GetSkipList(managerName)
}
