package cmd

import (
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/spf13/cobra"

	"github.com/indrasvat/sarasa/internal/config"
	"github.com/indrasvat/sarasa/internal/manager"
	"github.com/indrasvat/sarasa/internal/scheduler"
	"github.com/indrasvat/sarasa/internal/tui/wizard"
	"github.com/indrasvat/sarasa/internal/ui"
)

var (
	forceInit  bool
	dryRunInit bool
)

var initCmd = &cobra.Command{
	Use:   "init",
	Short: "Set up sarasa on this machine",
	Long: `Interactive setup wizard for sarasa.

Detects available package managers, asks about schedule preferences,
and generates ~/.config/sarasa/config.toml.

Examples:
  sarasa init                         # Interactive setup
  sarasa init --force                 # Overwrite existing config
  sarasa init --dry-run               # Preview without writing`,
	RunE: runInit,
}

func init() {
	rootCmd.AddCommand(initCmd)
	initCmd.Flags().BoolVar(&forceInit, "force", false, "overwrite existing config")
	initCmd.Flags().BoolVar(&dryRunInit, "dry-run", false, "preview config without writing")
}

func runInit(_ *cobra.Command, _ []string) error {
	if config.Exists() && !forceInit {
		fmt.Printf("  Config already exists: %s\n", config.ConfigPath())
		fmt.Println("  Run 'sarasa init --force' to reconfigure.")
		return nil
	}

	// Detect available managers
	opts := &manager.Options{}
	available := manager.Available(opts)
	var availNames []string
	for _, m := range available {
		availNames = append(availNames, m.Name())
	}

	// Non-interactive fallback
	if !ui.IsTTY() {
		return runInitNonInteractive(availNames)
	}

	// Run TUI wizard
	m := wizard.New(availNames)
	p := tea.NewProgram(m)
	finalModel, err := p.Run()
	if err != nil {
		return fmt.Errorf("init wizard failed: %w", err)
	}

	result := finalModel.(wizard.Model).GetResult()
	if result.Aborted {
		fmt.Println("  Init cancelled.")
		return nil
	}

	return applyInitResult(result)
}

func runInitNonInteractive(availNames []string) error {
	cfg := config.DefaultConfig()
	if len(availNames) > 0 {
		cfg.Managers = availNames
	}

	if dryRunInit {
		fmt.Println("[dry-run] Would write config to", config.ConfigPath())
		fmt.Printf("[dry-run] Managers: %v\n", cfg.Managers)
		fmt.Printf("[dry-run] Schedule: %v\n", cfg.Schedule.Times)
		return nil
	}

	if err := config.Save(cfg); err != nil {
		return fmt.Errorf("failed to save config: %w", err)
	}

	fmt.Printf("Config written to %s\n", config.ConfigPath())
	fmt.Printf("Managers: %v\n", cfg.Managers)
	fmt.Println("Run 'sarasa init' interactively to customize schedule.")
	return nil
}

func applyInitResult(result wizard.Result) error {
	cfg := config.DefaultConfig()
	cfg.Managers = result.Managers

	if result.Schedule.Times != nil {
		cfg.Schedule.Times = result.Schedule.Times
	} else {
		cfg.Schedule.Times = nil
	}

	fmt.Println()

	if dryRunInit {
		fmt.Printf("  %s [dry-run] Would write config to %s\n", ui.IconDot, config.ConfigPath())
		fmt.Printf("  %s [dry-run] Managers: %v\n", ui.IconDot, cfg.Managers)
		if result.Schedule.Times != nil {
			fmt.Printf("  %s [dry-run] Schedule: %s\n", ui.IconDot, result.Schedule.Label)
			fmt.Printf("  %s [dry-run] Would install launchd agent\n", ui.IconDot)
		} else {
			fmt.Printf("  %s [dry-run] No schedule\n", ui.IconDot)
		}
		fmt.Println()
		return nil
	}

	if err := config.Save(cfg); err != nil {
		return fmt.Errorf("failed to save config: %w", err)
	}

	fmt.Printf("  %s Config written to %s\n", ui.IconCheck, config.ConfigPath())
	fmt.Printf("  %s Managers: %v\n", ui.IconCheck, cfg.Managers)

	if result.Schedule.Times != nil {
		fmt.Printf("  %s Schedule: %s\n", ui.IconCheck, result.Schedule.Label)

		// Install launchd agent
		times, err := scheduler.ParseTimes(cfg.Schedule.Times)
		if err != nil {
			return fmt.Errorf("invalid schedule times: %w", err)
		}

		binaryPath, _ := os.Executable()
		launchdCfg := &scheduler.Config{
			Label:      scheduler.LaunchAgentLabel,
			BinaryPath: binaryPath,
			LogDir:     cfg.Logging.Dir,
			Times:      times,
		}

		if err := scheduler.Install(launchdCfg); err != nil {
			fmt.Printf("  %s Failed to install launchd agent: %v\n", ui.IconWarning, err)
			fmt.Println("    Run 'sarasa schedule install' manually.")
		} else {
			fmt.Printf("  %s Launchd agent installed\n", ui.IconCheck)
		}
	} else {
		fmt.Printf("  %s No schedule (run manually with 'sarasa run')\n", ui.IconDot)
	}

	fmt.Println()
	return nil
}
