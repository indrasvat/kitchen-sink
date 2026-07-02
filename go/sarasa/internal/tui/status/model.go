package status

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/indrasvat/sarasa/internal/logger"
	"github.com/indrasvat/sarasa/internal/manager"
	"github.com/indrasvat/sarasa/internal/ui"
)

// ManagerStatus represents the status of a single manager.
type ManagerStatus struct {
	Name      string
	Available bool
	Outdated  []manager.Package
	Error     error
	Loading   bool
}

// ManagerConfigProvider provides per-manager config.
type ManagerConfigProvider interface {
	GetSkipList(manager string) []string
}

type upgradeState int

const (
	stateLoading upgradeState = iota
	stateViewing
	stateUpgrading
	stateCleaningUp
	stateUpgraded
)

type upgradeResult struct {
	Name         string
	Packages     []*packageResult
	Status       string // "pending", "upgrading", "done", "error"
	Error        error
	CleanupError error
	Duration     time.Duration
	Start        time.Time
}

type packageResult struct {
	Package manager.Package
	Status  string // "success", "failed", "skipped"
}

// Model is the bubbletea model for the status command.
type Model struct {
	managers       []string
	opts           *manager.Options
	cfg            ManagerConfigProvider
	statuses       map[string]*ManagerStatus
	loadOrder      []string
	spinner        spinner.Model
	state          upgradeState
	upgradeResults map[string]*upgradeResult
	upgradeOrder   []string
	activeCount    int
	startTime      time.Time
	totalUpgraded  int
	totalFailed    int
	totalSkipped   int
	width          int
	height         int
}

// Messages
type allLoadedMsg struct{}

type upgradeStartMsg struct{ name string }

type upgradeManagerDoneMsg struct {
	name     string
	result   *manager.UpgradeResult
	duration time.Duration
	err      error
}

type cleanupDoneMsg struct {
	errors map[string]error
}

// New creates a new status TUI model.
func New(managerNames []string, opts *manager.Options, cfg ManagerConfigProvider) Model {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = ui.StyleSpinner

	statuses := make(map[string]*ManagerStatus)
	for _, name := range managerNames {
		statuses[name] = &ManagerStatus{
			Name:    name,
			Loading: true,
		}
	}

	return Model{
		managers:  managerNames,
		opts:      opts,
		cfg:       cfg,
		statuses:  statuses,
		loadOrder: managerNames,
		spinner:   s,
		state:     stateLoading,
	}
}

// Init initializes the model.
func (m Model) Init() tea.Cmd {
	return tea.Batch(
		m.spinner.Tick,
		m.loadAllManagers(),
	)
}

// loadAllManagers starts loading all manager statuses.
func (m Model) loadAllManagers() tea.Cmd {
	return func() tea.Msg {
		ctx := context.Background()

		for _, name := range m.managers {
			mgr, err := manager.Get(name, m.opts)
			status := &ManagerStatus{Name: name}

			if err != nil {
				status.Error = err
				status.Loading = false
			} else {
				status.Available = mgr.IsAvailable()
				if status.Available {
					if m.cfg != nil {
						mgr.SetSkipList(m.cfg.GetSkipList(name))
					}
					outdated, err := mgr.CheckOutdated(ctx)
					if err != nil {
						status.Error = err
					} else {
						status.Outdated = outdated
					}
				}
				status.Loading = false
			}

			m.statuses[name] = status
		}

		return allLoadedMsg{}
	}
}

func (m Model) hasOutdated() bool {
	for _, status := range m.statuses {
		if status.Available && status.Error == nil && len(status.Outdated) > 0 {
			return true
		}
	}
	return false
}

func (m Model) runManagerUpgrade(name string) tea.Cmd {
	opts := m.opts
	cfgProvider := m.cfg

	return func() tea.Msg {
		ctx := context.Background()

		mgr, err := manager.Get(name, opts)
		if err != nil {
			return upgradeManagerDoneMsg{name: name, err: err}
		}

		if cfgProvider != nil {
			mgr.SetSkipList(cfgProvider.GetSkipList(name))
		}

		logger.LogStart(name)
		start := time.Now()
		result, err := mgr.Upgrade(ctx, false)
		duration := time.Since(start)

		return upgradeManagerDoneMsg{
			name:     name,
			result:   result,
			duration: duration,
			err:      err,
		}
	}
}

func (m Model) cleanupUpgradedManagers() tea.Cmd {
	opts := m.opts
	cfgProvider := m.cfg
	names := append([]string(nil), m.upgradeOrder...)

	return func() tea.Msg {
		ctx := context.Background()
		cleanupErrors := make(map[string]error)
		for _, name := range names {
			result := m.upgradeResults[name]
			if result == nil || result.Status == "error" {
				continue
			}
			mgr, err := manager.Get(name, opts)
			if err != nil {
				cleanupErrors[name] = err
				continue
			}
			if cfgProvider != nil {
				mgr.SetSkipList(cfgProvider.GetSkipList(name))
			}
			if err := mgr.Cleanup(ctx); err != nil {
				logger.WithManager(name).Warn("Cleanup failed",
					"error", err.Error(),
					"action", "cleanup",
				)
				cleanupErrors[name] = err
			}
		}
		return cleanupDoneMsg{errors: cleanupErrors}
	}
}

//nolint:gocyclo // Bubble Tea state-machine update path; splitting would obscure message flow.
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c", "esc":
			return m, tea.Quit
		case "r":
			if m.state == stateViewing || m.state == stateUpgraded {
				// Reset and reload
				for _, name := range m.managers {
					m.statuses[name] = &ManagerStatus{
						Name:    name,
						Loading: true,
					}
				}
				m.state = stateLoading
				m.upgradeResults = nil
				m.upgradeOrder = nil
				m.activeCount = 0
				m.totalUpgraded = 0
				m.totalFailed = 0
				m.totalSkipped = 0
				return m, tea.Batch(m.spinner.Tick, m.loadAllManagers())
			}
		case "u":
			if m.state == stateViewing && m.hasOutdated() {
				m.state = stateUpgrading
				m.startTime = time.Now()
				m.upgradeResults = make(map[string]*upgradeResult)
				m.upgradeOrder = nil
				m.activeCount = 0
				m.totalUpgraded = 0
				m.totalFailed = 0
				m.totalSkipped = 0

				var cmds []tea.Cmd
				for _, name := range m.loadOrder {
					status := m.statuses[name]
					if !status.Available || status.Error != nil || len(status.Outdated) == 0 {
						continue
					}
					m.upgradeOrder = append(m.upgradeOrder, name)
					m.upgradeResults[name] = &upgradeResult{
						Name:   name,
						Status: "pending",
					}
					m.activeCount++
					n := name // capture
					cmds = append(cmds, func() tea.Msg {
						return upgradeStartMsg{name: n}
					})
				}

				return m, tea.Batch(cmds...)
			}
		}

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil

	case spinner.TickMsg:
		var cmd tea.Cmd
		m.spinner, cmd = m.spinner.Update(msg)
		return m, cmd

	case allLoadedMsg:
		m.state = stateViewing
		return m, nil

	case upgradeStartMsg:
		if r, ok := m.upgradeResults[msg.name]; ok {
			r.Status = "upgrading"
			r.Start = time.Now()
		}
		return m, m.runManagerUpgrade(msg.name)

	case upgradeManagerDoneMsg:
		m.activeCount--

		r, ok := m.upgradeResults[msg.name]
		if !ok {
			break
		}

		r.Duration = msg.duration

		if msg.err != nil {
			r.Status = "error"
			r.Error = msg.err
		} else {
			if msg.result == nil {
				msg.result = &manager.UpgradeResult{}
			}
			r.Status = "done"
			for _, pkg := range msg.result.Upgraded {
				r.Packages = append(r.Packages, &packageResult{
					Package: pkg,
					Status:  "success",
				})
				m.totalUpgraded++
			}
			for _, pkg := range msg.result.Failed {
				r.Packages = append(r.Packages, &packageResult{
					Package: pkg,
					Status:  "failed",
				})
				m.totalFailed++
			}
			for _, pkg := range msg.result.Skipped {
				r.Packages = append(r.Packages, &packageResult{
					Package: pkg,
					Status:  "skipped",
				})
				m.totalSkipped++
			}
		}

		upgraded := 0
		failed := 0
		for _, p := range r.Packages {
			switch p.Status {
			case "success":
				upgraded++
			case "failed":
				failed++
			}
		}
		logger.LogComplete(msg.name, upgraded, failed, msg.duration.Milliseconds())

		if m.activeCount == 0 {
			if m.opts != nil && !m.opts.DryRun && !m.opts.SkipCleanup {
				m.state = stateCleaningUp
				return m, tea.Batch(m.spinner.Tick, m.cleanupUpgradedManagers())
			}
			m.finishUpgrade()
		}

		return m, nil

	case cleanupDoneMsg:
		for name, err := range msg.errors {
			if result := m.upgradeResults[name]; result != nil {
				result.CleanupError = err
			}
			m.totalFailed++
		}
		m.finishUpgrade()
		return m, nil
	}

	return m, nil
}

func (m *Model) finishUpgrade() {
	m.state = stateUpgraded
	totalDuration := time.Since(m.startTime)
	logger.Get().Info("Status upgrade completed",
		"total_upgraded", m.totalUpgraded,
		"total_failed", m.totalFailed,
		"duration_ms", totalDuration.Milliseconds(),
	)
}

// View renders the UI.
func (m Model) View() string {
	var b strings.Builder

	// Header
	b.WriteString("\n")
	headerIcon := ui.StyleSummaryIcon.Render(ui.IconDiamond)
	headerText := ui.StyleHeader.Render("SARASA STATUS")
	switch m.state {
	case stateLoading:
		fmt.Fprintf(&b, "  %s %s %s\n", headerIcon, headerText, m.spinner.View())
	case stateUpgrading:
		fmt.Fprintf(&b, "  %s %s  %s Upgrading...\n", headerIcon, headerText, m.spinner.View())
	case stateCleaningUp:
		fmt.Fprintf(&b, "  %s %s  %s Cleaning up...\n", headerIcon, headerText, m.spinner.View())
	case stateViewing, stateUpgraded:
		fmt.Fprintf(&b, "  %s %s\n", headerIcon, headerText)
	}
	b.WriteString("\n")

	// Manager panels
	totalOutdated := 0
	totalUpToDate := 0
	totalUnavailable := 0
	totalErrors := 0

	panelWidth := 45
	if m.width >= 90 {
		panelWidth = min(76, m.width-6)
	}
	if m.width > 0 && m.width < 60 {
		panelWidth = m.width - 6
	}

	for _, name := range m.loadOrder {
		status := m.statuses[name]

		// If upgrading/upgraded and this manager has an upgrade result, show upgrade panel
		if (m.state == stateUpgrading || m.state == stateCleaningUp || m.state == stateUpgraded) && m.upgradeResults != nil {
			if ur, ok := m.upgradeResults[name]; ok {
				b.WriteString(m.renderUpgradePanel(name, ur, panelWidth))
				// Don't count stats for upgrade panels
				continue
			}
		}

		b.WriteString(m.renderManagerPanel(name, status, panelWidth))

		if status.Loading {
			continue
		}
		switch {
		case !status.Available:
			totalUnavailable++
		case status.Error != nil:
			totalErrors++
		case len(status.Outdated) > 0:
			totalOutdated += len(status.Outdated)
		default:
			totalUpToDate++
		}
	}

	// Summary
	switch m.state {
	case stateViewing:
		b.WriteString(m.renderSummary(totalOutdated, totalUpToDate, totalUnavailable, totalErrors))
	case stateUpgraded:
		b.WriteString(m.renderUpgradeSummary())
	case stateLoading, stateUpgrading, stateCleaningUp:
		// No summary while loading or upgrading
	}

	// Help bar
	helpStyle := ui.StyleHelp
	switch m.state {
	case stateLoading:
		b.WriteString(helpStyle.Render("  q quit"))
	case stateViewing:
		if m.hasOutdated() {
			b.WriteString(helpStyle.Render("  u upgrade  ·  r refresh  ·  q quit"))
		} else {
			b.WriteString(helpStyle.Render("  r refresh  ·  q quit"))
		}
	case stateUpgrading:
		b.WriteString(helpStyle.Render("  q quit"))
	case stateCleaningUp:
		b.WriteString(helpStyle.Render("  q quit"))
	case stateUpgraded:
		b.WriteString(helpStyle.Render("  r refresh  ·  q quit"))
	}
	b.WriteString("\n")

	return b.String()
}

func (m Model) renderManagerPanel(name string, status *ManagerStatus, width int) string {
	var b strings.Builder

	// Manager header with icon OUTSIDE the panel (with proper margin)
	titleStyle := ui.GetManagerTitleStyle(name)
	title := titleStyle.Render(strings.ToUpper(name))
	headerStyle := lipgloss.NewStyle().MarginLeft(2)
	b.WriteString(headerStyle.Render(ui.ManagerIconLabelPrefix(name)+title) + "\n")

	// Panel content (no emoji inside)
	var content strings.Builder

	switch {
	case status.Loading:
		fmt.Fprintf(&content, "%s Loading...", m.spinner.View())
	case !status.Available:
		content.WriteString(ui.StyleMuted.Render(ui.IconCross + " Not installed"))
	case status.Error != nil:
		content.WriteString(ui.StyleError.Render(ui.IconCross + " " + status.Error.Error()))
	case len(status.Outdated) == 0:
		content.WriteString(ui.StyleSuccess.Render(ui.IconCheck + " All up to date"))
	default:
		outdatedCount := ui.StyleWarning.Render(fmt.Sprintf("%d outdated", len(status.Outdated)))
		fmt.Fprintf(&content, "%s\n", outdatedCount)

		// Package list
		for i, pkg := range status.Outdated {
			arrow := ui.StyleArrow.Render(ui.IconArrow)
			pkgName := ui.StylePackageName.Render(pkg.Name)
			current := ui.StyleVersionCurrent.Render(pkg.Current)
			latest := ui.StyleVersionLatest.Render(pkg.Latest)

			majorTag := ""
			if pkg.IsMajor {
				majorTag = " " + ui.StyleVersionMajor.Render("[MAJOR]")
			}
			methodTag := ""
			if pkg.Method != "" {
				methodTag = " " + ui.StyleMethodTag.Render("· "+pkg.Method)
			}

			mgrColor := ui.ManagerColor(name)
			triangle := lipgloss.NewStyle().Foreground(mgrColor).Render(ui.IconTriangle)
			fmt.Fprintf(&content, "  %s %s  %s %s %s%s%s", triangle, pkgName, current, arrow, latest, majorTag, methodTag)
			if i < len(status.Outdated)-1 {
				content.WriteString("\n")
			}
		}
	}

	// Use MarginLeft instead of string concatenation for proper multi-line indent
	panelStyle := ui.GetManagerPanelStyle(name).Width(width).MarginLeft(2)
	b.WriteString(panelStyle.Render(content.String()) + "\n")
	return b.String()
}

func (m Model) renderUpgradePanel(name string, result *upgradeResult, width int) string {
	var b strings.Builder

	// Manager header with icon OUTSIDE the panel (with proper margin)
	titleStyle := ui.GetManagerTitleStyle(name)
	title := titleStyle.Render(strings.ToUpper(name))
	headerStyle := lipgloss.NewStyle().MarginLeft(2)
	b.WriteString(headerStyle.Render(ui.ManagerIconLabelPrefix(name)+title) + "\n")

	var content strings.Builder

	switch result.Status {
	case "pending":
		content.WriteString(ui.StyleMuted.Render("waiting..."))
	case "upgrading":
		elapsed := time.Since(result.Start)
		fmt.Fprintf(&content, "%s %s", m.spinner.View(), ui.StyleDuration.Render(formatDuration(elapsed)))
	case "error":
		content.WriteString(ui.StyleError.Render(ui.IconCross + " " + result.Error.Error()))
	case "done":
		if len(result.Packages) == 0 {
			content.WriteString(ui.StyleSuccess.Render(ui.IconCheck + " Already up to date"))
		} else {
			durationStr := ui.StyleDuration.Render(fmt.Sprintf("(%s)", formatDuration(result.Duration)))
			fmt.Fprintf(&content, "%s\n", durationStr)

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
					mgrColor := ui.ManagerColor(name)
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

				fmt.Fprintf(&content, "  %s %s  %s %s %s%s%s%s", statusIcon, pkgName, current, arrow, latest, majorTag, methodTag, reasonTag)
				if i < len(result.Packages)-1 {
					content.WriteString("\n")
				}
			}
		}
	}
	if result.CleanupError != nil {
		if content.Len() > 0 {
			content.WriteString("\n")
		}
		content.WriteString(ui.StyleWarning.Render(ui.IconWarning + " cleanup failed: " + result.CleanupError.Error()))
	}

	panelStyle := ui.GetManagerPanelStyle(name).Width(width).MarginLeft(2)
	b.WriteString(panelStyle.Render(content.String()) + "\n")
	return b.String()
}

func (m Model) renderSummary(outdated, upToDate, unavailable, errors int) string {
	var parts []string

	if outdated > 0 {
		parts = append(parts, ui.StyleWarning.Render(fmt.Sprintf("%d outdated", outdated)))
	}
	if upToDate > 0 {
		parts = append(parts, ui.StyleSuccess.Render(fmt.Sprintf("%d up to date", upToDate)))
	}
	if unavailable > 0 {
		parts = append(parts, ui.StyleMuted.Render(fmt.Sprintf("%d unavailable", unavailable)))
	}
	if errors > 0 {
		parts = append(parts, ui.StyleError.Render(fmt.Sprintf("%d errors", errors)))
	}

	var b strings.Builder
	if len(parts) > 0 {
		separator := ui.StyleMuted.Render(" · ")
		summaryLine := strings.Join(parts, separator)
		fmt.Fprintf(&b, "  %s  %s\n", ui.StyleSummaryIcon.Render(ui.IconSparkle), summaryLine)
	}

	if outdated > 0 {
		keyStyle := lipgloss.NewStyle().Bold(true).Foreground(ui.ColorPrimary)
		fmt.Fprintf(&b, "     Press %s to upgrade\n", keyStyle.Render("u"))
	}

	b.WriteString("\n")
	return b.String()
}

func (m Model) renderUpgradeSummary() string {
	var b strings.Builder
	var parts []string

	totalDuration := time.Since(m.startTime)

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

	parts = append(parts, ui.StyleDuration.Render(formatDuration(totalDuration)))

	summaryIcon := ui.IconSparkle
	if m.totalFailed > 0 {
		summaryIcon = ui.IconFailed
	}

	separator := ui.StyleMuted.Render(" · ")
	summaryLine := strings.Join(parts, separator)
	fmt.Fprintf(&b, "\n  %s  %s\n", summaryIcon, summaryLine)
	b.WriteString("\n")
	return b.String()
}

// GetStatuses returns the manager statuses for JSON output.
func (m Model) GetStatuses() map[string]*ManagerStatus {
	return m.statuses
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
