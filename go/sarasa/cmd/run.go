package cmd

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/spf13/cobra"

	"github.com/indrasvat/sarasa/internal/logger"
	"github.com/indrasvat/sarasa/internal/manager"
	"github.com/indrasvat/sarasa/internal/runengine"
	"github.com/indrasvat/sarasa/internal/runlock"
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
	lock, err := runlock.Acquire()
	if err != nil {
		if errors.Is(err, runlock.ErrAlreadyRunning) {
			return runlock.ErrAlreadyRunning
		}
		return fmt.Errorf("failed to acquire run lock: %w", err)
	}
	defer func() { _ = lock.Close() }()

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
		return runRunPlain(managers, cfgWrapper, mode == ui.ModeStyled)
	}

	return nil
}

func runRunJSON(managerNames []string, opts *manager.Options, cfg *configWrapper, writer io.Writer) error {
	ctx, cancel := signal.NotifyContext(context.Background())
	defer cancel()

	output := RunOutput{
		DryRun:   opts.DryRun,
		Success:  true,
		Managers: make([]RunManagerResult, len(managerNames)),
	}
	managers := make([]manager.Manager, 0, len(managerNames))
	managerIndexes := make([]int, 0, len(managerNames))
	for i, name := range managerNames {
		m, err := manager.Get(name, opts.CloneWithSkipList(cfg.GetSkipList(name)))
		if err != nil {
			result := RunManagerResult{Name: name, Error: err.Error()}
			output.Success = false
			output.Summary.ManagerErrors++
			output.Managers[i] = result
			continue
		}
		if !m.IsAvailable() {
			output.Managers[i] = RunManagerResult{Name: name, Available: false}
			continue
		}
		managers = append(managers, m)
		managerIndexes = append(managerIndexes, i)
	}

	runOutput := runengine.Runner{
		DryRun:         opts.DryRun,
		SkipCleanup:    opts.SkipCleanup,
		ConfigProvider: cfg,
	}.Run(ctx, managers)
	output.DurationMs = runOutput.Duration.Milliseconds()
	output.Success = output.Success && runOutput.Success
	output.Summary.Upgraded += runOutput.Summary.Upgraded
	output.Summary.Failed += runOutput.Summary.Failed
	output.Summary.Skipped += runOutput.Summary.Skipped
	output.Summary.WouldUpgrade += runOutput.Summary.WouldUpgrade
	output.Summary.ManagerErrors += runOutput.Summary.ManagerErrors
	for i, result := range toRunManagerResults(runOutput, opts.DryRun) {
		output.Managers[managerIndexes[i]] = result
	}

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

func toRunManagerResults(output runengine.Output, dryRun bool) []RunManagerResult {
	results := make([]RunManagerResult, 0, len(output.Managers))
	for _, managerResult := range output.Managers {
		result := RunManagerResult{
			Name:       managerResult.Name,
			Available:  managerResult.Available,
			DurationMs: managerResult.Duration.Milliseconds(),
			Upgraded:   managerResult.Upgraded,
			Failed:     managerResult.Failed,
		}
		if dryRun {
			result.WouldUpgrade = managerResult.Skipped
		} else {
			result.Skipped = managerResult.Skipped
		}
		if managerResult.Error != nil {
			result.Error = managerResult.Error.Error()
		}
		if managerResult.CleanupError != nil {
			result.CleanupError = managerResult.CleanupError.Error()
		}
		results = append(results, result)
	}
	return results
}

//nolint:gocyclo // plain-text renderer with many formatting conditionals
func runRunPlain(managers []manager.Manager, cfg runTUI.ManagerConfigProvider, styled bool) error {
	ctx, cancel := signal.NotifyContext(context.Background())
	defer cancel()

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

	runOutput := runengine.Runner{
		DryRun:         runDryRun,
		SkipCleanup:    runSkipCleanup,
		ConfigProvider: cfg,
	}.Run(ctx, managers)

	for _, result := range runOutput.Managers {
		mColor := managerColor(result.Name)
		icon := ""
		if styled {
			icon = ui.ManagerIcon(result.Name) + " "
		}

		// Manager header
		fmt.Printf("  %s%s\n", icon, c(bold+mColor, strings.ToUpper(result.Name)))

		if result.Error != nil {
			fmt.Printf("    %s %s\n\n", c(red, ui.IconCross), c(red, result.Error.Error()))
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

		if len(result.Skipped) > 0 {
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
				reasonTag := ""
				if pkg.SkipReason != "" {
					reasonTag = " " + c(dim, "· "+pkg.SkipReason)
				}
				label := pkg.Latest
				if !runDryRun {
					label = "skipped"
				}
				fmt.Printf("    %s %s  %s %s %s%s%s%s\n",
					c(brightMagenta, ui.IconTriangle),
					c(bold+white, pkg.Name),
					c(dim, pkg.Current),
					c(dim, ui.IconArrow),
					c(brightMagenta, label),
					majorTag,
					methodTag,
					reasonTag,
				)
			}
		}

		if result.CleanupError != nil {
			hasOutput = true
			fmt.Printf("    %s %s\n",
				c(yellow, ui.IconWarning),
				c(yellow, "cleanup failed: "+result.CleanupError.Error()),
			)
		}

		if !hasOutput {
			fmt.Printf("    %s %s\n", c(green, ui.IconCheck), c(green, "Already up to date"))
		}

		fmt.Println()
	}

	// Summary
	fmt.Println(c(dim, "  ─────────────────────────────────────────"))
	fmt.Println()

	// Build summary parts
	var summaryParts []string

	if runDryRun {
		if runOutput.Summary.Failed > 0 {
			summaryParts = append(summaryParts, c(red, fmt.Sprintf("%d failed", runOutput.Summary.Failed)))
		}
		if runOutput.Summary.WouldUpgrade > 0 {
			summaryParts = append(summaryParts, c(brightMagenta, fmt.Sprintf("%d to upgrade", runOutput.Summary.WouldUpgrade)))
		}
		if runOutput.Summary.Failed == 0 && runOutput.Summary.WouldUpgrade == 0 {
			summaryParts = append(summaryParts, c(green, "All up to date"))
		}
	} else {
		if runOutput.Summary.Upgraded > 0 {
			summaryParts = append(summaryParts, c(green, fmt.Sprintf("%d upgraded", runOutput.Summary.Upgraded)))
		}
		if runOutput.Summary.Failed > 0 || runOutput.Summary.ManagerErrors > 0 {
			summaryParts = append(summaryParts, c(red, fmt.Sprintf("%d failed", runOutput.Summary.Failed+runOutput.Summary.ManagerErrors)))
		}
		if runOutput.Summary.Skipped > 0 {
			summaryParts = append(summaryParts, c(brightMagenta, fmt.Sprintf("%d skipped", runOutput.Summary.Skipped)))
		}
		if runOutput.Summary.Upgraded == 0 && runOutput.Summary.Failed == 0 && runOutput.Summary.ManagerErrors == 0 && runOutput.Summary.Skipped == 0 {
			summaryParts = append(summaryParts, c(green, "All up to date"))
		}
	}

	// Duration
	durationStr := formatDuration(runOutput.Duration)
	summaryParts = append(summaryParts, c(dim, durationStr))

	// Print summary
	summaryIcon := ui.IconSparkle
	if runOutput.Summary.Failed > 0 || runOutput.Summary.ManagerErrors > 0 {
		summaryIcon = ui.IconFailed
	}
	fmt.Printf("  %s  %s\n", summaryIcon, strings.Join(summaryParts, c(dim, " · ")))

	if runDryRun && runOutput.Summary.WouldUpgrade > 0 {
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
