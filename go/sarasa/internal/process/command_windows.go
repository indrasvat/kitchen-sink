//go:build windows

package process

import "os/exec"

func detachTTY(_ *exec.Cmd) {}
