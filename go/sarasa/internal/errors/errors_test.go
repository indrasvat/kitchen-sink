package errors_test

import (
	"fmt"
	"testing"

	"github.com/indrasvat/sarasa/internal/errors"
)

func TestCommandError(t *testing.T) {
	err := errors.NewCommandError("brew", []string{"upgrade", "vim"}, "", "error output", 1, fmt.Errorf("exit status 1"))

	if !errors.IsCommandError(err) {
		t.Error("expected IsCommandError to return true")
	}

	expected := "brew failed (exit 1): error output"
	if err.Error() != expected {
		t.Errorf("expected %q, got %q", expected, err.Error())
	}
}

func TestCommandError_NoStderr(t *testing.T) {
	err := errors.NewCommandError("npm", []string{"install"}, "", "", 127, nil)

	expected := "npm failed (exit 127)"
	if err.Error() != expected {
		t.Errorf("expected %q, got %q", expected, err.Error())
	}
}

func TestUpgradeError(t *testing.T) {
	innerErr := fmt.Errorf("permission denied")
	err := errors.NewUpgradeError("npm", "typescript", "5.0.0", "5.1.0", "npm ERR!", innerErr)

	if !errors.IsUpgradeError(err) {
		t.Error("expected IsUpgradeError to return true")
	}

	expected := "failed to upgrade typescript (5.0.0 → 5.1.0): permission denied"
	if err.Error() != expected {
		t.Errorf("expected %q, got %q", expected, err.Error())
	}
}

func TestVersionUnchangedError(t *testing.T) {
	err := errors.NewVersionUnchangedError("npm", "lodash", "4.18.0", "4.17.21")

	if !errors.IsVersionUnchangedError(err) {
		t.Error("expected IsVersionUnchangedError to return true")
	}

	expected := "lodash: version unchanged after upgrade (expected 4.18.0, got 4.17.21)"
	if err.Error() != expected {
		t.Errorf("expected %q, got %q", expected, err.Error())
	}
}

func TestTimeoutError(t *testing.T) {
	err := errors.NewTimeoutError("brew upgrade", "5m")

	if !errors.IsTimeoutError(err) {
		t.Error("expected IsTimeoutError to return true")
	}

	expected := "brew upgrade timed out after 5m"
	if err.Error() != expected {
		t.Errorf("expected %q, got %q", expected, err.Error())
	}
}

func TestManagerUnavailableError(t *testing.T) {
	err := errors.NewManagerUnavailableError("bun")

	if !errors.IsManagerUnavailableError(err) {
		t.Error("expected IsManagerUnavailableError to return true")
	}

	expected := "manager bun is not available"
	if err.Error() != expected {
		t.Errorf("expected %q, got %q", expected, err.Error())
	}
}

func TestIsCheckers_NilError(t *testing.T) {
	if errors.IsCommandError(nil) {
		t.Error("IsCommandError(nil) should return false")
	}
	if errors.IsUpgradeError(nil) {
		t.Error("IsUpgradeError(nil) should return false")
	}
	if errors.IsVersionUnchangedError(nil) {
		t.Error("IsVersionUnchangedError(nil) should return false")
	}
	if errors.IsTimeoutError(nil) {
		t.Error("IsTimeoutError(nil) should return false")
	}
	if errors.IsManagerUnavailableError(nil) {
		t.Error("IsManagerUnavailableError(nil) should return false")
	}
}

func TestIsCheckers_RegularError(t *testing.T) {
	err := fmt.Errorf("regular error")

	if errors.IsCommandError(err) {
		t.Error("IsCommandError should return false for regular error")
	}
	if errors.IsUpgradeError(err) {
		t.Error("IsUpgradeError should return false for regular error")
	}
	if errors.IsVersionUnchangedError(err) {
		t.Error("IsVersionUnchangedError should return false for regular error")
	}
	if errors.IsTimeoutError(err) {
		t.Error("IsTimeoutError should return false for regular error")
	}
	if errors.IsManagerUnavailableError(err) {
		t.Error("IsManagerUnavailableError should return false for regular error")
	}
}
