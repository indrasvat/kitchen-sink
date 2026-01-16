package manager

import (
	"context"
)

// Package represents a package that can be upgraded.
type Package struct {
	Name    string `json:"name"`
	Current string `json:"current"`
	Latest  string `json:"latest"`
	IsMajor bool   `json:"is_major,omitempty"`
}

// UpgradeResult holds the results of an upgrade operation.
type UpgradeResult struct {
	Upgraded []Package `json:"upgraded"`
	Failed   []Package `json:"failed"`
	Skipped  []Package `json:"skipped"`
}

// Manager defines the interface for package managers.
type Manager interface {
	// Name returns the name of the package manager.
	Name() string

	// IsAvailable checks if the package manager is installed.
	IsAvailable() bool

	// CheckOutdated returns a list of outdated packages.
	CheckOutdated(ctx context.Context) ([]Package, error)

	// Upgrade upgrades all outdated packages.
	// If dryRun is true, it only reports what would be upgraded.
	Upgrade(ctx context.Context, dryRun bool) (*UpgradeResult, error)

	// Cleanup runs cleanup operations (if supported).
	Cleanup(ctx context.Context) error
}

// Options holds options passed to managers.
type Options struct {
	DryRun      bool
	SkipMajor   bool
	SkipCleanup bool
	SkipList    []string
	Greedy      bool // For brew casks with auto_updates
}

// ShouldSkip checks if a package should be skipped.
func (o *Options) ShouldSkip(pkg string) bool {
	for _, s := range o.SkipList {
		if s == pkg {
			return true
		}
	}
	return false
}
