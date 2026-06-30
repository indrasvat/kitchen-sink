package process

import (
	"io"
	"os/exec"
)

// Configure prepares a child command for Sarasa's non-interactive execution
// model.
func Configure(cmd *exec.Cmd, extraEnv map[string]string) {
	cmd.Env = Environment(extraEnv)
	cmd.Stdin = io.NopCloser(&emptyReader{})
	detachTTY(cmd)
}

type emptyReader struct{}

func (r *emptyReader) Read(_ []byte) (int, error) {
	return 0, io.EOF
}
