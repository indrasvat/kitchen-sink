package wizard

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/indrasvat/sarasa/internal/ui"
)

// ScheduleChoice represents a schedule option.
type ScheduleChoice struct {
	Label string
	Times []string
}

// Result holds the final selections from the init wizard.
type Result struct {
	Managers []string
	Schedule ScheduleChoice
	Aborted  bool
}

var scheduleChoices = []ScheduleChoice{
	{Label: "Every hour", Times: genHourlyTimes(1)},
	{Label: "Every 2 hours", Times: genHourlyTimes(2)},
	{Label: "Every 6 hours", Times: []string{"06:00", "12:00", "18:00", "00:00"}},
	{Label: "Three times a day (8am, 2pm, 10pm)", Times: []string{"08:00", "14:00", "22:00"}},
	{Label: "No schedule", Times: nil},
}

func genHourlyTimes(interval int) []string {
	var times []string
	for h := 0; h < 24; h += interval {
		times = append(times, fmt.Sprintf("%02d:00", h))
	}
	return times
}

type phase int

const (
	phaseManagers phase = iota
	phaseSchedule
	phaseDone
)

// Model is the bubbletea model for the init wizard.
type Model struct {
	phase    phase
	cursor   int
	managers []managerItem
	schedIdx int
	result   Result
	quitting bool
	width    int
}

type managerItem struct {
	name      string
	icon      string
	available bool
	selected  bool
}

// New creates a new init wizard model.
func New(availableManagers []string) Model {
	allManagers := []struct {
		name string
		icon string
	}{
		{"brew", ui.IconBrew},
		{"volta", ui.IconVolta},
		{"npm", ui.IconNPM},
		{"pipx", ui.IconPipx},
		{"bun", ui.IconBun},
		{"skills", ui.IconSkills},
	}

	avail := make(map[string]bool)
	for _, m := range availableManagers {
		avail[m] = true
	}

	items := make([]managerItem, 0, len(allManagers))
	for _, m := range allManagers {
		items = append(items, managerItem{
			name:      m.name,
			icon:      m.icon,
			available: avail[m.name],
			selected:  avail[m.name], // pre-select available ones
		})
	}

	return Model{
		phase:    phaseManagers,
		managers: items,
		schedIdx: 1, // default: every 2 hours
	}
}

// Init implements tea.Model.
func (m Model) Init() tea.Cmd {
	return nil
}

// Update implements tea.Model.
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		return m, nil

	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "q":
			m.quitting = true
			m.result.Aborted = true
			return m, tea.Quit

		case "up", "k":
			if m.cursor > 0 {
				m.cursor--
			}

		case "down", "j":
			switch m.phase {
			case phaseManagers:
				if m.cursor < len(m.managers)-1 {
					m.cursor++
				}
			case phaseSchedule:
				if m.cursor < len(scheduleChoices)-1 {
					m.cursor++
				}
			case phaseDone:
				// nothing to do
			}

		case " ":
			if m.phase == phaseManagers {
				m.managers[m.cursor].selected = !m.managers[m.cursor].selected
			}

		case "enter":
			switch m.phase {
			case phaseManagers:
				for _, mgr := range m.managers {
					if mgr.selected {
						m.result.Managers = append(m.result.Managers, mgr.name)
					}
				}
				// Require at least one manager
				if len(m.result.Managers) == 0 {
					break
				}
				m.phase = phaseSchedule
				m.cursor = m.schedIdx

			case phaseSchedule:
				m.result.Schedule = scheduleChoices[m.cursor]
				m.phase = phaseDone
				return m, tea.Quit

			case phaseDone:
				return m, tea.Quit
			}
		}
	}

	return m, nil
}

// View implements tea.Model.
func (m Model) View() string {
	if m.quitting {
		return ""
	}

	headerStyle := lipgloss.NewStyle().Bold(true).Foreground(ui.ColorPrimary)
	mutedStyle := lipgloss.NewStyle().Foreground(ui.ColorMuted)
	selectedStyle := lipgloss.NewStyle().Foreground(ui.ColorSuccess)
	unavailStyle := lipgloss.NewStyle().Foreground(ui.ColorMuted).Strikethrough(true)

	var b strings.Builder

	b.WriteString("\n")
	fmt.Fprintf(&b, "  %s %s\n\n", ui.IconDiamond, headerStyle.Render("SARASA INIT"))

	switch m.phase {
	case phaseManagers:
		b.WriteString(headerStyle.Render("  Package managers"))
		b.WriteString("\n")
		b.WriteString(mutedStyle.Render("  Space to toggle, Enter to confirm"))
		b.WriteString("\n\n")

		for i, mgr := range m.managers {
			cursor := "  "
			if i == m.cursor {
				cursor = mutedStyle.Render(ui.IconTriangle + " ")
			}

			check := "[ ]"
			if mgr.selected {
				check = selectedStyle.Render("[" + ui.IconCheck + "]")
			}

			name := fmt.Sprintf("%s %s", mgr.icon, mgr.name)
			if !mgr.available {
				name = unavailStyle.Render(name) + mutedStyle.Render(" (not found)")
			}

			fmt.Fprintf(&b, "  %s%s %s\n", cursor, check, name)
		}

	case phaseSchedule:
		b.WriteString(headerStyle.Render("  Upgrade schedule"))
		b.WriteString("\n")
		b.WriteString(mutedStyle.Render("  How often should sarasa check for upgrades?"))
		b.WriteString("\n\n")

		for i, choice := range scheduleChoices {
			cursor := "  "
			if i == m.cursor {
				cursor = mutedStyle.Render(ui.IconTriangle + " ")
			}

			radio := "( )"
			if i == m.cursor {
				radio = selectedStyle.Render("(" + ui.IconDot + ")")
			}

			label := choice.Label
			if choice.Times == nil {
				label = mutedStyle.Render(label)
			}

			fmt.Fprintf(&b, "  %s%s %s\n", cursor, radio, label)
		}

	case phaseDone:
		// final view not rendered; tea.Quit fires before View
	}

	b.WriteString("\n")
	b.WriteString(mutedStyle.Render("  q/ctrl+c to cancel"))
	b.WriteString("\n")

	return b.String()
}

// GetResult returns the wizard result.
func (m Model) GetResult() Result {
	return m.result
}
