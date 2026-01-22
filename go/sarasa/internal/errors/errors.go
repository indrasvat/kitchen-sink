package errors

import (
	"errors"
	"fmt"
)

// CommandError represents a command execution failure.
type CommandError struct {
	Command  string
	Args     []string
	Stdout   string
	Stderr   string
	ExitCode int
	Err      error
}

func (e *CommandError) Error() string {
	if e.Stderr != "" {
		return fmt.Sprintf("%s failed (exit %d): %s", e.Command, e.ExitCode, e.Stderr)
	}
	return fmt.Sprintf("%s failed (exit %d)", e.Command, e.ExitCode)
}

func (e *CommandError) Unwrap() error {
	return e.Err
}

// NewCommandError creates a new CommandError.
func NewCommandError(cmd string, args []string, stdout, stderr string, exitCode int, err error) *CommandError {
	return &CommandError{
		Command:  cmd,
		Args:     args,
		Stdout:   stdout,
		Stderr:   stderr,
		ExitCode: exitCode,
		Err:      err,
	}
}

// ParseError represents a parsing failure.
type ParseError struct {
	Manager string
	Data    string
	Err     error
}

func (e *ParseError) Error() string {
	return fmt.Sprintf("failed to parse %s output: %v", e.Manager, e.Err)
}

func (e *ParseError) Unwrap() error {
	return e.Err
}

// NewParseError creates a new ParseError.
func NewParseError(manager, data string, err error) *ParseError {
	return &ParseError{
		Manager: manager,
		Data:    data,
		Err:     err,
	}
}

// UpgradeError represents an upgrade failure.
type UpgradeError struct {
	Manager string
	Package string
	From    string
	To      string
	Output  string
	Err     error
}

func (e *UpgradeError) Error() string {
	return fmt.Sprintf("failed to upgrade %s (%s → %s): %v", e.Package, e.From, e.To, e.Err)
}

func (e *UpgradeError) Unwrap() error {
	return e.Err
}

// NewUpgradeError creates a new UpgradeError.
func NewUpgradeError(manager, pkg, from, to, output string, err error) *UpgradeError {
	return &UpgradeError{
		Manager: manager,
		Package: pkg,
		From:    from,
		To:      to,
		Output:  output,
		Err:     err,
	}
}

// VersionUnchangedError indicates an upgrade completed but the version didn't change.
type VersionUnchangedError struct {
	Manager  string
	Package  string
	Expected string
	Actual   string
}

func (e *VersionUnchangedError) Error() string {
	return fmt.Sprintf("%s: version unchanged after upgrade (expected %s, got %s)", e.Package, e.Expected, e.Actual)
}

// NewVersionUnchangedError creates a new VersionUnchangedError.
func NewVersionUnchangedError(manager, pkg, expected, actual string) *VersionUnchangedError {
	return &VersionUnchangedError{
		Manager:  manager,
		Package:  pkg,
		Expected: expected,
		Actual:   actual,
	}
}

// TimeoutError indicates an operation timed out.
type TimeoutError struct {
	Operation string
	Duration  string
}

func (e *TimeoutError) Error() string {
	return fmt.Sprintf("%s timed out after %s", e.Operation, e.Duration)
}

// NewTimeoutError creates a new TimeoutError.
func NewTimeoutError(operation, duration string) *TimeoutError {
	return &TimeoutError{
		Operation: operation,
		Duration:  duration,
	}
}

// ManagerUnavailableError indicates a manager is not installed.
type ManagerUnavailableError struct {
	Manager string
}

func (e *ManagerUnavailableError) Error() string {
	return fmt.Sprintf("manager %s is not available", e.Manager)
}

// NewManagerUnavailableError creates a new ManagerUnavailableError.
func NewManagerUnavailableError(manager string) *ManagerUnavailableError {
	return &ManagerUnavailableError{Manager: manager}
}

// IsCommandError checks if an error is a CommandError.
func IsCommandError(err error) bool {
	var cmdErr *CommandError
	return errors.As(err, &cmdErr)
}

// IsParseError checks if an error is a ParseError.
func IsParseError(err error) bool {
	var parseErr *ParseError
	return errors.As(err, &parseErr)
}

// IsUpgradeError checks if an error is an UpgradeError.
func IsUpgradeError(err error) bool {
	var upgradeErr *UpgradeError
	return errors.As(err, &upgradeErr)
}

// IsVersionUnchangedError checks if an error is a VersionUnchangedError.
func IsVersionUnchangedError(err error) bool {
	var versionErr *VersionUnchangedError
	return errors.As(err, &versionErr)
}

// IsTimeoutError checks if an error is a TimeoutError.
func IsTimeoutError(err error) bool {
	var timeoutErr *TimeoutError
	return errors.As(err, &timeoutErr)
}

// IsManagerUnavailableError checks if an error is a ManagerUnavailableError.
func IsManagerUnavailableError(err error) bool {
	var managerErr *ManagerUnavailableError
	return errors.As(err, &managerErr)
}
