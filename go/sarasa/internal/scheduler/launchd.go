package scheduler

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"
	"text/template"

	"github.com/indrasvat/sarasa/internal/logger"
	"github.com/indrasvat/sarasa/internal/process"
)

const (
	// LaunchAgentLabel is the launchd label for the sarasa agent.
	LaunchAgentLabel = "com.sarasa.upgrade"

	// plistTemplate is the template for the launchd plist.
	plistTemplate = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>{{.Label}}</string>

    <key>ProgramArguments</key>
    <array>
        <string>{{.BinaryPath}}</string>
        <string>run</string>
    </array>

    <key>StartCalendarInterval</key>
    <array>
{{- range .Times}}
        <dict>
            <key>Hour</key>
            <integer>{{.Hour}}</integer>
            <key>Minute</key>
            <integer>{{.Minute}}</integer>
        </dict>
{{- end}}
    </array>

    <key>StandardOutPath</key>
    <string>{{.LogDir}}/launchd-stdout.log</string>

    <key>StandardErrorPath</key>
    <string>{{.LogDir}}/launchd-stderr.log</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>{{.EnvironmentPath}}</string>
    </dict>
</dict>
</plist>`
)

// ScheduleTime represents a scheduled time.
type ScheduleTime struct {
	Hour   int
	Minute int
}

// Config holds launchd configuration.
type Config struct {
	Label           string
	BinaryPath      string
	LogDir          string
	Times           []ScheduleTime
	EnvironmentPath string
}

// PlistPath returns the path to the launchd plist file.
func PlistPath() string {
	homeDir, _ := os.UserHomeDir()
	return filepath.Join(homeDir, "Library", "LaunchAgents", LaunchAgentLabel+".plist")
}

// ParseTime parses a time string in HH:MM format.
func ParseTime(s string) (ScheduleTime, error) {
	parts := strings.Split(s, ":")
	if len(parts) != 2 {
		return ScheduleTime{}, fmt.Errorf("invalid time format: %s (expected HH:MM)", s)
	}

	hour, err := strconv.Atoi(parts[0])
	if err != nil || hour < 0 || hour > 23 {
		return ScheduleTime{}, fmt.Errorf("invalid hour: %s", parts[0])
	}

	minute, err := strconv.Atoi(parts[1])
	if err != nil || minute < 0 || minute > 59 {
		return ScheduleTime{}, fmt.Errorf("invalid minute: %s", parts[1])
	}

	return ScheduleTime{Hour: hour, Minute: minute}, nil
}

// ParseTimes parses multiple time strings.
func ParseTimes(times []string) ([]ScheduleTime, error) {
	result := make([]ScheduleTime, 0, len(times))
	for _, t := range times {
		st, err := ParseTime(t)
		if err != nil {
			return nil, err
		}
		result = append(result, st)
	}
	return result, nil
}

// DefaultConfig returns the default launchd configuration.
func DefaultConfig() (*Config, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}

	// Find the sarasa binary
	binaryPath, err := exec.LookPath("sarasa")
	if err != nil {
		// Default to common install locations
		binaryPath = filepath.Join(homeDir, ".local", "bin", "sarasa")
	}

	return &Config{
		Label:           LaunchAgentLabel,
		BinaryPath:      binaryPath,
		LogDir:          filepath.Join(homeDir, "Library", "Logs", "sarasa"),
		EnvironmentPath: DefaultEnvironmentPath(binaryPath),
		Times: []ScheduleTime{
			{Hour: 0, Minute: 0},
			{Hour: 2, Minute: 0},
			{Hour: 4, Minute: 0},
			{Hour: 6, Minute: 0},
			{Hour: 8, Minute: 0},
			{Hour: 10, Minute: 0},
			{Hour: 12, Minute: 0},
			{Hour: 14, Minute: 0},
			{Hour: 16, Minute: 0},
			{Hour: 18, Minute: 0},
			{Hour: 20, Minute: 0},
			{Hour: 22, Minute: 0},
		},
	}, nil
}

// DefaultEnvironmentPath returns a launchd-safe PATH for scheduled sarasa runs.
//
// launchd jobs do not inherit the user's interactive shell PATH. Sarasa custom
// tools are commonly installed in user-local directories, so include those
// explicitly along with the directory containing the sarasa binary.
func DefaultEnvironmentPath(binaryPath string) string {
	return process.DefaultPath(binaryPath)
}

// GeneratePlist generates the launchd plist content.
func GeneratePlist(cfg *Config) ([]byte, error) {
	tmpl, err := template.New("plist").Parse(plistTemplate)
	if err != nil {
		return nil, fmt.Errorf("failed to parse plist template: %w", err)
	}

	renderCfg := *cfg
	if renderCfg.EnvironmentPath == "" {
		renderCfg.EnvironmentPath = DefaultEnvironmentPath(renderCfg.BinaryPath)
	}

	var buf bytes.Buffer
	if err := tmpl.Execute(&buf, &renderCfg); err != nil {
		return nil, fmt.Errorf("failed to execute plist template: %w", err)
	}

	return buf.Bytes(), nil
}

// Install installs the launchd agent.
func Install(cfg *Config) error {
	// Ensure log directory exists
	if err := os.MkdirAll(cfg.LogDir, 0755); err != nil {
		return fmt.Errorf("failed to create log directory: %w", err)
	}

	// Ensure LaunchAgents directory exists
	plistPath := PlistPath()
	if err := os.MkdirAll(filepath.Dir(plistPath), 0755); err != nil {
		return fmt.Errorf("failed to create LaunchAgents directory: %w", err)
	}

	// Generate plist
	plist, err := GeneratePlist(cfg)
	if err != nil {
		return err
	}

	// Unload existing agent if present (ignore "not loaded" errors)
	if err := Unload(); err != nil && !strings.Contains(err.Error(), "Could not find specified service") {
		logger.Get().Debug("Failed to unload existing agent", "error", err.Error())
	}

	// Write plist file
	if err := os.WriteFile(plistPath, plist, 0644); err != nil {
		return fmt.Errorf("failed to write plist file: %w", err)
	}

	// Load the agent
	return Load()
}

// Uninstall removes the launchd agent.
func Uninstall() error {
	// Unload first (ignore "not loaded" errors)
	if err := Unload(); err != nil && !strings.Contains(err.Error(), "Could not find specified service") {
		logger.Get().Debug("Failed to unload agent during uninstall", "error", err.Error())
	}

	// Remove plist file
	plistPath := PlistPath()
	if err := os.Remove(plistPath); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("failed to remove plist file: %w", err)
	}

	return nil
}

// Load loads the launchd agent.
func Load() error {
	cmd := exec.CommandContext(context.Background(), "launchctl", "load", PlistPath()) //nolint:noctx // no context needed
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to load launchd agent: %w", err)
	}
	return nil
}

// Unload unloads the launchd agent.
func Unload() error {
	cmd := exec.CommandContext(context.Background(), "launchctl", "unload", PlistPath()) //nolint:noctx // no context needed
	return cmd.Run()                                                                     // Ignore error if not loaded
}

// Status returns the status of the launchd agent.
type Status struct {
	Installed bool
	Loaded    bool
	PID       int
	LastExit  int
	Times     []ScheduleTime
}

// GetStatus returns the current status of the launchd agent.
func GetStatus() (*Status, error) {
	status := &Status{}

	// Check if plist exists
	plistPath := PlistPath()
	if _, err := os.Stat(plistPath); err != nil {
		if os.IsNotExist(err) {
			return status, nil
		}
		return nil, err
	}
	status.Installed = true

	// Check if loaded
	cmd := exec.CommandContext(context.Background(), "launchctl", "list", LaunchAgentLabel) //nolint:noctx // no context needed
	output, err := cmd.Output()
	if err == nil {
		status.Loaded = true

		// Parse output for PID and exit status
		lines := strings.Split(string(output), "\n")
		for _, line := range lines {
			fields := strings.Fields(line)
			if len(fields) >= 3 && fields[2] == LaunchAgentLabel {
				if fields[0] != "-" {
					status.PID, _ = strconv.Atoi(fields[0])
				}
				status.LastExit, _ = strconv.Atoi(fields[1])
				break
			}
		}
	}

	// Parse plist to get scheduled times
	// (simplified - would need proper plist parsing for full implementation)

	return status, nil
}

// CurrentUser returns the current username.
func CurrentUser() (string, error) {
	u, err := user.Current()
	if err != nil {
		return "", err
	}
	return u.Username, nil
}
