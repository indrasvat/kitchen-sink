package cmd

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/spf13/cobra"

	logsTUI "github.com/indrasvat/sarasa/internal/tui/logs"
	"github.com/indrasvat/sarasa/internal/ui"
)

var (
	logsDate    string
	logsLevel   string
	logsManager string
	logsTail    int
	logsRaw     bool
	logsUTC     bool
)

var logsCmd = &cobra.Command{
	Use:   "logs",
	Short: "View upgrade logs",
	Long: `View upgrade logs with an interactive TUI viewer.

Examples:
  sarasa logs                         # Interactive log viewer (today's logs)
  sarasa logs --date=2026-01-15       # Logs from specific date
  sarasa logs --tail=50               # Load last 50 entries
  sarasa logs --level=error           # Pre-filter by level
  sarasa logs --manager=brew          # Pre-filter by manager
  sarasa logs --utc                   # Show timestamps in UTC
  sarasa logs --raw                   # Output raw JSONLines (no TUI)

TUI Controls:
  /         Search logs
  1-4       Toggle level filters (DBG/INF/WRN/ERR)
  j/k       Scroll up/down
  g/G       Jump to top/bottom
  Esc       Clear search
  q         Quit`,
	RunE: runLogs,
}

func init() {
	rootCmd.AddCommand(logsCmd)

	logsCmd.Flags().StringVar(&logsDate, "date", "", "date to view logs for (YYYY-MM-DD)")
	logsCmd.Flags().StringVar(&logsLevel, "level", "", "filter by log level (debug, info, warn, error)")
	logsCmd.Flags().StringVar(&logsManager, "manager", "", "filter by manager name")
	logsCmd.Flags().IntVar(&logsTail, "tail", 0, "show last N entries")
	logsCmd.Flags().BoolVar(&logsUTC, "utc", false, "show timestamps in UTC (default: local time)")
	logsCmd.Flags().BoolVar(&logsRaw, "raw", false, "output raw JSONLines")
}

// jsonLogEntry represents a log entry from the JSON file.
type jsonLogEntry struct {
	Timestamp  string `json:"ts"`
	Level      string `json:"level"`
	Message    string `json:"msg"`
	Manager    string `json:"manager,omitempty"`
	Action     string `json:"action,omitempty"`
	Package    string `json:"pkg,omitempty"`
	From       string `json:"from,omitempty"`
	To         string `json:"to,omitempty"`
	Error      string `json:"error,omitempty"`
	DurationMs int64  `json:"duration_ms,omitempty"`
	Count      int    `json:"count,omitempty"`
	Upgraded   int    `json:"upgraded,omitempty"`
	Failed     int    `json:"failed,omitempty"`
	FreedMB    int64  `json:"freed_mb,omitempty"`
}

func runLogs(_ *cobra.Command, _ []string) error {
	cfg := GetConfig()

	// Determine log file path
	logDir := cfg.Logging.Dir
	var logFile string

	if logsDate != "" {
		// Parse and validate date
		_, err := time.Parse("2006-01-02", logsDate)
		if err != nil {
			return fmt.Errorf("invalid date format: %s (expected YYYY-MM-DD)", logsDate)
		}
		logFile = filepath.Join(logDir, fmt.Sprintf("sarasa-%s.jsonl", logsDate))
	} else {
		// Use current log file (lumberjack names it sarasa.jsonl)
		logFile = filepath.Join(logDir, "sarasa.jsonl")
	}

	// Check if file exists
	if _, err := os.Stat(logFile); os.IsNotExist(err) {
		fmt.Printf("No logs found at %s\n", logFile)
		return nil
	}

	// Read log file
	entries, err := readLogFile(logFile)
	if err != nil {
		return err
	}

	if len(entries) == 0 {
		fmt.Println("No log entries found")
		return nil
	}

	// Output raw if requested
	if logsRaw {
		return outputRaw(entries)
	}

	// Detect output mode
	mode := ui.DetectOutputMode()

	switch mode {
	case ui.ModeTUI:
		return runLogsTUI(entries, logsUTC)
	case ui.ModeStyled, ui.ModePlain:
		return runLogsPlain(entries, mode == ui.ModeStyled, logsUTC)
	}

	return nil
}

func readLogFile(logFile string) ([]logsTUI.LogEntry, error) {
	file, err := os.Open(logFile)
	if err != nil {
		return nil, fmt.Errorf("failed to open log file: %w", err)
	}
	defer func() { _ = file.Close() }()

	var entries []logsTUI.LogEntry
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			continue
		}

		var jsonEntry jsonLogEntry
		if err := json.Unmarshal([]byte(line), &jsonEntry); err != nil {
			continue // Skip malformed lines
		}

		// Apply CLI filters
		if logsLevel != "" && !strings.EqualFold(jsonEntry.Level, logsLevel) {
			continue
		}
		if logsManager != "" && jsonEntry.Manager != logsManager {
			continue
		}

		// Convert to TUI entry
		entry := logsTUI.LogEntry{
			Timestamp:  jsonEntry.Timestamp,
			Level:      jsonEntry.Level,
			Message:    jsonEntry.Message,
			Manager:    jsonEntry.Manager,
			Package:    jsonEntry.Package,
			From:       jsonEntry.From,
			To:         jsonEntry.To,
			Error:      jsonEntry.Error,
			DurationMs: jsonEntry.DurationMs,
			Count:      jsonEntry.Count,
			Upgraded:   jsonEntry.Upgraded,
			Failed:     jsonEntry.Failed,
			Raw:        formatEntryRaw(jsonEntry),
		}

		entries = append(entries, entry)
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("error reading log file: %w", err)
	}

	// Apply tail
	if logsTail > 0 && len(entries) > logsTail {
		entries = entries[len(entries)-logsTail:]
	}

	return entries, nil
}

func formatEntryRaw(entry jsonLogEntry) string {
	// Create a searchable raw representation
	parts := []string{entry.Timestamp, entry.Level, entry.Message}
	if entry.Manager != "" {
		parts = append(parts, entry.Manager)
	}
	if entry.Package != "" {
		parts = append(parts, entry.Package)
	}
	if entry.From != "" {
		parts = append(parts, entry.From)
	}
	if entry.To != "" {
		parts = append(parts, entry.To)
	}
	if entry.Error != "" {
		parts = append(parts, entry.Error)
	}
	return strings.Join(parts, " ")
}

func runLogsTUI(entries []logsTUI.LogEntry, useUTC bool) error {
	model := logsTUI.New(entries, useUTC)
	p := tea.NewProgram(model, tea.WithAltScreen())

	_, err := p.Run()
	return err
}

func outputRaw(entries []logsTUI.LogEntry) error {
	for _, entry := range entries {
		jsonEntry := jsonLogEntry{
			Timestamp:  entry.Timestamp,
			Level:      entry.Level,
			Message:    entry.Message,
			Manager:    entry.Manager,
			Package:    entry.Package,
			From:       entry.From,
			To:         entry.To,
			Error:      entry.Error,
			DurationMs: entry.DurationMs,
			Count:      entry.Count,
			Upgraded:   entry.Upgraded,
			Failed:     entry.Failed,
		}
		data, _ := json.Marshal(jsonEntry)
		fmt.Println(string(data))
	}
	return nil
}

func runLogsPlain(entries []logsTUI.LogEntry, styled bool, useUTC bool) error {
	// Color helper
	c := func(code, text string) string {
		if !styled {
			return text
		}
		return code + text + "\033[0m"
	}

	// ANSI codes
	const (
		bold        = "\033[1m"
		dim         = "\033[2m"
		red         = "\033[31m"
		green       = "\033[32m"
		yellow      = "\033[33m"
		blue        = "\033[34m"
		brightCyan  = "\033[96m"
		brightGreen = "\033[92m"
		brightMagenta = "\033[95m"
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
		default:
			return brightCyan
		}
	}

	for _, entry := range entries {
		// Timestamp - format based on useUTC flag
		ts := entry.Timestamp
		if t, err := time.Parse(time.RFC3339, ts); err == nil {
			if useUTC {
				ts = t.UTC().Format(time.RFC3339)
			} else {
				ts = t.Local().Format("2006-01-02T15:04:05")
			}
		}

		// Level
		var levelStr string
		switch strings.ToLower(entry.Level) {
		case "debug":
			levelStr = c(dim, "[DBG]")
		case "info":
			levelStr = c(green, "[INF]")
		case "warn", "warning":
			levelStr = c(yellow, "[WRN]")
		case "error":
			levelStr = c(bold+red, "[ERR]")
		default:
			levelStr = fmt.Sprintf("[%s]", strings.ToUpper(entry.Level))
		}

		// Manager
		managerStr := ""
		if entry.Manager != "" {
			managerStr = c(bold+managerColor(entry.Manager), fmt.Sprintf("[%s]", entry.Manager)) + " "
		}

		// Message
		msg := entry.Message

		// Details
		var details []string
		if entry.Package != "" {
			if entry.From != "" && entry.To != "" {
				details = append(details, fmt.Sprintf("%s %s", c(brightCyan, entry.Package), c(brightGreen, entry.From+"→"+entry.To)))
			} else {
				details = append(details, c(brightCyan, entry.Package))
			}
		}
		if entry.DurationMs > 0 {
			details = append(details, c(dim, formatDurationMs(entry.DurationMs)))
		}
		if entry.Upgraded > 0 || entry.Failed > 0 {
			details = append(details, fmt.Sprintf("%s%d %s%d", c(green, "✓"), entry.Upgraded, c(red, "✗"), entry.Failed))
		}
		if entry.Count > 0 {
			details = append(details, fmt.Sprintf("count=%d", entry.Count))
		}
		if entry.Error != "" {
			details = append(details, c(red, entry.Error))
		}

		detailsStr := ""
		if len(details) > 0 {
			detailsStr = c(dim, " (") + strings.Join(details, c(dim, ", ")) + c(dim, ")")
		}

		fmt.Printf("%s %s %s%s%s\n", c(dim, ts), levelStr, managerStr, msg, detailsStr)
	}

	return nil
}

func formatDurationMs(ms int64) string {
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
