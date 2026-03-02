package cmd

import (
	"os"
	"path/filepath"

	"github.com/kendricklawton/project-platform/core/internal/cli/tui"
	"github.com/spf13/cobra"
)

var logoutCmd = &cobra.Command{
	Use:   "logout",
	Short: "Remove stored credentials",
	Run: func(cmd *cobra.Command, args []string) {
		home, _ := os.UserHomeDir()
		configPath := filepath.Join(home, ".plat", "config.json")
		if err := os.Remove(configPath); err != nil && !os.IsNotExist(err) {
			tui.ShowError("Failed to remove credentials: " + err.Error())
			return
		}
		tui.ShowSuccess("Logged out.")
	},
}

func init() {
	authCmd.AddCommand(logoutCmd)
}
