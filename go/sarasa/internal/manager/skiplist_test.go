package manager

import (
	"testing"
)

func TestVolta_SetSkipList(t *testing.T) {
	opts := &Options{}
	v := NewVolta(opts)

	v.SetSkipList([]string{"agent-browser", "@google/gemini-cli"})

	if !opts.ShouldSkip("agent-browser") {
		t.Error("expected agent-browser to be skipped after SetSkipList")
	}
	if !opts.ShouldSkip("@google/gemini-cli") {
		t.Error("expected @google/gemini-cli to be skipped after SetSkipList")
	}
	if opts.ShouldSkip("wrangler") {
		t.Error("expected wrangler to not be skipped")
	}
}

func TestNPM_SetSkipList(t *testing.T) {
	opts := &Options{}
	n := NewNPM(opts)

	n.SetSkipList([]string{"typescript", "eslint"})

	if !opts.ShouldSkip("typescript") {
		t.Error("expected typescript to be skipped after SetSkipList")
	}
	if !opts.ShouldSkip("eslint") {
		t.Error("expected eslint to be skipped after SetSkipList")
	}
	if opts.ShouldSkip("prettier") {
		t.Error("expected prettier to not be skipped")
	}
}

func TestBun_SetSkipList(t *testing.T) {
	opts := &Options{}
	b := NewBun(opts)

	b.SetSkipList([]string{"bun-pkg"})

	if !opts.ShouldSkip("bun-pkg") {
		t.Error("expected bun-pkg to be skipped after SetSkipList")
	}
	if opts.ShouldSkip("other") {
		t.Error("expected other to not be skipped")
	}
}

func TestSetSkipList_OverwritesPrevious(t *testing.T) {
	opts := &Options{SkipList: []string{"old-pkg"}}
	v := NewVolta(opts)

	if !opts.ShouldSkip("old-pkg") {
		t.Error("expected old-pkg to be skipped initially")
	}

	v.SetSkipList([]string{"new-pkg"})

	if opts.ShouldSkip("old-pkg") {
		t.Error("expected old-pkg to no longer be skipped after SetSkipList override")
	}
	if !opts.ShouldSkip("new-pkg") {
		t.Error("expected new-pkg to be skipped after SetSkipList override")
	}
}

func TestSetSkipList_EmptyClears(t *testing.T) {
	opts := &Options{SkipList: []string{"pkg1"}}
	v := NewVolta(opts)

	v.SetSkipList([]string{})

	if opts.ShouldSkip("pkg1") {
		t.Error("expected pkg1 to no longer be skipped after setting empty list")
	}
}

func TestSetSkipList_NilClears(t *testing.T) {
	opts := &Options{SkipList: []string{"pkg1"}}
	v := NewVolta(opts)

	v.SetSkipList(nil)

	if opts.ShouldSkip("pkg1") {
		t.Error("expected pkg1 to no longer be skipped after setting nil list")
	}
}

// TestVoltaCheckOutdated_SkipFiltering verifies that the skip list filters
// packages during the parsing phase of CheckOutdated. Since CheckOutdated
// calls external commands, we test the filtering logic directly using
// parseVoltaList + ShouldSkip, which is the exact code path.
func TestVoltaCheckOutdated_SkipFiltering(t *testing.T) {
	input := `runtime node@24.13.0 (default)
package-manager npm@11.8.0 (default)
package agent-browser@0.8.5 / agent-browser / node@24.13.0 npm@built-in (default)
package wrangler@4.59.1 / wrangler, wrangler2 / node@24.13.0 npm@built-in (default)
package @google/gemini-cli@0.25.0 / gemini / node@24.13.0 npm@built-in (default)
package pilotty@0.0.6 / pilotty / node@24.13.0 npm@built-in (default)`

	installed, _ := parseVoltaList(input)

	opts := &Options{
		SkipList: []string{"agent-browser", "@google/gemini-cli"},
	}

	var filtered []voltaPackage
	for _, pkg := range installed {
		if opts.ShouldSkip(pkg.name) {
			continue
		}
		filtered = append(filtered, pkg)
	}

	if len(filtered) != 2 {
		t.Fatalf("expected 2 packages after filtering, got %d", len(filtered))
	}
	if filtered[0].name != "wrangler" {
		t.Errorf("expected first package to be wrangler, got %s", filtered[0].name)
	}
	if filtered[1].name != "pilotty" {
		t.Errorf("expected second package to be pilotty, got %s", filtered[1].name)
	}
}

// TestVoltaCheckOutdated_SkipAll verifies that skipping all packages yields
// an empty result.
func TestVoltaCheckOutdated_SkipAll(t *testing.T) {
	input := `runtime node@24.13.0 (default)
package agent-browser@0.8.5 / agent-browser / node@24.13.0 npm@built-in (default)
package wrangler@4.59.1 / wrangler / node@24.13.0 npm@built-in (default)`

	installed, _ := parseVoltaList(input)

	opts := &Options{
		SkipList: []string{"agent-browser", "wrangler"},
	}

	var filtered []voltaPackage
	for _, pkg := range installed {
		if opts.ShouldSkip(pkg.name) {
			continue
		}
		filtered = append(filtered, pkg)
	}

	if len(filtered) != 0 {
		t.Errorf("expected 0 packages after skipping all, got %d", len(filtered))
	}
}

// TestVoltaCheckOutdated_EmptySkipFiltersNothing verifies that an empty skip
// list does not filter any packages.
func TestVoltaCheckOutdated_EmptySkipFiltersNothing(t *testing.T) {
	input := `runtime node@24.13.0 (default)
package agent-browser@0.8.5 / agent-browser / node@24.13.0 npm@built-in (default)
package wrangler@4.59.1 / wrangler / node@24.13.0 npm@built-in (default)`

	installed, _ := parseVoltaList(input)

	opts := &Options{
		SkipList: []string{},
	}

	var filtered []voltaPackage
	for _, pkg := range installed {
		if opts.ShouldSkip(pkg.name) {
			continue
		}
		filtered = append(filtered, pkg)
	}

	if len(filtered) != 2 {
		t.Errorf("expected 2 packages with empty skip list, got %d", len(filtered))
	}
}
