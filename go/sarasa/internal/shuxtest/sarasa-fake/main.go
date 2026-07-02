package main

import (
	"github.com/indrasvat/sarasa/cmd"
	"github.com/indrasvat/sarasa/internal/shuxtest/fakemanager"
)

func main() {
	fakemanager.RegisterBuiltins()
	cmd.Execute()
}
