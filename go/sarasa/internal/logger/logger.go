package logger

import (
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"time"

	"gopkg.in/natefinch/lumberjack.v2"
)

var (
	defaultLogger *slog.Logger
	logWriter     io.WriteCloser
)

// Config holds logger configuration.
type Config struct {
	Dir           string
	Level         slog.Level
	RetentionDays int
}

// DefaultConfig returns the default logger configuration.
func DefaultConfig() Config {
	homeDir, _ := os.UserHomeDir()
	return Config{
		Dir:           filepath.Join(homeDir, "Library", "Logs", "sarasa"),
		Level:         slog.LevelInfo,
		RetentionDays: 30,
	}
}

// Init initializes the global logger with the given configuration.
func Init(cfg Config) error {
	if err := os.MkdirAll(cfg.Dir, 0755); err != nil {
		return err
	}

	// Create daily rotating log file
	logFile := filepath.Join(cfg.Dir, "sarasa.jsonl")
	logWriter = &lumberjack.Logger{
		Filename:   logFile,
		MaxSize:    100, // MB
		MaxBackups: cfg.RetentionDays,
		MaxAge:     cfg.RetentionDays,
		Compress:   true,
		LocalTime:  true,
	}

	handler := slog.NewJSONHandler(logWriter, &slog.HandlerOptions{
		Level: cfg.Level,
		ReplaceAttr: func(groups []string, a slog.Attr) slog.Attr {
			// Rename "time" to "ts" for shorter JSON
			if a.Key == slog.TimeKey {
				a.Key = "ts"
				// Format as ISO8601
				if t, ok := a.Value.Any().(time.Time); ok {
					a.Value = slog.StringValue(t.Format(time.RFC3339))
				}
			}
			return a
		},
	})

	defaultLogger = slog.New(handler)
	slog.SetDefault(defaultLogger)

	return nil
}

// Close closes the log writer.
func Close() error {
	if logWriter != nil {
		return logWriter.Close()
	}
	return nil
}

// Get returns the default logger.
func Get() *slog.Logger {
	if defaultLogger == nil {
		// Return a default stderr logger if not initialized
		return slog.Default()
	}
	return defaultLogger
}

// WithManager returns a logger with the manager attribute set.
func WithManager(manager string) *slog.Logger {
	return Get().With("manager", manager)
}

// LogStart logs the start of an upgrade run for a manager.
func LogStart(manager string) {
	WithManager(manager).Info("Starting upgrade run", "action", "start")
}

// LogOutdated logs outdated packages found.
func LogOutdated(manager string, packages []string) {
	WithManager(manager).Info("Found outdated packages",
		"action", "outdated",
		"count", len(packages),
		"packages", packages,
	)
}

// LogUpgrade logs a package upgrade.
func LogUpgrade(manager, pkg, from, to string, durationMs int64) {
	WithManager(manager).Info("Upgraded package",
		"action", "upgrade",
		"pkg", pkg,
		"from", from,
		"to", to,
		"duration_ms", durationMs,
	)
}

// LogUpgradeError logs a package upgrade error.
func LogUpgradeError(manager, pkg string, err error, durationMs int64) {
	WithManager(manager).Error("Failed to upgrade package",
		"action", "upgrade",
		"pkg", pkg,
		"error", err.Error(),
		"duration_ms", durationMs,
	)
}

// LogCleanup logs cleanup results.
func LogCleanup(manager string, freedMB int64) {
	WithManager(manager).Info("Cleanup completed",
		"action", "cleanup",
		"freed_mb", freedMB,
	)
}

// LogComplete logs completion of a manager run.
func LogComplete(manager string, upgraded, failed int, durationMs int64) {
	WithManager(manager).Info("Upgrade run completed",
		"action", "complete",
		"upgraded", upgraded,
		"failed", failed,
		"duration_ms", durationMs,
	)
}

// LogSkipped logs a skipped package.
func LogSkipped(manager, pkg, reason string) {
	WithManager(manager).Info("Skipped package",
		"action", "skip",
		"pkg", pkg,
		"reason", reason,
	)
}

// ParseLevel parses a log level string.
func ParseLevel(level string) slog.Level {
	switch level {
	case "debug":
		return slog.LevelDebug
	case "info":
		return slog.LevelInfo
	case "warn":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}
