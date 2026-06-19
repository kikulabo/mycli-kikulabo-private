// Package cmd defines subcommands for mycli.
package cmd

import (
	"context"
	"fmt"
)

// HelloCmd implements the hello subcommand.
type HelloCmd struct{}

// Run executes the hello subcommand.
func (c *HelloCmd) Run(_ context.Context) error {
	fmt.Println("Hello, World!")
	return nil
}
