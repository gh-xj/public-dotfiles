package main

import (
	"fmt"
	"os"

	"github.com/alecthomas/kong"
)

func main() {
	os.Exit(execute(os.Args[1:]))
}

func execute(args []string) int {
	var cli CLI
	parser, err := kong.New(
		&cli,
		kong.Name("nvim-bench"),
		kong.Description("Reproducible Neovim activation benchmarks."),
		kong.UsageOnError(),
	)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}

	ctx, err := parser.Parse(args)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	if err := ctx.Run(&cli); err != nil {
		fmt.Fprintln(os.Stderr, "nvim-bench:", err)
		return 1
	}
	return 0
}
