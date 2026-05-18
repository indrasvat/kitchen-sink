package cmd

import (
	"fmt"
	"os/exec"

	"github.com/spf13/cobra"

	"github.com/indrasvat/sarasa/internal/scheduler"
)

var scheduleCmd = &cobra.Command{
	Use:   "schedule",
	Short: "Manage scheduled upgrades",
	Long: `Manage launchd-based scheduled upgrades.

Scheduled runs use a generated non-interactive launchd environment with a PATH
that includes user-local tool directories such as ~/.local/bin, ~/bin, and
~/go/bin, plus the directory containing the sarasa binary.

Examples:
  sarasa schedule install             # Install launchd agent
  sarasa schedule uninstall           # Remove launchd agent
  sarasa schedule status              # Show schedule status`,
}

var scheduleInstallCmd = &cobra.Command{
	Use:   "install",
	Short: "Install the launchd agent",
	RunE:  runScheduleInstall,
}

var scheduleUninstallCmd = &cobra.Command{
	Use:   "uninstall",
	Short: "Remove the launchd agent",
	RunE:  runScheduleUninstall,
}

var scheduleStatusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show schedule status",
	RunE:  runScheduleStatus,
}

func init() {
	rootCmd.AddCommand(scheduleCmd)
	scheduleCmd.AddCommand(scheduleInstallCmd)
	scheduleCmd.AddCommand(scheduleUninstallCmd)
	scheduleCmd.AddCommand(scheduleStatusCmd)
}

func runScheduleInstall(_ *cobra.Command, _ []string) error {
	cfg := GetConfig()

	// Parse schedule times from config
	times, err := scheduler.ParseTimes(cfg.Schedule.Times)
	if err != nil {
		return fmt.Errorf("invalid schedule times: %w", err)
	}

	// Find the sarasa binary
	binaryPath, err := exec.LookPath("sarasa")
	if err != nil {
		// If not in PATH, try to find it relative to current executable
		fmt.Println("Warning: 'sarasa' not found in PATH. Using default path.")
		binaryPath = "/usr/local/bin/sarasa"
	}

	launchdCfg := &scheduler.Config{
		Label:           scheduler.LaunchAgentLabel,
		BinaryPath:      binaryPath,
		LogDir:          cfg.Logging.Dir,
		Times:           times,
		EnvironmentPath: scheduler.DefaultEnvironmentPath(binaryPath),
	}

	if err := scheduler.Install(launchdCfg); err != nil {
		return err
	}

	fmt.Println("Launchd agent installed successfully!")
	fmt.Printf("Plist: %s\n", scheduler.PlistPath())
	fmt.Println("\nScheduled times:")
	for _, t := range times {
		fmt.Printf("  %02d:%02d\n", t.Hour, t.Minute)
	}

	return nil
}

func runScheduleUninstall(_ *cobra.Command, _ []string) error {
	if err := scheduler.Uninstall(); err != nil {
		return err
	}

	fmt.Println("Launchd agent uninstalled successfully!")
	return nil
}

func runScheduleStatus(_ *cobra.Command, _ []string) error {
	status, err := scheduler.GetStatus()
	if err != nil {
		return err
	}

	if !status.Installed {
		fmt.Println("Launchd agent is not installed")
		fmt.Println("\nRun 'sarasa schedule install' to install it.")
		return nil
	}

	fmt.Println("Launchd agent status:")
	fmt.Printf("  Installed: yes\n")
	fmt.Printf("  Plist: %s\n", scheduler.PlistPath())

	if status.Loaded {
		fmt.Printf("  Loaded: yes\n")
		if status.PID > 0 {
			fmt.Printf("  PID: %d (currently running)\n", status.PID)
		}
		fmt.Printf("  Last exit code: %d\n", status.LastExit)
	} else {
		fmt.Printf("  Loaded: no\n")
	}

	return nil
}
