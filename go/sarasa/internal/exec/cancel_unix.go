//go:build !windows

package exec

import (
	"os"
	"os/exec"
	"sync"
	"syscall"
	"time"
)

func configureCancel(cmd *exec.Cmd) func() {
	done := make(chan struct{})
	var doneOnce sync.Once
	markDone := func() {
		doneOnce.Do(func() {
			close(done)
		})
	}

	cmd.Cancel = func() error {
		if cmd.Process == nil {
			return os.ErrProcessDone
		}
		pgid := cmd.Process.Pid
		if err := syscall.Kill(-pgid, syscall.SIGINT); err != nil && err != syscall.ESRCH {
			return err
		}
		go func() {
			timer := time.NewTimer(2 * time.Second)
			defer timer.Stop()
			select {
			case <-done:
				return
			case <-timer.C:
				_ = syscall.Kill(-pgid, syscall.SIGKILL)
			}
		}()
		return nil
	}
	cmd.WaitDelay = 5 * time.Second
	return markDone
}
