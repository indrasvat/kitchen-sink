package process

import "os/exec"

// Configure prepares a child command for Sarasa's non-interactive execution
// model.
func Configure(cmd *exec.Cmd, extraEnv map[string]string) {
	cmd.Env = Environment(extraEnv)
	// A nil Stdin makes os/exec connect the child to the null device.
	detachTTY(cmd)
}
