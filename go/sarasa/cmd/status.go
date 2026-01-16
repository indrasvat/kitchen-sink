package cmd

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/spf13/cobra"

	"github.com/indrasvat/sarasa/internal/manager"
)

var (
	statusManagers string
	statusJSON     bool
)

var statusCmd = &cobra.Command{
	Use:   "status",
	Short: "Check for outdated packages",
	Long: `Check for outdated packages without upgrading them.

Examples:
  sarasa status                       # Check all managers
  sarasa status --managers=brew       # Check specific manager
  sarasa status --json                # Output as JSON`,
	RunE: runStatus,
}

func init() {
	rootCmd.AddCommand(statusCmd)

	statusCmd.Flags().StringVar(&statusManagers, "managers", "", "comma-separated list of managers to check")
	statusCmd.Flags().BoolVar(&statusJSON, "json", false, "output as JSON")
}

// StatusOutput represents the JSON output for status.
type StatusOutput struct {
	Managers []ManagerStatus `json:"managers"`
}

// ManagerStatus represents the status of a single manager.
type ManagerStatus struct {
	Name      string            `json:"name"`
	Available bool              `json:"available"`
	Outdated  []manager.Package `json:"outdated,omitempty"`
	Error     string            `json:"error,omitempty"`
}

func runStatus(_ *cobra.Command, _ []string) error {
	ctx := context.Background()
	cfg := GetConfig()

	opts := &manager.Options{
		Greedy: cfg.Brew.Greedy,
	}

	// Determine which managers to check
	var managerNames []string
	switch {
	case statusManagers != "":
		managerNames = strings.Split(statusManagers, ",")
	case len(cfg.Managers) > 0:
		managerNames = cfg.Managers
	default:
		managerNames = manager.List()
	}

	output := StatusOutput{
		Managers: make([]ManagerStatus, 0, len(managerNames)),
	}

	for _, name := range managerNames {
		m, err := manager.Get(name, opts)
		if err != nil {
			output.Managers = append(output.Managers, ManagerStatus{
				Name:  name,
				Error: err.Error(),
			})
			continue
		}

		status := ManagerStatus{
			Name:      name,
			Available: m.IsAvailable(),
		}

		if !m.IsAvailable() {
			output.Managers = append(output.Managers, status)
			continue
		}

		// Check outdated packages
		outdated, err := m.CheckOutdated(ctx)
		if err != nil {
			status.Error = err.Error()
		} else {
			status.Outdated = outdated
		}

		output.Managers = append(output.Managers, status)
	}

	if statusJSON {
		data, err := json.MarshalIndent(output, "", "  ")
		if err != nil {
			return err
		}
		fmt.Println(string(data))
		return nil
	}

	// Human-readable output
	for _, ms := range output.Managers {
		fmt.Printf("\n=== %s ===\n", ms.Name)

		if !ms.Available {
			fmt.Println("Not installed")
			continue
		}

		if ms.Error != "" {
			fmt.Printf("Error: %s\n", ms.Error)
			continue
		}

		if len(ms.Outdated) == 0 {
			fmt.Println("All packages up to date")
			continue
		}

		fmt.Printf("Outdated packages (%d):\n", len(ms.Outdated))
		for _, pkg := range ms.Outdated {
			majorTag := ""
			if pkg.IsMajor {
				majorTag = " [MAJOR]"
			}
			fmt.Printf("  %s: %s -> %s%s\n", pkg.Name, pkg.Current, pkg.Latest, majorTag)
		}
	}

	return nil
}
