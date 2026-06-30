package process

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// DefaultPath returns a launchd-safe PATH for Sarasa child processes.
//
// Scheduled jobs do not inherit the user's interactive shell PATH. Custom
// recipes often install tools into user-local directories, so every child
// process gets those paths even when an older launchd plist is still loaded.
func DefaultPath(binaryPath string) string {
	homeDir, _ := os.UserHomeDir()
	candidates := []string{}
	if dir := filepath.Dir(binaryPath); binaryPath != "" && dir != "." {
		candidates = append(candidates, dir)
	}
	if homeDir != "" {
		candidates = append(candidates,
			filepath.Join(homeDir, ".local", "bin"),
			filepath.Join(homeDir, "bin"),
			filepath.Join(homeDir, "go", "bin"),
		)
	}
	candidates = append(candidates, filepath.SplitList(os.Getenv("PATH"))...)
	candidates = append(candidates,
		"/opt/homebrew/bin",
		"/opt/homebrew/sbin",
		"/usr/local/bin",
		"/usr/bin",
		"/bin",
		"/usr/sbin",
		"/sbin",
	)

	seen := make(map[string]bool, len(candidates))
	path := make([]string, 0, len(candidates))
	for _, candidate := range candidates {
		candidate = strings.TrimSpace(candidate)
		if candidate == "" || !filepath.IsAbs(candidate) || seen[candidate] {
			continue
		}
		seen[candidate] = true
		path = append(path, candidate)
	}
	return strings.Join(path, string(os.PathListSeparator))
}

// Environment returns a normalized child-process environment.
func Environment(extra map[string]string) []string {
	env := make(map[string]string)
	for _, item := range os.Environ() {
		key, value, ok := strings.Cut(item, "=")
		if !ok {
			continue
		}
		env[key] = value
	}
	env["PATH"] = DefaultPath("")
	env["HOMEBREW_NO_ASK"] = "1"
	env["HOMEBREW_NO_ENV_HINTS"] = "1"
	env["NONINTERACTIVE"] = "1"
	env["SUDO_ASKPASS"] = "/usr/bin/false"
	env["SSH_ASKPASS"] = "/usr/bin/false"
	for key, value := range extra {
		env[key] = value
	}

	out := make([]string, 0, len(env))
	for key, value := range env {
		out = append(out, key+"="+value)
	}
	return out
}

// LookPath searches for a binary using Sarasa's normalized PATH.
func LookPath(file string) (string, error) {
	if path, err := exec.LookPath(file); err == nil {
		return path, nil
	}
	if strings.ContainsRune(file, filepath.Separator) {
		return exec.LookPath(file)
	}

	for _, dir := range filepath.SplitList(DefaultPath("")) {
		path := filepath.Join(dir, file)
		if info, err := os.Stat(path); err == nil && !info.IsDir() && info.Mode()&0111 != 0 {
			return path, nil
		}
	}
	return exec.LookPath(file)
}
