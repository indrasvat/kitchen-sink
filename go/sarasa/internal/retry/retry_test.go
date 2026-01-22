package retry_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/indrasvat/sarasa/internal/retry"
)

func TestDo_Success(t *testing.T) {
	cfg := retry.Config{
		MaxAttempts: 3,
		InitialWait: 10 * time.Millisecond,
		MaxWait:     100 * time.Millisecond,
		Multiplier:  2.0,
	}

	calls := 0
	result := retry.Do(context.Background(), cfg, func() error {
		calls++
		return nil
	})

	if result.Attempts != 1 {
		t.Errorf("expected 1 attempt, got %d", result.Attempts)
	}
	if result.LastErr != nil {
		t.Errorf("expected no error, got %v", result.LastErr)
	}
	if calls != 1 {
		t.Errorf("expected 1 call, got %d", calls)
	}
}

func TestDo_RetryThenSuccess(t *testing.T) {
	cfg := retry.Config{
		MaxAttempts: 3,
		InitialWait: 10 * time.Millisecond,
		MaxWait:     100 * time.Millisecond,
		Multiplier:  2.0,
	}

	calls := 0
	result := retry.Do(context.Background(), cfg, func() error {
		calls++
		if calls < 3 {
			return errors.New("transient error")
		}
		return nil
	})

	if result.Attempts != 3 {
		t.Errorf("expected 3 attempts, got %d", result.Attempts)
	}
	if result.LastErr != nil {
		t.Errorf("expected no error, got %v", result.LastErr)
	}
	if calls != 3 {
		t.Errorf("expected 3 calls, got %d", calls)
	}
}

func TestDo_AllAttemptsFail(t *testing.T) {
	cfg := retry.Config{
		MaxAttempts: 3,
		InitialWait: 10 * time.Millisecond,
		MaxWait:     100 * time.Millisecond,
		Multiplier:  2.0,
	}

	calls := 0
	expectedErr := errors.New("persistent error")
	result := retry.Do(context.Background(), cfg, func() error {
		calls++
		return expectedErr
	})

	if result.Attempts != 3 {
		t.Errorf("expected 3 attempts, got %d", result.Attempts)
	}
	if result.LastErr == nil {
		t.Error("expected error, got nil")
	}
	if calls != 3 {
		t.Errorf("expected 3 calls, got %d", calls)
	}
}

func TestDo_PermanentError(t *testing.T) {
	cfg := retry.Config{
		MaxAttempts: 3,
		InitialWait: 10 * time.Millisecond,
		MaxWait:     100 * time.Millisecond,
		Multiplier:  2.0,
	}

	calls := 0
	result := retry.Do(context.Background(), cfg, func() error {
		calls++
		return retry.Permanent(errors.New("permanent error"))
	})

	if result.Attempts != 1 {
		t.Errorf("expected 1 attempt for permanent error, got %d", result.Attempts)
	}
	if result.LastErr == nil {
		t.Error("expected error, got nil")
	}
	if calls != 1 {
		t.Errorf("expected 1 call for permanent error, got %d", calls)
	}
}

func TestDo_ContextCancelled(t *testing.T) {
	cfg := retry.Config{
		MaxAttempts: 10,
		InitialWait: 100 * time.Millisecond,
		MaxWait:     1 * time.Second,
		Multiplier:  2.0,
	}

	ctx, cancel := context.WithCancel(context.Background())
	calls := 0

	go func() {
		time.Sleep(50 * time.Millisecond)
		cancel()
	}()

	result := retry.Do(ctx, cfg, func() error {
		calls++
		return errors.New("error")
	})

	// Should have stopped early due to context cancellation
	if result.Attempts >= 10 {
		t.Errorf("expected fewer than 10 attempts, got %d", result.Attempts)
	}
}

func TestIsPermanent(t *testing.T) {
	regularErr := errors.New("regular error")
	permanentErr := retry.Permanent(errors.New("permanent error"))

	if retry.IsPermanent(regularErr) {
		t.Error("regular error should not be permanent")
	}

	if !retry.IsPermanent(permanentErr) {
		t.Error("permanent error should be permanent")
	}

	if retry.IsPermanent(nil) {
		t.Error("nil should not be permanent")
	}
}

func TestPermanent_Nil(t *testing.T) {
	if retry.Permanent(nil) != nil {
		t.Error("Permanent(nil) should return nil")
	}
}

func TestDefaultConfig(t *testing.T) {
	cfg := retry.DefaultConfig()

	if cfg.MaxAttempts != 3 {
		t.Errorf("expected MaxAttempts=3, got %d", cfg.MaxAttempts)
	}
	if cfg.InitialWait != 1*time.Second {
		t.Errorf("expected InitialWait=1s, got %v", cfg.InitialWait)
	}
	if cfg.MaxWait != 30*time.Second {
		t.Errorf("expected MaxWait=30s, got %v", cfg.MaxWait)
	}
	if cfg.Multiplier != 2.0 {
		t.Errorf("expected Multiplier=2.0, got %f", cfg.Multiplier)
	}
}
