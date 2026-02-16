package cmds

import (
	"github.com/kendricklawton/project-platform/core/internal/cli"
	"github.com/spf13/cobra"
)

var projectCmd = &cobra.Command{
	Use:   "projects",
	Short: "Manage your platform projects",
	Long:  `Login, logout, and manage your account settings or session tokens.`,
}

func init() {
	projectCmd.AddCommand(deployCmd)
	cli.RootCmd.AddCommand(projectCmd)
}
