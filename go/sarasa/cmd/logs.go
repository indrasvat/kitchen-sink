package cmd

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/spf13/cobra"
)

var (
	logsDate    string
	logsLevel   string
	logsManager string
	logsTail    int
	logsRaw     bool
)

var logsCmd = &cobra.Command{
	Use:   "logs",
	Short: "View upgrade logs",
	Long: `View upgrade logs with filtering options.

Examples:
  sarasa logs                         # Today's logs
  sarasa logs --date=2026-01-15       # Specific date
  sarasa logs --tail=50               # Last 50 entries
  sarasa logs --level=error           # Filter by level
  sarasa logs --manager=brew          # Filter by manager
  sarasa logs --raw                   # Output raw JSONLines`,
	RunE: runLogs,
}

func init() {
	rootCmd.AddCommand(logsCmd)

	logsCmd.Flags().StringVar(&logsDate, "date", "", "date to view logs for (YYYY-MM-DD)")
	logsCmd.Flags().StringVar(&logsLevel, "level", "", "filter by log level (debug, info, warn, error)")
	logsCmd.Flags().StringVar(&logsManager, "manager", "", "filter by manager name")
	logsCmd.Flags().IntVar(&logsTail, "tail", 0, "show last N entries")
	logsCmd.Flags().BoolVar(&logsRaw, "raw", false, "output raw JSONLines")
}

// LogEntry represents a single log entry.
type LogEntry struct {
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
		fmt.Printf("No logs found for %s\n", logFile)
		return nil
	}

	// Read log file
	file, err := os.Open(logFile)
	if err != nil {
		return fmt.Errorf("failed to open log file: %w", err)
	}
	defer func() { _ = file.Close() }()

	var entries []LogEntry
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			continue
		}

		var entry LogEntry
		if err := json.Unmarshal([]byte(line), &entry); err != nil {
			continue // Skip malformed lines
		}

		// Apply filters
		if logsLevel != "" && !strings.EqualFold(entry.Level, logsLevel) {
			continue
		}
		if logsManager != "" && entry.Manager != logsManager {
			continue
		}

		entries = append(entries, entry)
	}

	if err := scanner.Err(); err != nil {
		return fmt.Errorf("error reading log file: %w", err)
	}

	// Apply tail
	if logsTail > 0 && len(entries) > logsTail {
		entries = entries[len(entries)-logsTail:]
	}

	// Output
	if logsRaw {
		for _, entry := range entries {
			data, _ := json.Marshal(entry)
			fmt.Println(string(data))
		}
		return nil
	}

	// Human-readable output
	for _, entry := range entries {
		printLogEntry(entry)
	}

	return nil
}

func printLogEntry(entry LogEntry) {
	// Parse timestamp
	ts := entry.Timestamp
	if t, err := time.Parse(time.RFC3339, ts); err == nil {
		ts = t.Format("15:04:05")
	}

	// Level color/prefix
	levelPrefix := ""
	switch strings.ToLower(entry.Level) {
	case "debug":
		levelPrefix = "[DBG]"
	case "info":
		levelPrefix = "[INF]"
	case "warn":
		levelPrefix = "[WRN]"
	case "error":
		levelPrefix = "[ERR]"
	}

	// Build message
	msg := entry.Message
	if entry.Manager != "" {
		msg = fmt.Sprintf("[%s] %s", entry.Manager, msg)
	}

	// Add details
	details := []string{}
	if entry.Package != "" {
		details = append(details, fmt.Sprintf("pkg=%s", entry.Package))
	}
	if entry.From != "" && entry.To != "" {
		details = append(details, fmt.Sprintf("%s->%s", entry.From, entry.To))
	}
	if entry.Error != "" {
		details = append(details, fmt.Sprintf("error=%s", entry.Error))
	}
	if entry.DurationMs > 0 {
		details = append(details, fmt.Sprintf("duration=%dms", entry.DurationMs))
	}
	if entry.Upgraded > 0 || entry.Failed > 0 {
		details = append(details, fmt.Sprintf("upgraded=%d failed=%d", entry.Upgraded, entry.Failed))
	}
	if entry.Count > 0 {
		details = append(details, fmt.Sprintf("count=%d", entry.Count))
	}

	if len(details) > 0 {
		msg = fmt.Sprintf("%s (%s)", msg, strings.Join(details, ", "))
	}

	fmt.Printf("%s %s %s\n", ts, levelPrefix, msg)
}
