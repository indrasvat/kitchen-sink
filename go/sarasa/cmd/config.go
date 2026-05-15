package cmd

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/spf13/cobra"

	"github.com/indrasvat/sarasa/internal/manager"
	"github.com/indrasvat/sarasa/internal/ui"
)

var configCmd = &cobra.Command{
	Use:    "config",
	Short:  "Configuration utilities",
	Hidden: true, // Internal; used by install.sh
}

// SuggestOutput is the JSON output for config suggest.
type SuggestOutput struct {
	ConfigPath string   `json:"config_path"`
	Configured []string `json:"configured"`
	Missing    []string `json:"missing"`
}

var suggestJSON bool

var suggestCmd = &cobra.Command{
	Use:   "suggest",
	Short: "Suggest managers available but not in config",
	Long: `Check for package managers that are available on this system
but not listed in the current config's managers list.

Used by install.sh to detect stale configs after upgrades.`,
	RunE: runSuggest,
}

func init() {
	rootCmd.AddCommand(configCmd)
	configCmd.AddCommand(suggestCmd)
	suggestCmd.Flags().BoolVar(&suggestJSON, "json", false, "output as JSON")
}

func runSuggest(_ *cobra.Command, _ []string) error {
	cfg := GetConfig()
	opts := &manager.Options{Config: cfg}

	// An empty managers list means "all managers enabled" — nothing to suggest.
	if len(cfg.Managers) == 0 {
		if suggestJSON {
			out := SuggestOutput{
				ConfigPath: configPath(),
				Configured: cfg.Managers,
			}
			data, err := json.MarshalIndent(out, "", "  ")
			if err != nil {
				return err
			}
			fmt.Println(string(data))
		}
		return nil
	}

	// Build set of currently configured managers
	configured := make(map[string]bool)
	for _, m := range cfg.Managers {
		configured[m] = true
	}

	// Check all registered managers for availability
	var missing []string
	for _, name := range manager.List() {
		if configured[name] {
			continue
		}
		m, err := manager.Get(name, opts)
		if err != nil {
			continue
		}
		if m.IsAvailable() {
			missing = append(missing, name)
		}
	}

	if suggestJSON {
		out := SuggestOutput{
			ConfigPath: configPath(),
			Configured: cfg.Managers,
			Missing:    missing,
		}
		data, err := json.MarshalIndent(out, "", "  ")
		if err != nil {
			return err
		}
		fmt.Println(string(data))
		return nil
	}

	if len(missing) == 0 {
		return nil
	}

	// Styled output for terminal
	if ui.IsTTY() {
		fmt.Printf("\n  %s New managers available but not in your config:\n", ui.IconSparkle)
		for _, name := range missing {
			fmt.Printf("    %s %s %s\n", ui.ManagerIcon(name), name, "(available)")
		}
		fmt.Printf("\n  Run %ssarasa init --force%s to add them.\n\n",
			"\033[1m\033[96m", "\033[0m")
	} else {
		fmt.Println(strings.Join(missing, "\n"))
	}

	return nil
}
