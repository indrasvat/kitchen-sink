package cmd

import (
	"fmt"
	"runtime"

	"github.com/spf13/cobra"
)

// Version information set at build time.
var (
	Version   = "dev"
	Commit    = "none"
	BuildDate = "unknown"
)

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Print version information",
	Run: func(_ *cobra.Command, _ []string) {
		fmt.Printf("sarasa %s\n", Version)
		fmt.Printf("  commit: %s\n", Commit)
		fmt.Printf("  built: %s\n", BuildDate)
		fmt.Printf("  go: %s\n", runtime.Version())
		fmt.Printf("  os/arch: %s/%s\n", runtime.GOOS, runtime.GOARCH)
	},
}

func init() {
	rootCmd.AddCommand(versionCmd)
}
