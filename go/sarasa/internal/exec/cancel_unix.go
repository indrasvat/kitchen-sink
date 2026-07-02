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
	var mu sync.Mutex
	var pgid int
	var canceled bool
	markDone := func() {
		mu.Lock()
		cancelWasSent := canceled
		cancelPGID := pgid
		mu.Unlock()
		if !cancelWasSent || !processGroupExists(cancelPGID) {
			doneOnce.Do(func() {
				close(done)
			})
		}
	}

	cmd.Cancel = func() error {
		if cmd.Process == nil {
			return os.ErrProcessDone
		}
		cancelPGID := cmd.Process.Pid
		mu.Lock()
		pgid = cancelPGID
		canceled = true
		mu.Unlock()
		if err := syscall.Kill(-cancelPGID, syscall.SIGINT); err != nil && err != syscall.ESRCH {
			return err
		}
		go func() {
			timer := time.NewTimer(2 * time.Second)
			defer timer.Stop()
			select {
			case <-done:
				return
			case <-timer.C:
				if processGroupExists(cancelPGID) {
					_ = syscall.Kill(-cancelPGID, syscall.SIGKILL)
				}
			}
		}()
		return nil
	}
	cmd.WaitDelay = 5 * time.Second
	return markDone
}

func processGroupExists(pgid int) bool {
	if pgid <= 0 {
		return false
	}
	err := syscall.Kill(-pgid, 0)
	return err == nil || err == syscall.EPERM
}
