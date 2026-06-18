// Package main is the entry point for the mycli command.
package main

import (
	"os"

	"github.com/alecthomas/kong"
)

type CLI struct{}

func main() {
	os.Exit(run())
}

func run() int {
	if len(os.Args) == 1 {
		os.Args = append(os.Args, "--help")
	}
	kong.Parse(&CLI{})
	return 0
}
