// Package cmd defines subcommands for mycli.
package cmd

import (
	"context"
	"fmt"

	"go.opentelemetry.io/otel/codes"

	"github.com/kikulabo/mycli-kikulabo-private/internal/tracing"
)

// HelloCmd implements the hello subcommand.
type HelloCmd struct{}

// Run executes the hello subcommand.
func (c *HelloCmd) Run(ctx context.Context) error {
	_, span := tracing.Tracer().Start(ctx, "hello")
	defer span.End()

	fmt.Println("Hello, World!")

	span.SetStatus(codes.Ok, "")
	return nil
}
