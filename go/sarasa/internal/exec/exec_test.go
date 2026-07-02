package exec

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestRunTimeoutKillsProcessGroup(t *testing.T) {
	dir := t.TempDir()
	marker := filepath.Join(dir, "child-finished")
	script := filepath.Join(dir, "spawn-child.sh")
	if err := os.WriteFile(script, []byte(`#!/bin/sh
(sleep 2; touch "$1") &
wait
`), 0o755); err != nil {
		t.Fatalf("write script: %v", err)
	}

	_, err := Run(context.Background(), Options{Timeout: 100 * time.Millisecond}, script, marker)
	if err == nil {
		t.Fatal("Run succeeded, want timeout")
	}

	time.Sleep(3 * time.Second)
	if _, statErr := os.Stat(marker); !errors.Is(statErr, os.ErrNotExist) {
		t.Fatalf("grandchild survived timeout; marker stat err=%v", statErr)
	}
}

func TestRunAppliesNonInteractiveEnvironment(t *testing.T) {
	dir := t.TempDir()
	output := filepath.Join(dir, "env.out")
	script := filepath.Join(dir, "env.sh")
	if err := os.WriteFile(script, []byte(`#!/bin/sh
printf '%s\n' "$NONINTERACTIVE" "$SUDO_ASKPASS" > "$1"
`), 0o755); err != nil {
		t.Fatalf("write script: %v", err)
	}

	if _, err := Run(context.Background(), Options{Timeout: time.Second}, script, output); err != nil {
		t.Fatalf("Run failed: %v", err)
	}
	got, err := os.ReadFile(output)
	if err != nil {
		t.Fatalf("read env output: %v", err)
	}
	want := "1\n/usr/bin/false\n"
	if string(got) != want {
		t.Fatalf("env output = %q, want %q", string(got), want)
	}
}
