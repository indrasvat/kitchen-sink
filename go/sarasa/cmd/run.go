package cmd

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/spf13/cobra"

	"github.com/indrasvat/sarasa/internal/logger"
	"github.com/indrasvat/sarasa/internal/manager"
	"github.com/indrasvat/sarasa/internal/signal"
	runTUI "github.com/indrasvat/sarasa/internal/tui/run"
	"github.com/indrasvat/sarasa/internal/ui"
)

var (
	runManagers    string
	runDryRun      bool
	runNoMajor     bool
	runSkipCleanup bool
	runJSON        bool
)

var runCmd = &cobra.Command{
	Use:   "run",
	Short: "Run package upgrades",
	Long: `Run package upgrades for all or specified package managers.

Examples:
  sarasa run                          # Run all available managers
  sarasa run --managers=brew,pipx     # Run specific managers
  sarasa run --dry-run                # Show what would be upgraded
  sarasa run --json                   # Output machine-readable JSON
  sarasa run --no-major               # Skip major version upgrades (npm)
	sarasa run --skip-cleanup           # Skip cleanup phase`,
	RunE:         runRun,
	SilenceUsage: true,
}

func init() {
	rootCmd.AddCommand(runCmd)

	runCmd.Flags().StringVar(&runManagers, "managers", "", "comma-separated list of managers to run")
	runCmd.Flags().BoolVar(&runDryRun, "dry-run", false, "show what would be upgraded without making changes")
	runCmd.Flags().BoolVar(&runNoMajor, "no-major", false, "skip major version upgrades (npm only)")
	runCmd.Flags().BoolVar(&runSkipCleanup, "skip-cleanup", false, "skip cleanup phase")
	runCmd.Flags().BoolVar(&runJSON, "json", false, "output as JSON")
}

// RunOutput is the JSON result envelope for sarasa run.
type RunOutput struct {
	DryRun     bool               `json:"dry_run"`
	Success    bool               `json:"success"`
	DurationMs int64              `json:"duration_ms"`
	Summary    RunSummary         `json:"summary"`
	Managers   []RunManagerResult `json:"managers"`
}

// RunSummary contains aggregate run counts.
type RunSummary struct {
	Upgraded      int `json:"upgraded"`
	Failed        int `json:"failed"`
	Skipped       int `json:"skipped"`
	WouldUpgrade  int `json:"would_upgrade,omitempty"`
	ManagerErrors int `json:"manager_errors,omitempty"`
}

// RunManagerResult contains one manager's run outcome.
type RunManagerResult struct {
	Name         string            `json:"name"`
	Available    bool              `json:"available"`
	DurationMs   int64             `json:"duration_ms,omitempty"`
	Upgraded     []manager.Package `json:"upgraded,omitempty"`
	Failed       []manager.Package `json:"failed,omitempty"`
	Skipped      []manager.Package `json:"skipped,omitempty"`
	WouldUpgrade []manager.Package `json:"would_upgrade,omitempty"`
	Error        string            `json:"error,omitempty"`
	CleanupError string            `json:"cleanup_error,omitempty"`
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
		Config:      cfg,
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

	log.Info("Starting sarasa run",
		"managers", managerNames,
		"dry_run", runDryRun,
	)

	// Wrap config to implement ManagerConfigProvider interface
	cfgWrapper := &configWrapper{cfg: cfg}

	// JSON output is always non-interactive, even when stdout is a TTY.
	if runJSON {
		return runRunJSON(managerNames, opts, cfgWrapper, os.Stdout)
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

	// Detect output mode
	mode := ui.DetectOutputMode()

	switch mode {
	case ui.ModeTUI:
		return runRunTUI(managers, opts, cfgWrapper)
	case ui.ModeStyled, ui.ModePlain:
		return runRunPlain(managers, opts, cfgWrapper, mode == ui.ModeStyled)
	}

	return nil
}

func runRunJSON(managerNames []string, opts *manager.Options, cfg *configWrapper, writer io.Writer) error {
	ctx, cancel := signal.NotifyContext(context.Background())
	defer cancel()

	output := RunOutput{
		DryRun:   opts.DryRun,
		Success:  true,
		Managers: make([]RunManagerResult, 0, len(managerNames)),
	}
	overallStart := time.Now()

	for _, name := range managerNames {
		result := RunManagerResult{Name: name}

		m, err := manager.Get(name, opts)
		if err != nil {
			result.Error = err.Error()
			output.Success = false
			output.Summary.ManagerErrors++
			output.Managers = append(output.Managers, result)
			continue
		}

		result.Available = m.IsAvailable()
		if !result.Available {
			output.Managers = append(output.Managers, result)
			continue
		}

		opts.SkipList = cfg.GetSkipList(name)
		logger.LogStart(m.Name())
		start := time.Now()
		upgradeResult, err := m.Upgrade(ctx, opts.DryRun)
		result.DurationMs = time.Since(start).Milliseconds()
		if err != nil {
			result.Error = err.Error()
			output.Success = false
			output.Summary.ManagerErrors++
			logger.LogComplete(m.Name(), 0, 1, result.DurationMs)
			output.Managers = append(output.Managers, result)
			continue
		}
		if upgradeResult == nil {
			upgradeResult = &manager.UpgradeResult{}
		}

		result.Upgraded = upgradeResult.Upgraded
		result.Failed = upgradeResult.Failed
		if opts.DryRun {
			result.WouldUpgrade = upgradeResult.Skipped
			output.Summary.WouldUpgrade += len(upgradeResult.Skipped)
		} else {
			result.Skipped = upgradeResult.Skipped
			output.Summary.Skipped += len(upgradeResult.Skipped)
		}
		output.Summary.Upgraded += len(upgradeResult.Upgraded)
		output.Summary.Failed += len(upgradeResult.Failed)
		if len(upgradeResult.Failed) > 0 {
			output.Success = false
		}

		if !opts.DryRun && !opts.SkipCleanup {
			if err := m.Cleanup(ctx); err != nil {
				result.CleanupError = err.Error()
				output.Success = false
				output.Summary.ManagerErrors++
			}
		}

		logger.LogComplete(m.Name(), len(upgradeResult.Upgraded), len(upgradeResult.Failed), result.DurationMs)
		output.Managers = append(output.Managers, result)
	}

	output.DurationMs = time.Since(overallStart).Milliseconds()
	data, err := json.MarshalIndent(output, "", "  ")
	if err != nil {
		return err
	}
	if _, err := fmt.Fprintln(writer, string(data)); err != nil {
		return err
	}
	if !output.Success {
		return fmt.Errorf("sarasa run completed with failures")
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
			switch pkg.Status {
			case "success":
				upgraded++
			case "failed":
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

//nolint:gocyclo // plain-text renderer with many formatting conditionals
func runRunPlain(managers []manager.Manager, opts *manager.Options, cfg runTUI.ManagerConfigProvider, styled bool) error {
	ctx, cancel := signal.NotifyContext(context.Background())
	defer cancel()
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
		cyan          = "\033[36m"
		brightCyan    = "\033[96m"
		brightGreen   = "\033[92m"
		brightYellow  = "\033[93m"
		brightMagenta = "\033[95m"
		white         = "\033[37m"
	)

	managerColor := func(name string) string {
		switch name {
		case manager.ManagerBrew:
			return yellow
		case manager.ManagerNPM:
			return red
		case manager.ManagerPipx:
			return blue
		case manager.ManagerBun:
			return brightMagenta
		case manager.ManagerSkills:
			return cyan
		case manager.ManagerCustom:
			return brightCyan
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
		// Check for cancellation
		if ctx.Err() != nil {
			fmt.Printf("\n  %s %s\n\n", c(yellow, ui.IconWarning), c(yellow, "Interrupted"))
			break
		}

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
			totalFailed++
			continue
		}

		// Print results
		hasOutput := false

		if len(result.Upgraded) > 0 {
			hasOutput = true
			for _, pkg := range result.Upgraded {
				methodTag := ""
				if pkg.Method != "" {
					methodTag = " " + c(dim, "· "+pkg.Method)
				}
				fmt.Printf("    %s %s  %s %s %s%s\n",
					c(green, ui.IconCheck),
					c(bold+white, pkg.Name),
					c(dim, pkg.Current),
					c(dim, ui.IconArrow),
					c(brightGreen, pkg.Latest),
					methodTag,
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
				methodTag := ""
				if pkg.Method != "" {
					methodTag = " " + c(dim, "· "+pkg.Method)
				}
				fmt.Printf("    %s %s  %s %s %s%s%s\n",
					c(brightMagenta, ui.IconTriangle),
					c(bold+white, pkg.Name),
					c(dim, pkg.Current),
					c(dim, ui.IconArrow),
					c(brightMagenta, pkg.Latest),
					majorTag,
					methodTag,
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
		if totalFailed > 0 {
			summaryParts = append(summaryParts, c(red, fmt.Sprintf("%d failed", totalFailed)))
		}
		if totalSkipped > 0 {
			summaryParts = append(summaryParts, c(brightMagenta, fmt.Sprintf("%d to upgrade", totalSkipped)))
		}
		if totalFailed == 0 && totalSkipped == 0 {
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
