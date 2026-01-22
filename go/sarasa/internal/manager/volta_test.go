package manager

import (
	"testing"
)

func TestParseVoltaList(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		expected []voltaPackage
	}{
		{
			name:     "empty input",
			input:    "",
			expected: nil,
		},
		{
			name: "only runtime and package-manager",
			input: `runtime node@24.13.0 (default)
package-manager npm@11.8.0 (default)`,
			expected: nil,
		},
		{
			name: "single package",
			input: `runtime node@24.13.0 (default)
package-manager npm@11.8.0 (default)
package wrangler@4.59.1 / wrangler, wrangler2 / node@24.13.0 npm@built-in (default)`,
			expected: []voltaPackage{
				{name: "wrangler", version: "4.59.1"},
			},
		},
		{
			name: "scoped package",
			input: `runtime node@24.13.0 (default)
package @google/gemini-cli@0.25.0 / gemini / node@24.13.0 npm@built-in (default)`,
			expected: []voltaPackage{
				{name: "@google/gemini-cli", version: "0.25.0"},
			},
		},
		{
			name: "multiple packages",
			input: `runtime node@24.13.0 (default)
package-manager npm@11.8.0 (default)
package @google/gemini-cli@0.25.0 / gemini / node@24.13.0 npm@built-in (default)
package @google/jules@0.1.42 / jules / node@24.13.0 npm@built-in (default)
package happy-coder@0.13.0 / happy, happy-mcp / node@24.13.0 npm@built-in (default)
package wrangler@4.59.1 / wrangler, wrangler2 / node@24.13.0 npm@built-in (default)`,
			expected: []voltaPackage{
				{name: "@google/gemini-cli", version: "0.25.0"},
				{name: "@google/jules", version: "0.1.42"},
				{name: "happy-coder", version: "0.13.0"},
				{name: "wrangler", version: "4.59.1"},
			},
		},
		{
			name: "non-default package ignored",
			input: `runtime node@24.13.0 (default)
package old-tool@1.0.0 / old-tool / node@22.0.0 npm@built-in
package wrangler@4.59.1 / wrangler / node@24.13.0 npm@built-in (default)`,
			expected: []voltaPackage{
				{name: "wrangler", version: "4.59.1"},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, _ := parseVoltaList(tt.input)

			if len(result) != len(tt.expected) {
				t.Errorf("expected %d packages, got %d", len(tt.expected), len(result))
				return
			}

			for i, pkg := range result {
				if pkg.name != tt.expected[i].name {
					t.Errorf("package[%d]: expected name=%s, got %s", i, tt.expected[i].name, pkg.name)
				}
				if pkg.version != tt.expected[i].version {
					t.Errorf("package[%d]: expected version=%s, got %s", i, tt.expected[i].version, pkg.version)
				}
			}
		})
	}
}

func TestParseVoltaList_UnparsedLines(t *testing.T) {
	// Test that unparsed lines are captured
	input := `runtime node@24.13.0 (default)
package wrangler@4.59.1 / wrangler / node@24.13.0 npm@built-in (default)
package malformed-line (default)
package another@1.0.0 / another / node@24.13.0 npm@built-in (default)`

	result, unparsed := parseVoltaList(input)

	if len(result) != 2 {
		t.Errorf("expected 2 parsed packages, got %d", len(result))
	}
	if len(unparsed) != 1 {
		t.Errorf("expected 1 unparsed line, got %d", len(unparsed))
	}
	if len(unparsed) > 0 && unparsed[0] != "package malformed-line (default)" {
		t.Errorf("unexpected unparsed line: %s", unparsed[0])
	}
}
