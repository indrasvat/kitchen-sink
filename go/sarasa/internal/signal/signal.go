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

// SetupHandler sets up signal handlers and returns a channel that receives
// true when a signal is caught. Call the returned cleanup function when done.
func SetupHandler() (<-chan struct{}, func()) {
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)

	doneCh := make(chan struct{})

	go func() {
		<-sigCh
		close(doneCh)
	}()

	cleanup := func() {
		signal.Stop(sigCh)
		close(sigCh)
	}

	return doneCh, cleanup
}
