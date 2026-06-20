// Package main is the entry point for the mycli command.
package main

import (
	"context"
	"fmt"
	"os"

	"github.com/alecthomas/kong"
	"go.opentelemetry.io/otel/codes"

	"github.com/kikulabo/mycli-kikulabo-private/internal/cmd"
	"github.com/kikulabo/mycli-kikulabo-private/internal/tracing"
)

type CLI struct {
	Hello cmd.HelloCmd `cmd:"" help:"Print Hello, World!"`
}

func main() {
	os.Exit(run())
}

func run() int {
	ctx := context.Background()

	shutdown, err := tracing.Init(ctx)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		return 1
	}
	defer shutdown(ctx) //nolint:errcheck

	ctx, span := tracing.Tracer().Start(ctx, "main")
	defer span.End()

	if len(os.Args) == 1 {
		os.Args = append(os.Args, "--help")
	}
	k := kong.Parse(&CLI{}, kong.BindFor[context.Context](ctx))
	if err := k.Run(); err != nil {
		tracing.SetSpanError(span, err)
		k.Fatalf("%v", err)
		return 1
	}

	span.SetStatus(codes.Ok, "")
	return 0
}
