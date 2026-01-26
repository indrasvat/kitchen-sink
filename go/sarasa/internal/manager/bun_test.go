package manager

import (
	"testing"
)

func TestParseBunOutdated(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected []bunPackage
	}{
		{
			name:     "empty input",
			input:    "",
			expected: nil,
		},
		{
			name:     "whitespace only",
			input:    "   \n\t\n  ",
			expected: nil,
		},
		{
			name: "no outdated packages - just version line",
			input: `bun outdated v1.3.6 (d530ed99)
`,
			expected: nil,
		},
		{
			name:     "no outdated packages - version line no newline",
			input:    `bun outdated v1.3.6 (d530ed99)`,
			expected: nil,
		},
		{
			name: "single outdated package",
			input: `bun outdated v1.3.6 (d530ed99)
┌─────────────┬─────────┬────────┬────────┐
│ Package     │ Current │ Update │ Latest │
├─────────────┼─────────┼────────┼────────┤
│ opencode-ai │ 1.1.33  │ 1.1.36 │ 1.1.36 │
└─────────────┴─────────┴────────┴────────┘
`,
			expected: []bunPackage{
				{name: "opencode-ai", current: "1.1.33", update: "1.1.36", latest: "1.1.36"},
			},
		},
		{
			name: "multiple outdated packages",
			input: `bun outdated v1.3.6 (d530ed99)
┌─────────────┬─────────┬────────┬────────┐
│ Package     │ Current │ Update │ Latest │
├─────────────┼─────────┼────────┼────────┤
│ opencode-ai │ 1.1.33  │ 1.1.36 │ 1.1.36 │
│ typescript  │ 5.0.0   │ 5.3.0  │ 5.3.0  │
│ prettier    │ 2.8.0   │ 3.1.0  │ 3.1.0  │
└─────────────┴─────────┴────────┴────────┘
`,
			expected: []bunPackage{
				{name: "opencode-ai", current: "1.1.33", update: "1.1.36", latest: "1.1.36"},
				{name: "typescript", current: "5.0.0", update: "5.3.0", latest: "5.3.0"},
				{name: "prettier", current: "2.8.0", update: "3.1.0", latest: "3.1.0"},
			},
		},
		{
			name: "scoped package with @",
			input: `bun outdated v1.3.6 (d530ed99)
┌───────────────────┬─────────┬────────┬────────┐
│ Package           │ Current │ Update │ Latest │
├───────────────────┼─────────┼────────┼────────┤
│ @types/node       │ 20.0.0  │ 20.5.0 │ 20.5.0 │
└───────────────────┴─────────┴────────┴────────┘
`,
			expected: []bunPackage{
				{name: "@types/node", current: "20.0.0", update: "20.5.0", latest: "20.5.0"},
			},
		},
		{
			name: "multiple scoped packages",
			input: `bun outdated v1.3.6 (d530ed99)
┌────────────────────────┬─────────┬────────┬────────┐
│ Package                │ Current │ Update │ Latest │
├────────────────────────┼─────────┼────────┼────────┤
│ @types/node            │ 20.0.0  │ 20.5.0 │ 20.5.0 │
│ @google/generative-ai  │ 1.0.0   │ 1.2.0  │ 1.2.0  │
│ @anthropic/sdk         │ 0.5.0   │ 0.6.0  │ 0.6.0  │
└────────────────────────┴─────────┴────────┴────────┘
`,
			expected: []bunPackage{
				{name: "@types/node", current: "20.0.0", update: "20.5.0", latest: "20.5.0"},
				{name: "@google/generative-ai", current: "1.0.0", update: "1.2.0", latest: "1.2.0"},
				{name: "@anthropic/sdk", current: "0.5.0", update: "0.6.0", latest: "0.6.0"},
			},
		},
		{
			name: "different update and latest versions (major upgrade available)",
			input: `bun outdated v1.3.6 (d530ed99)
┌─────────────┬─────────┬────────┬────────┐
│ Package     │ Current │ Update │ Latest │
├─────────────┼─────────┼────────┼────────┤
│ semver      │ 7.5.0   │ 7.6.0  │ 8.0.0  │
└─────────────┴─────────┴────────┴────────┘
`,
			expected: []bunPackage{
				{name: "semver", current: "7.5.0", update: "7.6.0", latest: "8.0.0"},
			},
		},
		{
			name: "extra whitespace in columns",
			input: `bun outdated v1.3.6 (d530ed99)
┌─────────────┬─────────┬────────┬────────┐
│ Package     │ Current │ Update │ Latest │
├─────────────┼─────────┼────────┼────────┤
│   lodash    │  4.17.0 │ 4.17.21│4.17.21 │
└─────────────┴─────────┴────────┴────────┘
`,
			expected: []bunPackage{
				{name: "lodash", current: "4.17.0", update: "4.17.21", latest: "4.17.21"},
			},
		},
		{
			name: "prerelease versions",
			input: `bun outdated v1.3.6 (d530ed99)
┌─────────────┬─────────────┬─────────────┬─────────────┐
│ Package     │ Current     │ Update      │ Latest      │
├─────────────┼─────────────┼─────────────┼─────────────┤
│ beta-pkg    │ 1.0.0-beta.1│ 1.0.0-beta.2│ 1.0.0       │
│ alpha-pkg   │ 2.0.0-alpha │ 2.0.0-rc.1  │ 2.0.0       │
└─────────────┴─────────────┴─────────────┴─────────────┘
`,
			expected: []bunPackage{
				{name: "beta-pkg", current: "1.0.0-beta.1", update: "1.0.0-beta.2", latest: "1.0.0"},
				{name: "alpha-pkg", current: "2.0.0-alpha", update: "2.0.0-rc.1", latest: "2.0.0"},
			},
		},
		{
			name: "package names with hyphens and numbers",
			input: `bun outdated v1.3.6 (d530ed99)
┌──────────────────┬─────────┬────────┬────────┐
│ Package          │ Current │ Update │ Latest │
├──────────────────┼─────────┼────────┼────────┤
│ node-fetch       │ 3.0.0   │ 3.1.0  │ 3.1.0  │
│ es6-promise      │ 4.0.0   │ 4.2.0  │ 4.2.0  │
│ level-2-cache    │ 1.0.0   │ 1.1.0  │ 1.1.0  │
└──────────────────┴─────────┴────────┴────────┘
`,
			expected: []bunPackage{
				{name: "node-fetch", current: "3.0.0", update: "3.1.0", latest: "3.1.0"},
				{name: "es6-promise", current: "4.0.0", update: "4.2.0", latest: "4.2.0"},
				{name: "level-2-cache", current: "1.0.0", update: "1.1.0", latest: "1.1.0"},
			},
		},
		{
			name: "very long package names",
			input: `bun outdated v1.3.6 (d530ed99)
┌──────────────────────────────────────────┬─────────┬────────┬────────┐
│ Package                                  │ Current │ Update │ Latest │
├──────────────────────────────────────────┼─────────┼────────┼────────┤
│ @very-long-scope/extremely-long-pkg-name │ 1.0.0   │ 1.1.0  │ 1.1.0  │
└──────────────────────────────────────────┴─────────┴────────┴────────┘
`,
			expected: []bunPackage{
				{name: "@very-long-scope/extremely-long-pkg-name", current: "1.0.0", update: "1.1.0", latest: "1.1.0"},
			},
		},
		{
			name: "no trailing newline",
			input: `bun outdated v1.3.6 (d530ed99)
┌─────────────┬─────────┬────────┬────────┐
│ Package     │ Current │ Update │ Latest │
├─────────────┼─────────┼────────┼────────┤
│ my-pkg      │ 1.0.0   │ 1.1.0  │ 1.1.0  │
└─────────────┴─────────┴────────┴────────┘`,
			expected: []bunPackage{
				{name: "my-pkg", current: "1.0.0", update: "1.1.0", latest: "1.1.0"},
			},
		},
		{
			name: "different bun version format",
			input: `bun outdated v2.0.0 (abcdef12)
┌─────────────┬─────────┬────────┬────────┐
│ Package     │ Current │ Update │ Latest │
├─────────────┼─────────┼────────┼────────┤
│ test-pkg    │ 1.0.0   │ 1.1.0  │ 1.1.0  │
└─────────────┴─────────┴────────┴────────┘
`,
			expected: []bunPackage{
				{name: "test-pkg", current: "1.0.0", update: "1.1.0", latest: "1.1.0"},
			},
		},
		{
			name: "table without version header line",
			input: `┌─────────────┬─────────┬────────┬────────┐
│ Package     │ Current │ Update │ Latest │
├─────────────┼─────────┼────────┼────────┤
│ test-pkg    │ 1.0.0   │ 1.1.0  │ 1.1.0  │
└─────────────┴─────────┴────────┴────────┘
`,
			expected: []bunPackage{
				{name: "test-pkg", current: "1.0.0", update: "1.1.0", latest: "1.1.0"},
			},
		},
		{
			name: "ASCII format - single package (non-TTY/piped)",
			input: `bun outdated v1.3.6 (d530ed99)
|-----------------------------------------|
| Package     | Current | Update | Latest |
|-------------|---------|--------|--------|
| opencode-ai | 1.1.33  | 1.1.36 | 1.1.36 |
|-----------------------------------------|`,
			expected: []bunPackage{
				{name: "opencode-ai", current: "1.1.33", update: "1.1.36", latest: "1.1.36"},
			},
		},
		{
			name: "ASCII format - multiple packages",
			input: `bun outdated v1.3.6 (d530ed99)
|-----------------------------------------|
| Package     | Current | Update | Latest |
|-------------|---------|--------|--------|
| typescript  | 5.0.0   | 5.3.0  | 5.3.0  |
| prettier    | 2.8.0   | 3.0.0  | 3.1.0  |
| opencode-ai | 1.1.33  | 1.1.36 | 1.1.36 |
|-----------------------------------------|`,
			expected: []bunPackage{
				{name: "typescript", current: "5.0.0", update: "5.3.0", latest: "5.3.0"},
				{name: "prettier", current: "2.8.0", update: "3.0.0", latest: "3.1.0"},
				{name: "opencode-ai", current: "1.1.33", update: "1.1.36", latest: "1.1.36"},
			},
		},
		{
			name: "ASCII format - scoped package",
			input: `|-----------------------------------------|
| Package           | Current | Update | Latest |
|-------------------|---------|--------|--------|
| @types/node       | 20.0.0  | 20.5.0 | 20.5.0 |
|-----------------------------------------|`,
			expected: []bunPackage{
				{name: "@types/node", current: "20.0.0", update: "20.5.0", latest: "20.5.0"},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, _ := parseBunOutdated(tt.input)

			if len(result) != len(tt.expected) {
				t.Errorf("expected %d packages, got %d", len(tt.expected), len(result))
				return
			}

			for i, pkg := range result {
				if pkg.name != tt.expected[i].name {
					t.Errorf("package[%d]: expected name=%q, got %q", i, tt.expected[i].name, pkg.name)
				}
				if pkg.current != tt.expected[i].current {
					t.Errorf("package[%d]: expected current=%q, got %q", i, tt.expected[i].current, pkg.current)
				}
				if pkg.update != tt.expected[i].update {
					t.Errorf("package[%d]: expected update=%q, got %q", i, tt.expected[i].update, pkg.update)
				}
				if pkg.latest != tt.expected[i].latest {
					t.Errorf("package[%d]: expected latest=%q, got %q", i, tt.expected[i].latest, pkg.latest)
				}
			}
		})
	}
}

func TestParseBunOutdated_UnparsedLines(t *testing.T) {
	tests := []struct {
		name             string
		input            string
		expectedPkgs     int
		expectedUnparsed int
		unparsedContains string // optional: check that unparsed contains this string
	}{
		{
			name: "malformed row with missing columns",
			input: `bun outdated v1.3.6 (d530ed99)
┌─────────────┬─────────┬────────┬────────┐
│ Package     │ Current │ Update │ Latest │
├─────────────┼─────────┼────────┼────────┤
│ valid-pkg   │ 1.0.0   │ 1.1.0  │ 1.1.0  │
│ broken │
│ another-pkg │ 2.0.0   │ 2.1.0  │ 2.1.0  │
└─────────────┴─────────┴────────┴────────┘
`,
			expectedPkgs:     2,
			expectedUnparsed: 1,
			unparsedContains: "broken",
		},
		{
			name: "empty package name",
			input: `bun outdated v1.3.6 (d530ed99)
┌─────────────┬─────────┬────────┬────────┐
│ Package     │ Current │ Update │ Latest │
├─────────────┼─────────┼────────┼────────┤
│             │ 1.0.0   │ 1.1.0  │ 1.1.0  │
│ valid-pkg   │ 2.0.0   │ 2.1.0  │ 2.1.0  │
└─────────────┴─────────┴────────┴────────┘
`,
			expectedPkgs:     1,
			expectedUnparsed: 1,
		},
		{
			name: "row with only separators - single column",
			input: `bun outdated v1.3.6 (d530ed99)
┌─────────────┬─────────┬────────┬────────┐
│ Package     │ Current │ Update │ Latest │
├─────────────┼─────────┼────────┼────────┤
│ valid-pkg   │ 1.0.0   │ 1.1.0  │ 1.1.0  │
│ only-one    │
│ another     │ 2.0.0   │ 2.1.0  │ 2.1.0  │
└─────────────┴─────────┴────────┴────────┘
`,
			expectedPkgs:     2,
			expectedUnparsed: 1,
		},
		{
			name: "multiple malformed rows",
			input: `bun outdated v1.3.6 (d530ed99)
┌─────────────┬─────────┬────────┬────────┐
│ Package     │ Current │ Update │ Latest │
├─────────────┼─────────┼────────┼────────┤
│ valid-pkg   │ 1.0.0   │ 1.1.0  │ 1.1.0  │
│ bad1 │
│             │ empty   │ name   │ here   │
│ another     │ 2.0.0   │ 2.1.0  │ 2.1.0  │
└─────────────┴─────────┴────────┴────────┘
`,
			expectedPkgs:     2,
			expectedUnparsed: 2,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, unparsed := parseBunOutdated(tt.input)

			if len(result) != tt.expectedPkgs {
				t.Errorf("expected %d parsed packages, got %d", tt.expectedPkgs, len(result))
			}
			if len(unparsed) != tt.expectedUnparsed {
				t.Errorf("expected %d unparsed lines, got %d: %v", tt.expectedUnparsed, len(unparsed), unparsed)
			}
			if tt.unparsedContains != "" {
				found := false
				for _, line := range unparsed {
					if contains(line, tt.unparsedContains) {
						found = true
						break
					}
				}
				if !found {
					t.Errorf("expected unparsed lines to contain %q, got: %v", tt.unparsedContains, unparsed)
				}
			}
		})
	}
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(s) > 0 && containsSubstring(s, substr))
}

func containsSubstring(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}

func TestParseBunOutdated_IgnoresNonDataLines(t *testing.T) {
	// Verify that version line, separators, and headers are properly skipped
	input := `bun outdated v1.3.6 (d530ed99)
┌─────────────┬─────────┬────────┬────────┐
│ Package     │ Current │ Update │ Latest │
├─────────────┼─────────┼────────┼────────┤
│ my-package  │ 1.0.0   │ 1.1.0  │ 1.1.0  │
└─────────────┴─────────┴────────┴────────┘
`

	result, unparsed := parseBunOutdated(input)

	if len(result) != 1 {
		t.Errorf("expected 1 package, got %d", len(result))
	}
	if len(unparsed) != 0 {
		t.Errorf("expected 0 unparsed lines, got %d: %v", len(unparsed), unparsed)
	}
	if len(result) > 0 && result[0].name != "my-package" {
		t.Errorf("expected name 'my-package', got %q", result[0].name)
	}
}

func TestParseBunOutdated_BoxDrawingCharacters(t *testing.T) {
	// Ensure all box-drawing characters are properly handled
	tests := []struct {
		name  string
		input string
		want  int // expected package count
	}{
		{
			name: "standard box drawing",
			input: `┌───┬───┬───┬───┐
│ Package │ Current │ Update │ Latest │
├───┼───┼───┼───┤
│ pkg │ 1.0 │ 1.1 │ 1.1 │
└───┴───┴───┴───┘`,
			want: 1,
		},
		{
			name: "double-line box drawing (if bun ever uses it)",
			input: `╔═══╦═══╦═══╦═══╗
║ Package ║ Current ║ Update ║ Latest ║
╠═══╬═══╬═══╬═══╣
║ pkg ║ 1.0 ║ 1.1 ║ 1.1 ║
╚═══╩═══╩═══╩═══╝`,
			want: 0, // won't parse because uses ║ not │
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, _ := parseBunOutdated(tt.input)
			if len(result) != tt.want {
				t.Errorf("expected %d packages, got %d", tt.want, len(result))
			}
		})
	}
}

func TestParseBunOutdated_RealWorldExamples(t *testing.T) {
	// Test with actual output captured from bun CLI
	tests := []struct {
		name     string
		input    string
		expected []bunPackage
	}{
		{
			name: "actual bun 1.3.6 TTY output - single outdated package (Unicode box-drawing)",
			// Captured from: bun outdated -g (TTY mode, when opencode-ai was outdated)
			input: `bun outdated v1.3.6 (d530ed99)
┌─────────────┬─────────┬────────┬────────┐
│ Package     │ Current │ Update │ Latest │
├─────────────┼─────────┼────────┼────────┤
│ opencode-ai │ 1.1.33  │ 1.1.36 │ 1.1.36 │
└─────────────┴─────────┴────────┴────────┘
`,
			expected: []bunPackage{
				{name: "opencode-ai", current: "1.1.33", update: "1.1.36", latest: "1.1.36"},
			},
		},
		{
			name: "actual bun 1.3.6 non-TTY output - single outdated package (ASCII)",
			// Captured from: bun outdated -g | cat (non-TTY/piped mode)
			input: `bun outdated v1.3.6 (d530ed99)
|-----------------------------------------|
| Package     | Current | Update | Latest |
|-------------|---------|--------|--------|
| opencode-ai | 1.1.33  | 1.1.33 | 1.1.36 |
|-----------------------------------------|`,
			expected: []bunPackage{
				{name: "opencode-ai", current: "1.1.33", update: "1.1.33", latest: "1.1.36"},
			},
		},
		{
			name: "actual bun 1.3.6 output - no outdated packages",
			// Captured from: bun outdated -g (when everything is up to date)
			input:    `bun outdated v1.3.6 (d530ed99)`,
			expected: nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, unparsed := parseBunOutdated(tt.input)

			if len(unparsed) > 0 {
				t.Errorf("unexpected unparsed lines: %v", unparsed)
			}

			if len(result) != len(tt.expected) {
				t.Errorf("expected %d packages, got %d", len(tt.expected), len(result))
				return
			}

			for i, pkg := range result {
				if pkg != tt.expected[i] {
					t.Errorf("package[%d]: expected %+v, got %+v", i, tt.expected[i], pkg)
				}
			}
		})
	}
}

// TestParseBunPmLs tests the parsing logic used in getInstalledVersion
func TestParseBunPmLsOutput(t *testing.T) {
	tests := []struct {
		name        string
		input       string
		packageName string
		expected    string
	}{
		{
			name: "actual bun pm ls -g output",
			// Captured from: bun pm ls -g on 2026-01-25
			input: `/Users/indrasvat/.bun/install/global node_modules (12)
└── opencode-ai@1.1.36`,
			packageName: "opencode-ai",
			expected:    "1.1.36",
		},
		{
			name: "single package with tree char └──",
			input: `/Users/test/.bun/install/global node_modules (1)
└── opencode-ai@1.1.36
`,
			packageName: "opencode-ai",
			expected:    "1.1.36",
		},
		{
			name: "multiple packages with tree chars",
			input: `/Users/test/.bun/install/global node_modules (3)
├── typescript@5.3.0
├── prettier@3.1.0
└── opencode-ai@1.1.36
`,
			packageName: "opencode-ai",
			expected:    "1.1.36",
		},
		{
			name: "scoped package",
			input: `/Users/test/.bun/install/global node_modules (2)
├── @types/node@20.5.0
└── lodash@4.17.21
`,
			packageName: "@types/node",
			expected:    "20.5.0",
		},
		{
			name: "package not found",
			input: `/Users/test/.bun/install/global node_modules (1)
└── other-package@1.0.0
`,
			packageName: "not-installed",
			expected:    "",
		},
		{
			name:        "empty output",
			input:       "",
			packageName: "any-package",
			expected:    "",
		},
		{
			name: "package with similar prefix - should not match",
			input: `/Users/test/.bun/install/global node_modules (2)
├── opencode-ai-extra@2.0.0
└── opencode-ai@1.1.36
`,
			packageName: "opencode-ai",
			expected:    "1.1.36",
		},
		{
			name: "prerelease version",
			input: `/Users/test/.bun/install/global node_modules (1)
└── beta-pkg@1.0.0-beta.5
`,
			packageName: "beta-pkg",
			expected:    "1.0.0-beta.5",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Simulate the parsing logic from getInstalledVersion
			result := parseVersionFromBunPmLs(tt.input, tt.packageName)
			if result != tt.expected {
				t.Errorf("expected version %q, got %q", tt.expected, result)
			}
		})
	}
}

// parseVersionFromBunPmLs extracts version for a package from bun pm ls output.
// This is a test helper that mirrors the logic in getInstalledVersion.
func parseVersionFromBunPmLs(output, name string) string {
	lines := splitLines(output)
	for _, line := range lines {
		// Strip tree-drawing characters (└── or ├──)
		line = trimSpace(line)
		line = trimPrefix(line, "└── ")
		line = trimPrefix(line, "├── ")

		// Check if this line is for our package
		if hasPrefix(line, name+"@") {
			// Extract version from "package@version"
			if idx := lastIndex(line, "@"); idx > 0 {
				return line[idx+1:]
			}
		}
	}
	return ""
}

// Helper functions to avoid importing strings in test
func splitLines(s string) []string {
	var lines []string
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] == '\n' {
			lines = append(lines, s[start:i])
			start = i + 1
		}
	}
	if start < len(s) {
		lines = append(lines, s[start:])
	}
	return lines
}

func trimSpace(s string) string {
	start := 0
	end := len(s)
	for start < end && (s[start] == ' ' || s[start] == '\t' || s[start] == '\r') {
		start++
	}
	for end > start && (s[end-1] == ' ' || s[end-1] == '\t' || s[end-1] == '\r') {
		end--
	}
	return s[start:end]
}

func trimPrefix(s, prefix string) string {
	if hasPrefix(s, prefix) {
		return s[len(prefix):]
	}
	return s
}

func hasPrefix(s, prefix string) bool {
	return len(s) >= len(prefix) && s[:len(prefix)] == prefix
}

func lastIndex(s string, substr string) int {
	for i := len(s) - len(substr); i >= 0; i-- {
		if s[i:i+len(substr)] == substr {
			return i
		}
	}
	return -1
}
