package retry

import (
	"context"
	"errors"
	"math"
	"time"
)

// Config holds retry configuration.
type Config struct {
	MaxAttempts int           // Maximum number of attempts (default: 3)
	InitialWait time.Duration // Initial wait time (default: 1s)
	MaxWait     time.Duration // Maximum wait time (default: 30s)
	Multiplier  float64       // Backoff multiplier (default: 2.0)
}

// DefaultConfig returns a default retry configuration.
func DefaultConfig() Config {
	return Config{
		MaxAttempts: 3,
		InitialWait: 1 * time.Second,
		MaxWait:     30 * time.Second,
		Multiplier:  2.0,
	}
}

// Result holds the result of a retryable operation.
type Result struct {
	Attempts int
	LastErr  error
}

// Do executes the given function with retries using exponential backoff.
// Returns nil on success, or the last error after all attempts are exhausted.
func Do(ctx context.Context, cfg Config, fn func() error) *Result {
	if cfg.MaxAttempts <= 0 {
		cfg.MaxAttempts = 3
	}
	if cfg.InitialWait <= 0 {
		cfg.InitialWait = 1 * time.Second
	}
	if cfg.MaxWait <= 0 {
		cfg.MaxWait = 30 * time.Second
	}
	if cfg.Multiplier <= 0 {
		cfg.Multiplier = 2.0
	}

	result := &Result{}

	for attempt := 1; attempt <= cfg.MaxAttempts; attempt++ {
		result.Attempts = attempt

		err := fn()
		if err == nil {
			result.LastErr = nil
			return result
		}

		result.LastErr = err

		// Don't retry if context is cancelled
		if ctx.Err() != nil {
			return result
		}

		// Don't retry on permanent errors
		if IsPermanent(err) {
			return result
		}

		// Don't wait after the last attempt
		if attempt == cfg.MaxAttempts {
			break
		}

		// Calculate exponential backoff
		wait := cfg.InitialWait * time.Duration(math.Pow(cfg.Multiplier, float64(attempt-1)))
		if wait > cfg.MaxWait {
			wait = cfg.MaxWait
		}

		select {
		case <-ctx.Done():
			return result
		case <-time.After(wait):
			// Continue to next attempt
		}
	}

	return result
}

// PermanentError wraps an error to indicate it should not be retried.
type PermanentError struct {
	Err error
}

func (e *PermanentError) Error() string {
	return e.Err.Error()
}

func (e *PermanentError) Unwrap() error {
	return e.Err
}

// Permanent wraps an error to mark it as permanent (non-retryable).
func Permanent(err error) error {
	if err == nil {
		return nil
	}
	return &PermanentError{Err: err}
}

// IsPermanent checks if an error is marked as permanent.
func IsPermanent(err error) bool {
	var permanent *PermanentError
	return errors.As(err, &permanent)
}
