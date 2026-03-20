package config

import (
	"os"
	"path/filepath"

	"github.com/pelletier/go-toml/v2"
)

// Config holds the sarasa configuration.
type Config struct {
	Managers []string       `toml:"managers"`
	Skip     SkipConfig     `toml:"skip"`
	Schedule ScheduleConfig `toml:"schedule"`
	Logging  LoggingConfig  `toml:"logging"`
	Brew     BrewConfig     `toml:"brew"`
	NPM      NPMConfig      `toml:"npm"`
	Volta    VoltaConfig    `toml:"volta"`
}

// SkipConfig holds packages to skip per manager.
type SkipConfig struct {
	Brew  []string `toml:"brew"`
	NPM   []string `toml:"npm"`
	Volta []string `toml:"volta"`
	Pipx  []string `toml:"pipx"`
	Bun   []string `toml:"bun"`
}

// ScheduleConfig holds scheduling configuration.
type ScheduleConfig struct {
	Times []string `toml:"times"`
}

// LoggingConfig holds logging configuration.
type LoggingConfig struct {
	Dir           string `toml:"dir"`
	RetentionDays int    `toml:"retention_days"`
	Level         string `toml:"level"`
}

// BrewConfig holds Homebrew-specific configuration.
type BrewConfig struct {
	Greedy bool `toml:"greedy"`
}

// NPMConfig holds npm-specific configuration.
type NPMConfig struct {
	SkipMajor bool `toml:"skip_major"`
}

// VoltaConfig holds Volta-specific configuration.
type VoltaConfig struct {
	SkipMajor bool `toml:"skip_major"`
}

// DefaultConfig returns the default configuration.
func DefaultConfig() *Config {
	homeDir, _ := os.UserHomeDir()
	return &Config{
		Managers: []string{"brew", "volta", "pipx", "bun"},
		Skip: SkipConfig{
			Brew:  []string{},
			NPM:   []string{},
			Volta: []string{},
			Pipx:  []string{},
			Bun:   []string{},
		},
		Schedule: ScheduleConfig{
			Times: []string{
				"00:00", "02:00", "04:00", "06:00",
				"08:00", "10:00", "12:00", "14:00",
				"16:00", "18:00", "20:00", "22:00",
			},
		},
		Logging: LoggingConfig{
			Dir:           filepath.Join(homeDir, "Library", "Logs", "sarasa"),
			RetentionDays: 30,
			Level:         "info",
		},
		Brew: BrewConfig{
			Greedy: false,
		},
		NPM: NPMConfig{
			SkipMajor: false,
		},
		Volta: VoltaConfig{
			SkipMajor: false,
		},
	}
}

// ConfigPath returns the default config file path.
func ConfigPath() string {
	homeDir, _ := os.UserHomeDir()
	return filepath.Join(homeDir, ".config", "sarasa", "config.toml")
}

// Exists returns true if the config file exists at the default path.
func Exists() bool {
	_, err := os.Stat(ConfigPath())
	return err == nil
}

// Load loads the configuration from the default path or returns defaults.
func Load() (*Config, error) {
	return LoadFrom(ConfigPath())
}

// LoadFrom loads the configuration from a specific path.
func LoadFrom(path string) (*Config, error) {
	cfg := DefaultConfig()

	// Expand ~ in path
	if len(path) > 0 && path[0] == '~' {
		homeDir, _ := os.UserHomeDir()
		path = filepath.Join(homeDir, path[1:])
	}

	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			// Return defaults if config doesn't exist
			return cfg, nil
		}
		return nil, err
	}

	if err := toml.Unmarshal(data, cfg); err != nil {
		return nil, err
	}

	// Expand ~ in logging dir
	if len(cfg.Logging.Dir) > 0 && cfg.Logging.Dir[0] == '~' {
		homeDir, _ := os.UserHomeDir()
		cfg.Logging.Dir = filepath.Join(homeDir, cfg.Logging.Dir[1:])
	}

	return cfg, nil
}

// Save saves the configuration to the default path.
func Save(cfg *Config) error {
	return SaveTo(cfg, ConfigPath())
}

// SaveTo saves the configuration to a specific path.
func SaveTo(cfg *Config, path string) error {
	// Expand ~ in path
	if len(path) > 0 && path[0] == '~' {
		homeDir, _ := os.UserHomeDir()
		path = filepath.Join(homeDir, path[1:])
	}

	// Ensure directory exists
	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}

	data, err := toml.Marshal(cfg)
	if err != nil {
		return err
	}

	return os.WriteFile(path, data, 0644)
}

// IsManagerEnabled checks if a manager is enabled in the config.
func (c *Config) IsManagerEnabled(name string) bool {
	if len(c.Managers) == 0 {
		return true // All managers enabled if list is empty
	}
	for _, m := range c.Managers {
		if m == name {
			return true
		}
	}
	return false
}

// GetSkipList returns the skip list for a manager.
func (c *Config) GetSkipList(manager string) []string {
	switch manager {
	case "brew":
		return c.Skip.Brew
	case "npm":
		return c.Skip.NPM
	case "volta":
		return c.Skip.Volta
	case "pipx":
		return c.Skip.Pipx
	case "bun":
		return c.Skip.Bun
	default:
		return nil
	}
}

// ShouldSkip checks if a package should be skipped.
func (c *Config) ShouldSkip(manager, pkg string) bool {
	skipList := c.GetSkipList(manager)
	for _, s := range skipList {
		if s == pkg {
			return true
		}
	}
	return false
}
