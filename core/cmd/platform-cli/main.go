package main

import (
	"github.com/kendricklawton/project-platform/core/internal/cli"
	_ "github.com/kendricklawton/project-platform/core/internal/cli/cmds"
)

func main() {
	cli.Execute()
}
