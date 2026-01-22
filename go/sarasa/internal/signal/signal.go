package signal

import (
	"context"
	"os"
	"os/signal"
	"syscall"
)

// NotifyContext returns a context that is cancelled when an interrupt
// or termination signal is received.
func NotifyContext(parent context.Context) (context.Context, context.CancelFunc) {
	return signal.NotifyContext(parent, os.Interrupt, syscall.SIGTERM)
}
