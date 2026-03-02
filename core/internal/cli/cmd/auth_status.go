package cmd

import (
	"fmt"

	"github.com/kendricklawton/project-platform/core/internal/cli/tui"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

var authStatusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show current authentication state",
	Run: func(cmd *cobra.Command, args []string) {
		token := viper.GetString("token")
		if token == "" {
			tui.ShowInfo("Not authenticated. Run: plat auth login")
			return
		}
		masked := token
		if len(token) > 12 {
			masked = token[:8] + "..." + token[len(token)-4:]
		}
		tui.ShowSuccess(fmt.Sprintf("Authenticated  token: %s", masked))
	},
}

func init() {
	authCmd.AddCommand(authStatusCmd)
}
