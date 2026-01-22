package manager_test

import (
	"testing"

	"github.com/indrasvat/sarasa/internal/manager"
)

func TestOptions_ShouldSkip(t *testing.T) {
	opts := &manager.Options{
		SkipList: []string{"pkg1", "pkg2", "pkg3"},
	}

	tests := []struct {
		pkg      string
		expected bool
	}{
		{"pkg1", true},
		{"pkg2", true},
		{"pkg3", true},
		{"pkg4", false},
		{"", false},
		{"PKG1", false}, // case sensitive
	}

	for _, tt := range tests {
		t.Run(tt.pkg, func(t *testing.T) {
			got := opts.ShouldSkip(tt.pkg)
			if got != tt.expected {
				t.Errorf("ShouldSkip(%q) = %v, want %v", tt.pkg, got, tt.expected)
			}
		})
	}
}

func TestOptions_ShouldSkip_EmptyList(t *testing.T) {
	opts := &manager.Options{
		SkipList: []string{},
	}

	if opts.ShouldSkip("anything") {
		t.Error("ShouldSkip should return false with empty list")
	}
}

func TestOptions_ShouldSkip_NilList(t *testing.T) {
	opts := &manager.Options{
		SkipList: nil,
	}

	if opts.ShouldSkip("anything") {
		t.Error("ShouldSkip should return false with nil list")
	}
}
