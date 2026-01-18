package status

import (
	"context"
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

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

// Model is the bubbletea model for the status command.
type Model struct {
	managers  []string
	opts      *manager.Options
	statuses  map[string]*ManagerStatus
	loadOrder []string
	spinner   spinner.Model
	loading   bool
	done      bool
	width     int
	height    int
}

// allLoadedMsg is sent when all managers are loaded.
type allLoadedMsg struct{}

// New creates a new status TUI model.
func New(managerNames []string, opts *manager.Options) Model {
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
		statuses:  statuses,
		loadOrder: managerNames,
		spinner:   s,
		loading:   true,
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
					outdated, err := mgr.CheckOutdated(ctx)
					if err != nil {
						status.Error = err
					} else {
						status.Outdated = outdated
					}
				}
				status.Loading = false
			}

			// We'll collect all and return at end
			m.statuses[name] = status
		}

		return allLoadedMsg{}
	}
}

// Update handles messages.
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c", "esc":
			return m, tea.Quit
		case "r":
			if !m.loading {
				// Reset and reload
				for _, name := range m.managers {
					m.statuses[name].Loading = true
				}
				m.loading = true
				m.done = false
				return m, tea.Batch(m.spinner.Tick, m.loadAllManagers())
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
		m.loading = false
		m.done = true
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
	headerText := ui.StyleHeader.Render("SARASA STATUS")
	if m.loading {
		b.WriteString(fmt.Sprintf("  %s %s %s\n", headerIcon, headerText, m.spinner.View()))
	} else {
		b.WriteString(fmt.Sprintf("  %s %s\n", headerIcon, headerText))
	}
	b.WriteString("\n")

	// Manager panels
	totalOutdated := 0
	totalUpToDate := 0
	totalUnavailable := 0
	totalErrors := 0

	panelWidth := 45
	if m.width > 0 && m.width < 60 {
		panelWidth = m.width - 6
	}

	for _, name := range m.loadOrder {
		status := m.statuses[name]
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

	// Summary (only show when done)
	if m.done {
		b.WriteString(m.renderSummary(totalOutdated, totalUpToDate, totalUnavailable, totalErrors))
	}

	// Help
	helpStyle := ui.StyleHelp
	if m.loading {
		b.WriteString(helpStyle.Render("  q quit"))
	} else {
		b.WriteString(helpStyle.Render("  r refresh  ·  q quit"))
	}
	b.WriteString("\n")

	return b.String()
}

func (m Model) renderManagerPanel(name string, status *ManagerStatus, width int) string {
	var b strings.Builder

	// Manager header with icon OUTSIDE the panel (with proper margin)
	icon := ui.ManagerIcon(name)
	titleStyle := ui.GetManagerTitleStyle(name)
	title := titleStyle.Render(strings.ToUpper(name))
	headerStyle := lipgloss.NewStyle().MarginLeft(2)
	b.WriteString(headerStyle.Render(fmt.Sprintf("%s %s", icon, title)) + "\n")

	// Panel content (no emoji inside)
	var content strings.Builder

	switch {
	case status.Loading:
		content.WriteString(fmt.Sprintf("%s Loading...", m.spinner.View()))
	case !status.Available:
		content.WriteString(ui.StyleMuted.Render(ui.IconCross + " Not installed"))
	case status.Error != nil:
		content.WriteString(ui.StyleError.Render(ui.IconCross + " " + status.Error.Error()))
	case len(status.Outdated) == 0:
		content.WriteString(ui.StyleSuccess.Render(ui.IconCheck + " All up to date"))
	default:
		outdatedCount := ui.StyleWarning.Render(fmt.Sprintf("%d outdated", len(status.Outdated)))
		content.WriteString(fmt.Sprintf("%s\n", outdatedCount))

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

			mgrColor := ui.ManagerColor(name)
			triangle := lipgloss.NewStyle().Foreground(mgrColor).Render(ui.IconTriangle)
			content.WriteString(fmt.Sprintf("  %s %s  %s %s %s%s", triangle, pkgName, current, arrow, latest, majorTag))
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
		b.WriteString(fmt.Sprintf("  %s  %s\n", ui.StyleSummaryIcon.Render(ui.IconSparkle), summaryLine))
	}

	if outdated > 0 {
		cmdStyle := lipgloss.NewStyle().Bold(true).Foreground(ui.ColorPrimary)
		b.WriteString(fmt.Sprintf("     Run %s to upgrade\n", cmdStyle.Render("sarasa run")))
	}

	b.WriteString("\n")
	return b.String()
}

// GetStatuses returns the manager statuses for JSON output.
func (m Model) GetStatuses() map[string]*ManagerStatus {
	return m.statuses
}
