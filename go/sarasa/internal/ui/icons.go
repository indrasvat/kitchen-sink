package ui

// Status icons
const (
	IconCheck    = "✓"
	IconCross    = "✗"
	IconArrow    = "→"
	IconDot      = "●"
	IconWarning  = "⚠"
	IconSparkle  = "✨"
	IconDiamond  = "◆"
	IconTriangle = "▸"
	IconFailed   = "💥"
)

// Manager icons/emojis
const (
	IconBrew    = "🍺"
	IconNPM     = "📦"
	IconVolta   = "⚡"
	IconPipx    = "🐍"
	IconBun     = "🥟"
	IconSkills  = "🧩"
	IconCustom  = "🛠"
	IconPackage = "📦"
)

// ManagerIcon returns the icon for a given manager name.
func ManagerIcon(name string) string {
	switch name {
	case "brew":
		return IconBrew
	case "npm":
		return IconNPM
	case "volta":
		return IconVolta
	case "pipx":
		return IconPipx
	case "bun":
		return IconBun
	case "skills":
		return IconSkills
	case "custom":
		return IconCustom
	default:
		return IconPackage
	}
}

// PlainManagerIcon returns a plain text indicator for non-TTY output.
func PlainManagerIcon(name string) string {
	return "[" + name + "]"
}
