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

	"github.com/indrasvat/sarasa/internal/manager"
	"github.com/indrasvat/sarasa/internal/ui"
)

// PackageStatus represents the upgrade status of a single package.
type PackageStatus struct {
	Package   manager.Package
	Status    string // "pending", "upgrading", "success", "failed", "skipped"
	Duration  time.Duration
	Error     error
}

// ManagerResult holds the upgrade results for a manager.
type ManagerResult struct {
	Name       string
	Packages   []*PackageStatus
	Status     string // "pending", "checking", "upgrading", "done", "error"
	Error      error
	Duration   time.Duration
	StartTime  time.Time
}

// Model is the bubbletea model for the run command.
type Model struct {
	managers     []manager.Manager
	opts         *manager.Options
	cfg          ManagerConfigProvider
	results      []*ManagerResult
	currentMgr   int
	spinner      spinner.Model
	progress     progress.Model
	dryRun       bool
	skipCleanup  bool
	running      bool
	done         bool
	startTime    time.Time
	width        int
	height       int
	err          error

	// Stats
	totalPackages   int
	donePackages    int
	totalUpgraded   int
	totalFailed     int
	totalSkipped    int
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
	tickMsg      time.Time
	progressMsg  float64
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
	m.startTime = time.Now()
	m.running = true
	return tea.Batch(
		m.spinner.Tick,
		m.startNextManager(0),
	)
}

func (m Model) startNextManager(index int) tea.Cmd {
	if index >= len(m.managers) {
		return func() tea.Msg {
			return managerDoneMsg{index: -1} // Signal all done
		}
	}

	return func() tea.Msg {
		return managerStartMsg{index: index}
	}
}

func (m Model) runManager(index int) tea.Cmd {
	return func() tea.Msg {
		mgr := m.managers[index]
		ctx := context.Background()

		// Set skip list for this manager
		if m.cfg != nil {
			m.opts.SkipList = m.cfg.GetSkipList(mgr.Name())
		}

		start := time.Now()
		result, err := mgr.Upgrade(ctx, m.dryRun)
		duration := time.Since(start)

		// Run cleanup if not dry run and not skipped
		if err == nil && !m.dryRun && !m.skipCleanup {
			_ = mgr.Cleanup(ctx)
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
		m.results[msg.index].Status = "upgrading"
		m.results[msg.index].StartTime = time.Now()
		m.currentMgr = msg.index
		return m, m.runManager(msg.index)

	case managerDoneMsg:
		if msg.index == -1 {
			// All managers done
			m.running = false
			m.done = true
			return m, nil
		}

		result := m.results[msg.index]
		result.Duration = msg.duration

		if msg.err != nil {
			result.Status = "error"
			result.Error = msg.err
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

		// Start next manager
		return m, m.startNextManager(msg.index + 1)
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
		progressPct := float64(m.currentMgr) / float64(len(m.managers))
		b.WriteString(fmt.Sprintf("  %s  %s\n\n", m.progress.ViewAs(progressPct), ui.StyleDuration.Render(formatDuration(elapsed))))
	}

	// Manager panels
	panelWidth := 45
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
	icon := ui.ManagerIcon(result.Name)
	titleStyle := ui.GetManagerTitleStyle(result.Name)
	title := titleStyle.Render(strings.ToUpper(result.Name))
	headerStyle := lipgloss.NewStyle().MarginLeft(2)
	b.WriteString(headerStyle.Render(fmt.Sprintf("%s %s", icon, title)) + "\n")

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

				content.WriteString(fmt.Sprintf("  %s %s  %s %s %s%s", statusIcon, pkgName, current, arrow, latest, majorTag))
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
		if m.totalSkipped > 0 {
			parts = append(parts, lipgloss.NewStyle().Foreground(lipgloss.AdaptiveColor{Light: "#8B008B", Dark: "#DA70D6"}).Render(fmt.Sprintf("%d to upgrade", m.totalSkipped)))
		} else {
			parts = append(parts, ui.StyleSuccess.Render("All up to date"))
		}
	} else {
		if m.totalUpgraded > 0 {
			parts = append(parts, ui.StyleSuccess.Render(fmt.Sprintf("%d upgraded", m.totalUpgraded)))
		}
		if m.totalFailed > 0 {
			parts = append(parts, ui.StyleError.Render(fmt.Sprintf("%d failed", m.totalFailed)))
		}
		if m.totalUpgraded == 0 && m.totalFailed == 0 {
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
