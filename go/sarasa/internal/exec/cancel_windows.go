//go:build windows

package exec

import "os/exec"

func configureCancel(_ *exec.Cmd) func() {
	return func() {}
}
