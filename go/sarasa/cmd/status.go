package cmd

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/spf13/cobra"

	"github.com/indrasvat/sarasa/internal/manager"
	statusTUI "github.com/indrasvat/sarasa/internal/tui/status"
	"github.com/indrasvat/sarasa/internal/ui"
)

var (
	statusManagers string
	statusJSON     bool
)

var statusCmd = &cobra.Command{
	Use:   "status",
	Short: "Check for outdated packages",
	Long: `Check for outdated packages and optionally upgrade them.

In interactive mode, press 'u' to upgrade outdated packages directly.

Examples:
  sarasa status                       # Check all managers (press u to upgrade)
  sarasa status --managers=brew       # Check specific manager
  sarasa status --json                # Output as JSON`,
	RunE: runStatus,
}

func init() {
	rootCmd.AddCommand(statusCmd)

	statusCmd.Flags().StringVar(&statusManagers, "managers", "", "comma-separated list of managers to check")
	statusCmd.Flags().BoolVar(&statusJSON, "json", false, "output as JSON")
}

// StatusOutput represents the JSON output for status.
type StatusOutput struct {
	Managers []ManagerStatus `json:"managers"`
}

// ManagerStatus represents the status of a single manager.
type ManagerStatus struct {
	Name      string            `json:"name"`
	Available bool              `json:"available"`
	Outdated  []manager.Package `json:"outdated,omitempty"`
	Error     string            `json:"error,omitempty"`
}

func runStatus(_ *cobra.Command, _ []string) error {
	cfg := GetConfig()

	opts := &manager.Options{
		SkipMajor: cfg.NPM.SkipMajor,
		Greedy:    cfg.Brew.Greedy,
	}

	// Determine which managers to check
	var managerNames []string
	switch {
	case statusManagers != "":
		managerNames = strings.Split(statusManagers, ",")
	case len(cfg.Managers) > 0:
		managerNames = cfg.Managers
	default:
		managerNames = manager.List()
	}

	// Wrap config for skip list access
	cfgWrapper := &configWrapper{cfg: cfg}

	// JSON output - no TUI
	if statusJSON {
		return runStatusJSON(managerNames, opts, cfgWrapper)
	}

	// Detect output mode
	mode := ui.DetectOutputMode()

	switch mode {
	case ui.ModeTUI:
		return runStatusTUI(managerNames, opts, cfgWrapper)
	case ui.ModeStyled, ui.ModePlain:
		return runStatusPlain(managerNames, opts, cfgWrapper, mode == ui.ModeStyled)
	}

	return nil
}

func runStatusTUI(managerNames []string, opts *manager.Options, cfg *configWrapper) error {
	model := statusTUI.New(managerNames, opts, cfg)
	p := tea.NewProgram(model, tea.WithAltScreen())

	_, err := p.Run()
	return err
}

func runStatusJSON(managerNames []string, opts *manager.Options, cfg *configWrapper) error {
	ctx := context.Background()
	output := StatusOutput{
		Managers: make([]ManagerStatus, 0, len(managerNames)),
	}

	for _, name := range managerNames {
		m, err := manager.Get(name, opts)
		if err != nil {
			output.Managers = append(output.Managers, ManagerStatus{
				Name:  name,
				Error: err.Error(),
			})
			continue
		}

		status := ManagerStatus{
			Name:      name,
			Available: m.IsAvailable(),
		}

		if m.IsAvailable() {
			m.SetSkipList(cfg.GetSkipList(name))
			outdated, err := m.CheckOutdated(ctx)
			if err != nil {
				status.Error = err.Error()
			} else {
				status.Outdated = outdated
			}
		}

		output.Managers = append(output.Managers, status)
	}

	data, err := json.MarshalIndent(output, "", "  ")
	if err != nil {
		return err
	}
	fmt.Println(string(data))
	return nil
}

func runStatusPlain(managerNames []string, opts *manager.Options, cfg *configWrapper, styled bool) error {
	ctx := context.Background()

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
		case "brew":
			return yellow
		case "npm":
			return red
		case "pipx":
			return blue
		case "bun":
			return brightMagenta
		case "skills":
			return cyan
		default:
			return brightCyan
		}
	}

	fmt.Println()
	fmt.Printf("  %s %s\n", c(brightCyan, ui.IconDiamond), c(bold+brightCyan, "SARASA STATUS"))
	fmt.Println(c(dim, "  ─────────────────────────────────────────"))
	fmt.Println()

	totalOutdated := 0
	totalUpToDate := 0
	totalUnavailable := 0
	totalErrors := 0

	for _, name := range managerNames {
		m, err := manager.Get(name, opts)
		mColor := managerColor(name)
		icon := ""
		if styled {
			icon = ui.ManagerIcon(name) + " "
		}

		fmt.Printf("  %s%s\n", icon, c(bold+mColor, strings.ToUpper(name)))

		if err != nil {
			fmt.Printf("    %s %s\n\n", c(red, ui.IconCross), c(red, err.Error()))
			totalErrors++
			continue
		}

		if !m.IsAvailable() {
			fmt.Printf("    %s %s\n\n", c(dim, ui.IconCross), c(dim, "Not installed"))
			totalUnavailable++
			continue
		}

		m.SetSkipList(cfg.GetSkipList(name))
		outdated, err := m.CheckOutdated(ctx)
		if err != nil {
			fmt.Printf("    %s %s\n\n", c(red, ui.IconCross), c(red, err.Error()))
			totalErrors++
			continue
		}

		if len(outdated) == 0 {
			fmt.Printf("    %s %s\n\n", c(green, ui.IconCheck), c(green, "All packages up to date"))
			totalUpToDate++
			continue
		}

		fmt.Printf("    %s %s\n\n", c(yellow, ui.IconWarning), c(yellow, fmt.Sprintf("%d outdated", len(outdated))))
		totalOutdated += len(outdated)

		for _, pkg := range outdated {
			majorTag := ""
			if pkg.IsMajor {
				majorTag = " " + c(bold+brightYellow, "[MAJOR]")
			}
			fmt.Printf("      %s %s  %s %s %s%s\n",
				c(mColor, ui.IconTriangle),
				c(bold+white, pkg.Name),
				c(dim, pkg.Current),
				c(dim, ui.IconArrow),
				c(brightGreen, pkg.Latest),
				majorTag,
			)
		}
		fmt.Println()
	}

	// Summary
	fmt.Println(c(dim, "  ─────────────────────────────────────────"))
	fmt.Println()

	var summaryParts []string
	if totalOutdated > 0 {
		summaryParts = append(summaryParts, c(yellow, fmt.Sprintf("%d outdated", totalOutdated)))
	}
	if totalUpToDate > 0 {
		summaryParts = append(summaryParts, c(green, fmt.Sprintf("%d up to date", totalUpToDate)))
	}
	if totalUnavailable > 0 {
		summaryParts = append(summaryParts, c(dim, fmt.Sprintf("%d unavailable", totalUnavailable)))
	}
	if totalErrors > 0 {
		summaryParts = append(summaryParts, c(red, fmt.Sprintf("%d errors", totalErrors)))
	}

	if len(summaryParts) > 0 {
		fmt.Printf("  %s  %s\n", c(brightCyan, ui.IconSparkle), strings.Join(summaryParts, c(dim, " · ")))
	}

	if totalOutdated > 0 {
		fmt.Printf("     Run %s to upgrade\n", c(brightCyan+bold, "sarasa run"))
	}

	fmt.Println()
	return nil
}
