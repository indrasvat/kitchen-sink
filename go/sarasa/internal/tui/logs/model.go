package logs

import (
	"fmt"
	"regexp"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/textinput"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/indrasvat/sarasa/internal/ui"
)

// LogEntry represents a parsed log entry.
type LogEntry struct {
	Timestamp  string
	Level      string
	Message    string
	Manager    string
	Package    string
	From       string
	To         string
	Error      string
	DurationMs int64
	Count      int
	Upgraded   int
	Failed     int
	Raw        string // Original formatted line
}

// Model is the bubbletea model for the logs viewer.
type Model struct {
	entries     []LogEntry
	filtered    []LogEntry
	viewport    viewport.Model
	searchInput textinput.Model
	searching   bool
	searchQuery string
	width       int
	height      int
	ready       bool

	// Filters
	showDebug bool
	showInfo  bool
	showWarn  bool
	showError bool

	// Display options
	useUTC bool
}

// recalcViewportHeight adjusts viewport height based on current UI state.
func (m *Model) recalcViewportHeight() {
	if !m.ready || m.height == 0 {
		return
	}

	headerHeight := 3 // Header + blank line
	footerHeight := 5 // Status bar + help + padding
	searchHeight := 0
	if m.searching {
		searchHeight = 5 // Search bar (3 lines with border) + blank lines
	} else if m.searchQuery != "" {
		searchHeight = 2 // Search indicator + blank line
	}

	m.viewport.Height = m.height - headerHeight - footerHeight - searchHeight
}

// Styles for log levels
var (
	styleTimestamp = lipgloss.NewStyle().
			Foreground(lipgloss.AdaptiveColor{Light: "#666666", Dark: "#888888"})

	styleLevelDebug = lipgloss.NewStyle().
			Foreground(lipgloss.AdaptiveColor{Light: "#999999", Dark: "#666666"})

	styleLevelInfo = lipgloss.NewStyle().
			Foreground(lipgloss.AdaptiveColor{Light: "#228B22", Dark: "#32CD32"})

	styleLevelWarn = lipgloss.NewStyle().
			Foreground(lipgloss.AdaptiveColor{Light: "#CC8800", Dark: "#FFD700"})

	styleLevelError = lipgloss.NewStyle().
			Foreground(lipgloss.AdaptiveColor{Light: "#CC0000", Dark: "#FF6B6B"}).
			Bold(true)

	styleManager = func(name string) lipgloss.Style {
		return lipgloss.NewStyle().Foreground(ui.ManagerColor(name)).Bold(true)
	}

	stylePackage = lipgloss.NewStyle().
			Foreground(lipgloss.AdaptiveColor{Light: "#0066CC", Dark: "#00BFFF"})

	styleVersion = lipgloss.NewStyle().
			Foreground(lipgloss.AdaptiveColor{Light: "#228B22", Dark: "#32CD32"})

	styleDuration = lipgloss.NewStyle().
			Foreground(lipgloss.AdaptiveColor{Light: "#666666", Dark: "#888888"})

	styleSearchMatch = lipgloss.NewStyle().
				Background(lipgloss.AdaptiveColor{Light: "#FFFF00", Dark: "#444400"}).
				Foreground(lipgloss.AdaptiveColor{Light: "#000000", Dark: "#FFFFFF"})

	styleHeader = lipgloss.NewStyle().
			Bold(true).
			Foreground(ui.ColorPrimary).
			MarginLeft(2)

	styleHelp = lipgloss.NewStyle().
			Foreground(ui.ColorMuted).
			MarginLeft(2)

	styleSearchBar = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(ui.ColorPrimary).
			Padding(0, 1).
			MarginLeft(2)

	styleStatusBar = lipgloss.NewStyle().
			Foreground(ui.ColorMuted).
			MarginLeft(2)
)

// New creates a new logs viewer model.
// If useUTC is true, timestamps are shown in UTC; otherwise local time is used.
func New(entries []LogEntry, useUTC bool) Model {
	ti := textinput.New()
	ti.Placeholder = "Search..."
	ti.CharLimit = 100
	ti.Width = 40

	m := Model{
		entries:     entries,
		searchInput: ti,
		showDebug:   true,
		showInfo:    true,
		showWarn:    true,
		showError:   true,
		useUTC:      useUTC,
	}

	m.applyFilters()
	return m
}

// Init initializes the model.
func (m Model) Init() tea.Cmd {
	return nil
}

// Update handles messages.
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.KeyMsg:
		if m.searching {
			switch msg.String() {
			case "enter":
				m.searchQuery = m.searchInput.Value()
				m.searching = false
				m.searchInput.Blur()
				m.applyFilters()
				m.recalcViewportHeight()
				m.updateViewportContent()
				return m, nil
			case "esc":
				m.searching = false
				m.searchInput.Blur()
				m.searchInput.SetValue(m.searchQuery) // Restore previous query
				m.recalcViewportHeight()
				return m, nil
			default:
				var cmd tea.Cmd
				m.searchInput, cmd = m.searchInput.Update(msg)
				return m, cmd
			}
		}

		switch msg.String() {
		case "q", "ctrl+c":
			return m, tea.Quit
		case "/":
			m.searching = true
			m.searchInput.Focus()
			m.recalcViewportHeight()
			return m, textinput.Blink
		case "esc":
			if m.searchQuery != "" {
				m.searchQuery = ""
				m.searchInput.SetValue("")
				m.applyFilters()
				m.recalcViewportHeight()
				m.updateViewportContent()
			}
			return m, nil
		case "1":
			m.showDebug = !m.showDebug
			m.applyFilters()
			m.updateViewportContent()
			return m, nil
		case "2":
			m.showInfo = !m.showInfo
			m.applyFilters()
			m.updateViewportContent()
			return m, nil
		case "3":
			m.showWarn = !m.showWarn
			m.applyFilters()
			m.updateViewportContent()
			return m, nil
		case "4":
			m.showError = !m.showError
			m.applyFilters()
			m.updateViewportContent()
			return m, nil
		case "g":
			m.viewport.GotoTop()
			return m, nil
		case "G":
			m.viewport.GotoBottom()
			return m, nil
		}

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height

		if !m.ready {
			// Initial viewport setup with placeholder height
			m.viewport = viewport.New(msg.Width-4, 10)
			m.viewport.YPosition = 3 // Below header
			m.ready = true
		} else {
			m.viewport.Width = msg.Width - 4
		}
		m.recalcViewportHeight()
		m.updateViewportContent()
	}

	// Handle viewport scrolling
	var cmd tea.Cmd
	m.viewport, cmd = m.viewport.Update(msg)
	cmds = append(cmds, cmd)

	return m, tea.Batch(cmds...)
}

// View renders the UI.
func (m Model) View() string {
	if !m.ready {
		return "\n  Loading logs..."
	}

	var b strings.Builder

	// Header
	b.WriteString("\n")
	header := fmt.Sprintf("%s SARASA LOGS", ui.IconDiamond)
	b.WriteString(styleHeader.Render(header))
	b.WriteString("\n\n")

	// Search bar (if searching)
	if m.searching {
		searchBar := styleSearchBar.Render("/ " + m.searchInput.View())
		b.WriteString(searchBar)
		b.WriteString("\n\n")
	} else if m.searchQuery != "" {
		searchIndicator := styleStatusBar.Render(fmt.Sprintf("Search: %q (Esc to clear)", m.searchQuery))
		b.WriteString(searchIndicator)
		b.WriteString("\n\n")
	}

	// Viewport with logs
	viewportStyle := lipgloss.NewStyle().MarginLeft(2)
	b.WriteString(viewportStyle.Render(m.viewport.View()))
	b.WriteString("\n")

	// Status bar
	filters := []string{}
	if m.showDebug {
		filters = append(filters, styleLevelDebug.Render("DBG"))
	}
	if m.showInfo {
		filters = append(filters, styleLevelInfo.Render("INF"))
	}
	if m.showWarn {
		filters = append(filters, styleLevelWarn.Render("WRN"))
	}
	if m.showError {
		filters = append(filters, styleLevelError.Render("ERR"))
	}

	statusLeft := fmt.Sprintf("%d/%d entries", len(m.filtered), len(m.entries))
	statusRight := fmt.Sprintf("Showing: %s", strings.Join(filters, " "))
	status := styleStatusBar.Render(fmt.Sprintf("%s  |  %s", statusLeft, statusRight))
	b.WriteString("\n")
	b.WriteString(status)
	b.WriteString("\n")

	// Help
	var helpText string
	if m.searching {
		helpText = "Enter confirm  ·  Esc cancel"
	} else {
		helpText = "/ search  ·  1-4 toggle levels  ·  g/G top/bottom  ·  q quit"
	}
	b.WriteString(styleHelp.Render(helpText))
	b.WriteString("\n")

	return b.String()
}

// applyFilters filters entries based on current filter settings.
func (m *Model) applyFilters() {
	m.filtered = nil

	for _, entry := range m.entries {
		// Level filter
		level := strings.ToLower(entry.Level)
		switch level {
		case "debug":
			if !m.showDebug {
				continue
			}
		case "info":
			if !m.showInfo {
				continue
			}
		case "warn", "warning":
			if !m.showWarn {
				continue
			}
		case "error":
			if !m.showError {
				continue
			}
		}

		// Search filter
		if m.searchQuery != "" {
			searchLower := strings.ToLower(m.searchQuery)
			rawLower := strings.ToLower(entry.Raw)
			if !strings.Contains(rawLower, searchLower) {
				continue
			}
		}

		m.filtered = append(m.filtered, entry)
	}
}

// updateViewportContent renders filtered entries into the viewport.
func (m *Model) updateViewportContent() {
	if !m.ready {
		return
	}

	var lines []string
	for _, entry := range m.filtered {
		line := m.renderEntry(entry)
		lines = append(lines, line)
	}

	content := strings.Join(lines, "\n")
	m.viewport.SetContent(content)
}

// renderEntry renders a single log entry with colors.
func (m *Model) renderEntry(entry LogEntry) string {
	var parts []string

	// Timestamp - format based on useUTC flag
	ts := entry.Timestamp
	if t, err := time.Parse(time.RFC3339, ts); err == nil {
		if m.useUTC {
			ts = t.UTC().Format(time.RFC3339)
		} else {
			ts = t.Local().Format("2006-01-02T15:04:05")
		}
	}
	parts = append(parts, styleTimestamp.Render(ts))

	// Level
	level := strings.ToUpper(entry.Level)
	var levelStyled string
	switch strings.ToLower(entry.Level) {
	case "debug":
		levelStyled = styleLevelDebug.Render("[DBG]")
	case "info":
		levelStyled = styleLevelInfo.Render("[INF]")
	case "warn", "warning":
		levelStyled = styleLevelWarn.Render("[WRN]")
	case "error":
		levelStyled = styleLevelError.Render("[ERR]")
	default:
		levelStyled = fmt.Sprintf("[%s]", level)
	}
	parts = append(parts, levelStyled)

	// Manager prefix
	if entry.Manager != "" {
		managerStyled := styleManager(entry.Manager).Render(fmt.Sprintf("[%s]", entry.Manager))
		parts = append(parts, managerStyled)
	}

	// Message
	msg := entry.Message

	// Highlight search matches
	if m.searchQuery != "" {
		msg = highlightMatches(msg, m.searchQuery)
	}

	parts = append(parts, msg)

	// Details
	var details []string
	if entry.Package != "" {
		pkg := stylePackage.Render(entry.Package)
		if entry.From != "" && entry.To != "" {
			version := styleVersion.Render(fmt.Sprintf("%s→%s", entry.From, entry.To))
			details = append(details, fmt.Sprintf("%s %s", pkg, version))
		} else {
			details = append(details, fmt.Sprintf("pkg=%s", pkg))
		}
	}
	if entry.DurationMs > 0 {
		dur := styleDuration.Render(formatDuration(entry.DurationMs))
		details = append(details, dur)
	}
	if entry.Upgraded > 0 || entry.Failed > 0 {
		upgraded := styleLevelInfo.Render(fmt.Sprintf("✓%d", entry.Upgraded))
		failed := ""
		if entry.Failed > 0 {
			failed = styleLevelError.Render(fmt.Sprintf(" ✗%d", entry.Failed))
		}
		details = append(details, upgraded+failed)
	}
	if entry.Count > 0 {
		details = append(details, fmt.Sprintf("count=%d", entry.Count))
	}
	if entry.Error != "" {
		errStyled := styleLevelError.Render(entry.Error)
		details = append(details, errStyled)
	}

	if len(details) > 0 {
		detailsStr := styleDuration.Render("(") + strings.Join(details, styleDuration.Render(", ")) + styleDuration.Render(")")
		parts = append(parts, detailsStr)
	}

	return strings.Join(parts, " ")
}

// highlightMatches highlights search matches in text.
func highlightMatches(text, query string) string {
	if query == "" {
		return text
	}

	// Case-insensitive replace with highlighting
	re := regexp.MustCompile("(?i)" + regexp.QuoteMeta(query))
	return re.ReplaceAllStringFunc(text, func(match string) string {
		return styleSearchMatch.Render(match)
	})
}

// formatDuration formats milliseconds into a readable duration.
func formatDuration(ms int64) string {
	if ms < 1000 {
		return fmt.Sprintf("%dms", ms)
	}
	if ms < 60000 {
		return fmt.Sprintf("%.1fs", float64(ms)/1000)
	}
	minutes := ms / 60000
	seconds := (ms % 60000) / 1000
	return fmt.Sprintf("%dm%ds", minutes, seconds)
}
