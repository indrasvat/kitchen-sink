package ui

import (
	"github.com/charmbracelet/lipgloss"
)

// Color palette - adaptive for light/dark terminals
var (
	// Base colors
	ColorPrimary   = lipgloss.AdaptiveColor{Light: "#0066CC", Dark: "#00BFFF"}
	ColorSecondary = lipgloss.AdaptiveColor{Light: "#666666", Dark: "#888888"}
	ColorSuccess   = lipgloss.AdaptiveColor{Light: "#228B22", Dark: "#32CD32"}
	ColorWarning   = lipgloss.AdaptiveColor{Light: "#CC8800", Dark: "#FFD700"}
	ColorError     = lipgloss.AdaptiveColor{Light: "#CC0000", Dark: "#FF6B6B"}
	ColorMuted     = lipgloss.AdaptiveColor{Light: "#999999", Dark: "#666666"}

	// Manager-specific accent colors
	ColorBrew   = lipgloss.AdaptiveColor{Light: "#B5651D", Dark: "#FFA500"} // Orange
	ColorNPM    = lipgloss.AdaptiveColor{Light: "#CC0000", Dark: "#CB3837"} // Red
	ColorVolta  = lipgloss.AdaptiveColor{Light: "#7B68EE", Dark: "#9370DB"} // Purple
	ColorPipx   = lipgloss.AdaptiveColor{Light: "#3776AB", Dark: "#4B8BBE"} // Blue
	ColorBun    = lipgloss.AdaptiveColor{Light: "#D2B48C", Dark: "#FBDF9D"} // Tan
	ColorSkills = lipgloss.AdaptiveColor{Light: "#008080", Dark: "#00CED1"} // Teal
	ColorCustom = lipgloss.AdaptiveColor{Light: "#52616B", Dark: "#A7BBC7"} // Steel
)

// ManagerColor returns the accent color for a given manager name.
func ManagerColor(name string) lipgloss.AdaptiveColor {
	switch name {
	case "brew":
		return ColorBrew
	case "npm":
		return ColorNPM
	case "volta":
		return ColorVolta
	case "pipx":
		return ColorPipx
	case "bun":
		return ColorBun
	case "skills":
		return ColorSkills
	case managerCustom:
		return ColorCustom
	default:
		return ColorPrimary
	}
}

// Styles for various UI components
var (
	// Container styles
	StyleContainer = lipgloss.NewStyle().
			Padding(1, 2)

	// Header styles
	StyleHeader = lipgloss.NewStyle().
			Bold(true).
			Foreground(ColorPrimary)

	StyleHeaderDryRun = lipgloss.NewStyle().
				Bold(true).
				Foreground(lipgloss.AdaptiveColor{Light: "#8B008B", Dark: "#DA70D6"})

	// Manager panel with rounded border
	StyleManagerPanel = lipgloss.NewStyle().
				Border(lipgloss.RoundedBorder()).
				BorderForeground(ColorMuted).
				Padding(0, 1).
				MarginBottom(1)

	// Manager title inside panel
	StyleManagerTitle = lipgloss.NewStyle().
				Bold(true)

	// Package row styles
	StylePackageName = lipgloss.NewStyle().
				Bold(true)

	StyleVersionCurrent = lipgloss.NewStyle().
				Foreground(ColorMuted)

	StyleVersionLatest = lipgloss.NewStyle().
				Foreground(ColorSuccess)

	StyleVersionMajor = lipgloss.NewStyle().
				Bold(true).
				Foreground(ColorWarning)

	StyleMethodTag = lipgloss.NewStyle().
			Foreground(ColorMuted)

	StyleArrow = lipgloss.NewStyle().
			Foreground(ColorMuted)

	// Status indicators
	StyleSuccess = lipgloss.NewStyle().
			Foreground(ColorSuccess)

	StyleError = lipgloss.NewStyle().
			Foreground(ColorError)

	StyleWarning = lipgloss.NewStyle().
			Foreground(ColorWarning)

	StyleMuted = lipgloss.NewStyle().
			Foreground(ColorMuted)

	// Summary footer
	StyleSummary = lipgloss.NewStyle().
			MarginTop(1)

	StyleSummaryIcon = lipgloss.NewStyle().
				Foreground(ColorPrimary)

	// Help text at bottom
	StyleHelp = lipgloss.NewStyle().
			Foreground(ColorMuted).
			MarginTop(1)

	// Spinner style
	StyleSpinner = lipgloss.NewStyle().
			Foreground(ColorPrimary)

	// Progress bar styles
	StyleProgressBar = lipgloss.NewStyle().
				Foreground(ColorPrimary)

	StyleProgressBarFilled = lipgloss.NewStyle().
				Foreground(ColorSuccess)

	// Duration/timing
	StyleDuration = lipgloss.NewStyle().
			Foreground(ColorMuted)
)

// GetManagerPanelStyle returns a styled panel for the given manager.
func GetManagerPanelStyle(name string) lipgloss.Style {
	return StyleManagerPanel.BorderForeground(ManagerColor(name))
}

// GetManagerTitleStyle returns a styled title for the given manager.
func GetManagerTitleStyle(name string) lipgloss.Style {
	return StyleManagerTitle.Foreground(ManagerColor(name))
}
