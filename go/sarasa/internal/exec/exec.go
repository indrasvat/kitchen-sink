package exec

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os/exec"
	"time"

	"github.com/indrasvat/sarasa/internal/process"
	"github.com/indrasvat/sarasa/internal/retry"
)

// DefaultTimeout is the default command timeout.
const DefaultTimeout = 5 * time.Minute

// Result holds the result of a command execution.
type Result struct {
	Stdout   []byte
	Stderr   []byte
	ExitCode int
	Duration time.Duration
	Attempts int
}

// Options configures command execution.
type Options struct {
	Timeout     time.Duration // Command timeout (default: 5m)
	Retry       bool          // Whether to retry on failure
	RetryConfig retry.Config  // Retry configuration
	Env         map[string]string
}

// DefaultOptions returns default execution options.
func DefaultOptions() Options {
	return Options{
		Timeout:     DefaultTimeout,
		Retry:       false,
		RetryConfig: retry.DefaultConfig(),
	}
}

// Run executes a command with timeout and optional retry.
func Run(ctx context.Context, opts Options, name string, args ...string) (*Result, error) {
	if opts.Timeout <= 0 {
		opts.Timeout = DefaultTimeout
	}

	result := &Result{}
	start := time.Now()

	runOnce := func() error {
		cmdCtx, cancel := context.WithTimeout(ctx, opts.Timeout)
		defer cancel()

		cmd := exec.CommandContext(cmdCtx, name, args...)
		process.Configure(cmd, opts.Env)
		markDone := configureCancel(cmd)
		var stdout, stderr bytes.Buffer
		cmd.Stdout = &stdout
		cmd.Stderr = &stderr

		err := cmd.Run()
		markDone()
		result.Stdout = stdout.Bytes()
		result.Stderr = stderr.Bytes()
		result.Duration = time.Since(start)

		if err != nil {
			var exitErr *exec.ExitError
			if errors.As(err, &exitErr) {
				result.ExitCode = exitErr.ExitCode()
			} else {
				result.ExitCode = -1
			}

			// Context timeout/cancel is permanent
			if cmdCtx.Err() != nil {
				return retry.Permanent(fmt.Errorf("command timed out after %v: %w", opts.Timeout, err))
			}

			return err
		}

		result.ExitCode = 0
		return nil
	}

	if opts.Retry {
		retryResult := retry.Do(ctx, opts.RetryConfig, runOnce)
		result.Attempts = retryResult.Attempts
		if retryResult.LastErr != nil {
			return result, retryResult.LastErr
		}
		return result, nil
	}

	result.Attempts = 1
	if err := runOnce(); err != nil {
		return result, err
	}
	return result, nil
}

// Output executes a command and returns stdout.
func Output(ctx context.Context, opts Options, name string, args ...string) ([]byte, error) {
	result, err := Run(ctx, opts, name, args...)
	if err != nil {
		return result.Stdout, err
	}
	return result.Stdout, nil
}

// CombinedOutput executes a command and returns combined stdout+stderr.
func CombinedOutput(ctx context.Context, opts Options, name string, args ...string) ([]byte, error) {
	result, err := Run(ctx, opts, name, args...)
	combined := make([]byte, 0, len(result.Stdout)+len(result.Stderr))
	combined = append(combined, result.Stdout...)
	combined = append(combined, result.Stderr...)
	if err != nil {
		return combined, err
	}
	return combined, nil
}
