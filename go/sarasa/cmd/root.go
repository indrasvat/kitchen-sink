package cmd

import (
	"fmt"
	"os"
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/spf13/cobra"

	"github.com/indrasvat/sarasa/internal/config"
	"github.com/indrasvat/sarasa/internal/logger"
	"github.com/indrasvat/sarasa/internal/ui"
)

var (
	cfgFile string
	verbose bool
	cfg     *config.Config
)

// rootCmd represents the base command when called without any subcommands.
var rootCmd = &cobra.Command{
	Use:   "sarasa",
	Short: "Automated global package manager upgrades",
	Long: `Sarasa automates global package upgrades for brew, npm, bun, and pipx
with scheduled background execution via launchd.

All operations target globally-installed packages only.`,
	PersistentPreRunE: func(_ *cobra.Command, _ []string) error {
		// Load config
		var err error
		if cfgFile != "" {
			cfg, err = config.LoadFrom(cfgFile)
		} else {
			cfg, err = config.Load()
		}
		if err != nil {
			return fmt.Errorf("failed to load config: %w", err)
		}

		// Initialize logger
		level := logger.ParseLevel(cfg.Logging.Level)
		if verbose {
			level = logger.ParseLevel("debug")
		}

		logCfg := logger.Config{
			Dir:           cfg.Logging.Dir,
			Level:         level,
			RetentionDays: cfg.Logging.RetentionDays,
		}

		if err := logger.Init(logCfg); err != nil {
			return fmt.Errorf("failed to initialize logger: %w", err)
		}

		return nil
	},
	PersistentPostRun: func(_ *cobra.Command, _ []string) {
		_ = logger.Close()
	},
}

// Execute adds all child commands to the root command and sets flags appropriately.
func Execute() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}

func init() {
	rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "", "config file (default is ~/.config/sarasa/config.toml)")
	rootCmd.PersistentFlags().BoolVarP(&verbose, "verbose", "v", false, "enable verbose output")

	// Set custom help function
	rootCmd.SetHelpFunc(styledHelp)
}

// GetConfig returns the loaded configuration.
func GetConfig() *config.Config {
	return cfg
}

// styledHelp renders a styled help output using lipgloss.
func styledHelp(cmd *cobra.Command, _ []string) {
	// Check if we should use colors
	mode := ui.DetectOutputMode()
	useColor := mode != ui.ModePlain

	// Styles
	headerStyle := lipgloss.NewStyle().Bold(true).Foreground(ui.ColorPrimary)
	titleStyle := lipgloss.NewStyle().Bold(true)
	cmdStyle := lipgloss.NewStyle().Foreground(ui.ColorPrimary)
	flagStyle := lipgloss.NewStyle().Foreground(lipgloss.AdaptiveColor{Light: "#0066CC", Dark: "#00BFFF"})
	descStyle := lipgloss.NewStyle().Foreground(lipgloss.AdaptiveColor{Light: "#666666", Dark: "#AAAAAA"})
	mutedStyle := lipgloss.NewStyle().Foreground(ui.ColorMuted)

	if !useColor {
		headerStyle = lipgloss.NewStyle()
		titleStyle = lipgloss.NewStyle()
		cmdStyle = lipgloss.NewStyle()
		flagStyle = lipgloss.NewStyle()
		descStyle = lipgloss.NewStyle()
		mutedStyle = lipgloss.NewStyle()
	}

	var b strings.Builder

	// Header with icon
	b.WriteString("\n")
	if useColor {
		b.WriteString(fmt.Sprintf("  %s %s\n", ui.IconDiamond, headerStyle.Render("SARASA")))
	} else {
		b.WriteString("  SARASA\n")
	}
	b.WriteString("\n")

	// Description
	b.WriteString(descStyle.Render("  Automated global package upgrades for:"))
	b.WriteString("\n")

	// Manager icons
	if useColor {
		managers := []struct {
			icon  string
			name  string
			color lipgloss.AdaptiveColor
		}{
			{ui.IconBrew, "brew", ui.ColorBrew},
			{ui.IconNPM, "npm", ui.ColorNPM},
			{ui.IconPipx, "pipx", ui.ColorPipx},
			{ui.IconBun, "bun", ui.ColorBun},
		}
		b.WriteString("  ")
		for i, m := range managers {
			style := lipgloss.NewStyle().Foreground(m.color)
			b.WriteString(fmt.Sprintf("%s %s", m.icon, style.Render(m.name)))
			if i < len(managers)-1 {
				b.WriteString(mutedStyle.Render("  ·  "))
			}
		}
		b.WriteString("\n")
	} else {
		b.WriteString("  brew · npm · pipx · bun\n")
	}
	b.WriteString("\n")

	// Usage
	b.WriteString(titleStyle.Render("  Usage:"))
	b.WriteString("\n")
	b.WriteString(fmt.Sprintf("    %s %s\n", cmdStyle.Render("sarasa"), mutedStyle.Render("[command]")))
	b.WriteString("\n")

	// Commands
	b.WriteString(titleStyle.Render("  Commands:"))
	b.WriteString("\n")

	commands := []struct {
		name string
		desc string
	}{
		{"status", "Check for outdated packages"},
		{"run", "Run package upgrades"},
		{"logs", "View upgrade logs"},
		{"schedule", "Manage scheduled upgrades"},
		{"version", "Print version information"},
	}

	for _, c := range commands {
		cmdName := cmdStyle.Render(fmt.Sprintf("%-12s", c.name))
		b.WriteString(fmt.Sprintf("    %s %s\n", cmdName, descStyle.Render(c.desc)))
	}
	b.WriteString("\n")

	// Flags
	b.WriteString(titleStyle.Render("  Flags:"))
	b.WriteString("\n")

	flags := []struct {
		flag string
		desc string
	}{
		{"-h, --help", "Show this help"},
		{"-v, --verbose", "Enable verbose output"},
		{"--config FILE", "Config file path"},
	}

	for _, f := range flags {
		flagName := flagStyle.Render(fmt.Sprintf("%-16s", f.flag))
		b.WriteString(fmt.Sprintf("    %s %s\n", flagName, descStyle.Render(f.desc)))
	}
	b.WriteString("\n")

	// Examples
	b.WriteString(titleStyle.Render("  Examples:"))
	b.WriteString("\n")

	examples := []struct {
		cmd  string
		desc string
	}{
		{"sarasa status", "Show outdated packages"},
		{"sarasa run --dry-run", "Preview upgrades without applying"},
		{"sarasa run", "Upgrade all outdated packages"},
		{"sarasa logs", "View upgrade history"},
		{"sarasa schedule enable", "Enable daily scheduled upgrades"},
	}

	for _, e := range examples {
		b.WriteString(fmt.Sprintf("    %s\n", cmdStyle.Render(e.cmd)))
		b.WriteString(fmt.Sprintf("      %s\n", mutedStyle.Render(e.desc)))
	}
	b.WriteString("\n")

	// Footer
	b.WriteString(mutedStyle.Render("  Use \"sarasa [command] --help\" for more information about a command."))
	b.WriteString("\n\n")

	fmt.Fprint(cmd.OutOrStdout(), b.String())
}
