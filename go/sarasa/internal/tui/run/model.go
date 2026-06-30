package run

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/progress"
	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/indrasvat/sarasa/internal/logger"
	"github.com/indrasvat/sarasa/internal/manager"
	"github.com/indrasvat/sarasa/internal/ui"
)

// PackageStatus represents the upgrade status of a single package.
type PackageStatus struct {
	Package  manager.Package
	Status   string // "pending", "upgrading", "success", "failed", "skipped"
	Duration time.Duration
	Error    error
}

// ManagerResult holds the upgrade results for a manager.
type ManagerResult struct {
	Name      string
	Packages  []*PackageStatus
	Status    string // "pending", "checking", "upgrading", "done", "error"
	Error     error
	Duration  time.Duration
	StartTime time.Time
}

// Model is the bubbletea model for the run command.
type Model struct {
	managers    []manager.Manager
	opts        *manager.Options
	cfg         ManagerConfigProvider
	results     []*ManagerResult
	activeCount int // Number of managers still running
	spinner     spinner.Model
	progress    progress.Model
	dryRun      bool
	skipCleanup bool
	running     bool
	done        bool
	startTime   time.Time
	width       int
	height      int

	// Stats
	totalUpgraded int
	totalFailed   int
	totalSkipped  int
}

// ManagerConfigProvider provides per-manager config.
type ManagerConfigProvider interface {
	GetSkipList(manager string) []string
}

// Messages
type (
	managerStartMsg struct {
		index int
	}
	managerDoneMsg struct {
		index    int
		result   *manager.UpgradeResult
		duration time.Duration
		err      error
	}
)

// New creates a new run TUI model.
func New(managers []manager.Manager, opts *manager.Options, cfg ManagerConfigProvider, dryRun, skipCleanup bool) Model {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = ui.StyleSpinner

	p := progress.New(
		progress.WithDefaultGradient(),
		progress.WithWidth(40),
		progress.WithoutPercentage(),
	)

	results := make([]*ManagerResult, len(managers))
	for i, mgr := range managers {
		results[i] = &ManagerResult{
			Name:     mgr.Name(),
			Status:   "pending",
			Packages: []*PackageStatus{},
		}
		// Set skip list for each manager upfront (before concurrent execution)
		if cfg != nil {
			mgr.SetSkipList(cfg.GetSkipList(mgr.Name()))
		}
	}

	return Model{
		managers:    managers,
		opts:        opts,
		cfg:         cfg,
		results:     results,
		spinner:     s,
		progress:    p,
		dryRun:      dryRun,
		skipCleanup: skipCleanup,
	}
}

// Init initializes the model.
func (m Model) Init() tea.Cmd {
	// Start all managers concurrently
	cmds := make([]tea.Cmd, 0, len(m.managers)+1)
	cmds = append(cmds, m.spinner.Tick)

	for i := range m.managers {
		idx := i // capture loop variable
		cmds = append(cmds, func() tea.Msg {
			return managerStartMsg{index: idx}
		})
	}

	return tea.Batch(cmds...)
}

func (m Model) runManager(index int) tea.Cmd {
	mgr := m.managers[index]
	dryRun := m.dryRun
	skipCleanup := m.skipCleanup

	return func() tea.Msg {
		ctx := context.Background()

		start := time.Now()
		result, err := mgr.Upgrade(ctx, dryRun)
		duration := time.Since(start)

		// Run cleanup if not dry run and not skipped
		if err == nil && !dryRun && !skipCleanup {
			if cleanupErr := mgr.Cleanup(ctx); cleanupErr != nil {
				logger.WithManager(mgr.Name()).Warn("Cleanup failed",
					"error", cleanupErr.Error(),
					"action", "cleanup",
				)
			}
		}

		return managerDoneMsg{
			index:    index,
			result:   result,
			duration: duration,
			err:      err,
		}
	}
}

// Update handles messages.
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c", "esc":
			return m, tea.Quit
		}

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		m.progress.Width = min(40, m.width-10)
		return m, nil

	case spinner.TickMsg:
		var cmd tea.Cmd
		m.spinner, cmd = m.spinner.Update(msg)
		return m, cmd

	case progress.FrameMsg:
		progressModel, cmd := m.progress.Update(msg)
		m.progress = progressModel.(progress.Model)
		return m, cmd

	case managerStartMsg:
		// Initialize timing on first manager start
		if !m.running {
			m.running = true
			m.startTime = time.Now()
		}
		m.results[msg.index].Status = "upgrading"
		m.results[msg.index].StartTime = time.Now()
		m.activeCount++
		return m, m.runManager(msg.index)

	case managerDoneMsg:
		m.activeCount--

		result := m.results[msg.index]
		result.Duration = msg.duration

		if msg.err != nil {
			result.Status = "error"
			result.Error = msg.err
			m.totalFailed++
		} else {
			result.Status = "done"
			// Convert result packages to status
			for _, pkg := range msg.result.Upgraded {
				result.Packages = append(result.Packages, &PackageStatus{
					Package: pkg,
					Status:  "success",
				})
				m.totalUpgraded++
			}
			for _, pkg := range msg.result.Failed {
				result.Packages = append(result.Packages, &PackageStatus{
					Package: pkg,
					Status:  "failed",
				})
				m.totalFailed++
			}
			for _, pkg := range msg.result.Skipped {
				result.Packages = append(result.Packages, &PackageStatus{
					Package: pkg,
					Status:  "skipped",
				})
				m.totalSkipped++
			}
		}

		// Check if all managers are done
		if m.activeCount == 0 {
			m.running = false
			m.done = true
		}

		return m, nil
	}

	return m, nil
}

// View renders the UI.
func (m Model) View() string {
	var b strings.Builder

	// Header
	b.WriteString("\n")
	headerIcon := ui.StyleSummaryIcon.Render(ui.IconDiamond)
	var headerText string
	if m.dryRun {
		headerText = ui.StyleHeaderDryRun.Render("SARASA DRY RUN")
	} else {
		headerText = ui.StyleHeader.Render("SARASA UPGRADE")
	}

	if m.running {
		b.WriteString(fmt.Sprintf("  %s %s  %s Upgrading packages...\n", headerIcon, headerText, m.spinner.View()))
	} else {
		b.WriteString(fmt.Sprintf("  %s %s\n", headerIcon, headerText))
	}
	b.WriteString("\n")

	// Progress bar (only during upgrade)
	if m.running && !m.dryRun {
		elapsed := time.Since(m.startTime)
		completed := len(m.managers) - m.activeCount
		progressPct := float64(completed) / float64(len(m.managers))
		b.WriteString(fmt.Sprintf("  %s  %s\n\n", m.progress.ViewAs(progressPct), ui.StyleDuration.Render(formatDuration(elapsed))))
	}

	// Manager panels
	panelWidth := 45
	if m.width >= 90 {
		panelWidth = min(76, m.width-6)
	}
	if m.width > 0 && m.width < 60 {
		panelWidth = m.width - 6
	}

	for _, result := range m.results {
		b.WriteString(m.renderManagerPanel(result, panelWidth))
	}

	// Summary (only when done)
	if m.done {
		b.WriteString(m.renderSummary())
	}

	// Help
	b.WriteString(ui.StyleHelp.Render("  q quit"))
	b.WriteString("\n")

	return b.String()
}

func (m Model) renderManagerPanel(result *ManagerResult, width int) string {
	var b strings.Builder

	// Manager header with icon OUTSIDE the panel (with proper margin)
	titleStyle := ui.GetManagerTitleStyle(result.Name)
	title := titleStyle.Render(strings.ToUpper(result.Name))
	headerStyle := lipgloss.NewStyle().MarginLeft(2)
	b.WriteString(headerStyle.Render(ui.ManagerIconLabelPrefix(result.Name)+title) + "\n")

	// Panel content (no emoji inside)
	var content strings.Builder

	switch result.Status {
	case "pending":
		content.WriteString(ui.StyleMuted.Render("waiting..."))
	case "upgrading":
		elapsed := time.Since(result.StartTime)
		content.WriteString(fmt.Sprintf("%s %s", m.spinner.View(), ui.StyleDuration.Render(formatDuration(elapsed))))
	case "error":
		content.WriteString(ui.StyleError.Render(ui.IconCross + " " + result.Error.Error()))
	case "done":
		if len(result.Packages) == 0 {
			content.WriteString(ui.StyleSuccess.Render(ui.IconCheck + " Already up to date"))
		} else {
			durationStr := ui.StyleDuration.Render(fmt.Sprintf("(%s)", formatDuration(result.Duration)))
			content.WriteString(fmt.Sprintf("%s\n", durationStr))

			// Package list
			for i, pkg := range result.Packages {
				var statusIcon string
				var versionStyle lipgloss.Style

				switch pkg.Status {
				case "success":
					statusIcon = ui.StyleSuccess.Render(ui.IconCheck)
					versionStyle = ui.StyleVersionLatest
				case "failed":
					statusIcon = ui.StyleError.Render(ui.IconCross)
					versionStyle = ui.StyleError
				case "skipped":
					mgrColor := ui.ManagerColor(result.Name)
					statusIcon = lipgloss.NewStyle().Foreground(mgrColor).Render(ui.IconTriangle)
					versionStyle = lipgloss.NewStyle().Foreground(lipgloss.AdaptiveColor{Light: "#8B008B", Dark: "#DA70D6"})
				}

				pkgName := ui.StylePackageName.Render(pkg.Package.Name)
				current := ui.StyleVersionCurrent.Render(pkg.Package.Current)
				arrow := ui.StyleArrow.Render(ui.IconArrow)
				latest := versionStyle.Render(pkg.Package.Latest)

				majorTag := ""
				if pkg.Package.IsMajor && pkg.Status == "skipped" {
					majorTag = " " + ui.StyleVersionMajor.Render("[MAJOR]")
				}
				methodTag := ""
				if pkg.Package.Method != "" {
					methodTag = " " + ui.StyleMethodTag.Render("· "+pkg.Package.Method)
				}
				reasonTag := ""
				if pkg.Package.SkipReason != "" {
					reasonTag = " " + ui.StyleMethodTag.Render("· "+pkg.Package.SkipReason)
				}

				content.WriteString(fmt.Sprintf("  %s %s  %s %s %s%s%s%s", statusIcon, pkgName, current, arrow, latest, majorTag, methodTag, reasonTag))
				if i < len(result.Packages)-1 {
					content.WriteString("\n")
				}
			}
		}
	}

	// Use MarginLeft instead of string concatenation for proper multi-line indent
	panelStyle := ui.GetManagerPanelStyle(result.Name).Width(width).MarginLeft(2)
	b.WriteString(panelStyle.Render(content.String()) + "\n")
	return b.String()
}

func (m Model) renderSummary() string {
	var b strings.Builder
	var parts []string

	totalDuration := time.Since(m.startTime)

	if m.dryRun {
		if m.totalFailed > 0 {
			parts = append(parts, ui.StyleError.Render(fmt.Sprintf("%d failed", m.totalFailed)))
		}
		if m.totalSkipped > 0 {
			parts = append(parts, lipgloss.NewStyle().Foreground(lipgloss.AdaptiveColor{Light: "#8B008B", Dark: "#DA70D6"}).Render(fmt.Sprintf("%d to upgrade", m.totalSkipped)))
		}
		if m.totalFailed == 0 && m.totalSkipped == 0 {
			parts = append(parts, ui.StyleSuccess.Render("All up to date"))
		}
	} else {
		if m.totalUpgraded > 0 {
			parts = append(parts, ui.StyleSuccess.Render(fmt.Sprintf("%d upgraded", m.totalUpgraded)))
		}
		if m.totalFailed > 0 {
			parts = append(parts, ui.StyleError.Render(fmt.Sprintf("%d failed", m.totalFailed)))
		}
		if m.totalSkipped > 0 {
			parts = append(parts, lipgloss.NewStyle().Foreground(lipgloss.AdaptiveColor{Light: "#8B008B", Dark: "#DA70D6"}).Render(fmt.Sprintf("%d skipped", m.totalSkipped)))
		}
		if m.totalUpgraded == 0 && m.totalFailed == 0 && m.totalSkipped == 0 {
			parts = append(parts, ui.StyleSuccess.Render("All up to date"))
		}
	}

	parts = append(parts, ui.StyleDuration.Render(formatDuration(totalDuration)))

	summaryIcon := ui.IconSparkle
	if m.totalFailed > 0 {
		summaryIcon = ui.IconFailed
	}

	separator := ui.StyleMuted.Render(" · ")
	summaryLine := strings.Join(parts, separator)
	b.WriteString(fmt.Sprintf("\n  %s  %s\n", summaryIcon, summaryLine))

	if m.dryRun && m.totalSkipped > 0 {
		cmdStyle := lipgloss.NewStyle().Bold(true).Foreground(ui.ColorPrimary)
		b.WriteString(fmt.Sprintf("     Run %s to apply upgrades\n", cmdStyle.Render("sarasa run")))
	}

	b.WriteString("\n")
	return b.String()
}

// GetResults returns the upgrade results.
func (m Model) GetResults() []*ManagerResult {
	return m.results
}

// GetStats returns the upgrade statistics.
func (m Model) GetStats() (upgraded, failed, skipped int, duration time.Duration) {
	return m.totalUpgraded, m.totalFailed, m.totalSkipped, time.Since(m.startTime)
}

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
