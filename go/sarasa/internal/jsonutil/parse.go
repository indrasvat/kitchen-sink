package jsonutil

import (
	"encoding/json"
	"fmt"

	"github.com/indrasvat/sarasa/internal/logger"
)

// ParseError contains detailed information about a JSON parse failure.
type ParseError struct {
	Manager   string // Which manager failed
	Operation string // What operation was being performed
	RawOutput string // The raw output that failed to parse
	Err       error  // The underlying error
}

func (e *ParseError) Error() string {
	return fmt.Sprintf("%s: failed to parse %s output", e.Manager, e.Operation)
}

func (e *ParseError) Unwrap() error {
	return e.Err
}

// DetailedError returns a verbose error message for logging.
func (e *ParseError) DetailedError() string {
	return fmt.Sprintf("%s %s parse failed: %v\nRaw output:\n%s",
		e.Manager, e.Operation, e.Err, e.RawOutput)
}

// Parse unmarshals JSON with detailed error capture.
// On failure, it logs the full details and returns a clean error for display.
func Parse(manager, operation string, data []byte, v any) error {
	if err := json.Unmarshal(data, v); err != nil {
		parseErr := &ParseError{
			Manager:   manager,
			Operation: operation,
			RawOutput: string(data),
			Err:       err,
		}

		// Log full details for debugging
		log := logger.Get()
		if log != nil {
			log.Error("JSON parse failed - tool output format may have changed",
				"manager", manager,
				"operation", operation,
				"error", err.Error(),
				"raw_output", truncateForLog(string(data), 2000),
			)
		}

		return parseErr
	}
	return nil
}

// truncateForLog shortens output for log entries.
func truncateForLog(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen] + fmt.Sprintf("... [truncated, %d bytes total]", len(s))
}
