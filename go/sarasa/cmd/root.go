package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/indrasvat/sarasa/internal/config"
	"github.com/indrasvat/sarasa/internal/logger"
)

var (
	cfgFile string
	verbose bool
	cfg     *config.Config
)

// rootCmd represents the base command when called without any subcommands.
var rootCmd = &cobra.Command{
	Use:   "sarasa",
	Short: "Automated global package manager upgrades",
	Long: `Sarasa automates global package upgrades for brew, npm, bun, and pipx
with scheduled background execution via launchd.

All operations target globally-installed packages only.`,
	PersistentPreRunE: func(_ *cobra.Command, _ []string) error {
		// Load config
		var err error
		if cfgFile != "" {
			cfg, err = config.LoadFrom(cfgFile)
		} else {
			cfg, err = config.Load()
		}
		if err != nil {
			return fmt.Errorf("failed to load config: %w", err)
		}

		// Initialize logger
		level := logger.ParseLevel(cfg.Logging.Level)
		if verbose {
			level = logger.ParseLevel("debug")
		}

		logCfg := logger.Config{
			Dir:           cfg.Logging.Dir,
			Level:         level,
			RetentionDays: cfg.Logging.RetentionDays,
		}

		if err := logger.Init(logCfg); err != nil {
			return fmt.Errorf("failed to initialize logger: %w", err)
		}

		return nil
	},
	PersistentPostRun: func(_ *cobra.Command, _ []string) {
		_ = logger.Close()
	},
}

// Execute adds all child commands to the root command and sets flags appropriately.
func Execute() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}

func init() {
	rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "", "config file (default is ~/.config/sarasa/config.toml)")
	rootCmd.PersistentFlags().BoolVarP(&verbose, "verbose", "v", false, "enable verbose output")
}

// GetConfig returns the loaded configuration.
func GetConfig() *config.Config {
	return cfg
}
