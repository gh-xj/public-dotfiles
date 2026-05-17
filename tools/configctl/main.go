package main

import (
	"os"

	"configctl/cmd"
)

func main() {
	os.Exit(cmd.Execute(os.Args[1:]))
}
