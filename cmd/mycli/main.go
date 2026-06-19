// Package main is the entry point for the mycli command.
package main

import (
	"context"
	"os"

	"github.com/alecthomas/kong"

	"github.com/kikulabo/mycli-kikulabo-private/internal/cmd"
)

type CLI struct {
	Hello cmd.HelloCmd `cmd:"" help:"Print Hello, World!"`
}

func main() {
	os.Exit(run())
}

func run() int {
	ctx := context.Background()
	if len(os.Args) == 1 {
		os.Args = append(os.Args, "--help")
	}
	k := kong.Parse(&CLI{}, kong.BindFor[context.Context](ctx))
	if err := k.Run(); err != nil {
		k.Fatalf("%v", err)
		return 1
	}
	return 0
}
