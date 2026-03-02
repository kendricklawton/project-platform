package cmd

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/kendricklawton/project-platform/core/internal/cli/api"
	"github.com/kendricklawton/project-platform/core/internal/cli/tui"
	"github.com/spf13/cobra"
)

var rollbackTo string

var rollbackCmd = &cobra.Command{
	Use:   "rollback",
	Short: "Roll back to a previous revision",
	Run: func(cmd *cobra.Command, args []string) {
		client := api.New()
		if !client.HasToken() {
			tui.ShowError("Not authenticated. Run: plat auth login")
			os.Exit(1)
		}

		target := "previous"
		if rollbackTo != "" {
			target = rollbackTo
		}

		confirm, err := tui.Confirm(fmt.Sprintf("Roll back to revision %s?", target))
		if err != nil || !confirm {
			tui.ShowInfo("Rollback cancelled.")
			return
		}

		var result map[string]any
		var reqErr error

		_ = tui.RunLoader(fmt.Sprintf("Rolling back to %s...", target), func() {
			payload := map[string]any{"to": rollbackTo}
			resp, err := client.Post("/v1/rollback", payload)
			if err != nil {
				reqErr = err
				return
			}
			defer resp.Body.Close()
			json.NewDecoder(resp.Body).Decode(&result)
		})

		if reqErr != nil {
			tui.ShowError(fmt.Sprintf("Rollback failed: %v", reqErr))
			os.Exit(1)
		}
		if errMsg, ok := result["error"].(string); ok {
			tui.ShowError(fmt.Sprintf("Rollback failed: %s", errMsg))
			os.Exit(1)
		}
		tui.ShowSuccess(fmt.Sprintf("Rolled back to %s.", target))
	},
}

func init() {
	rollbackCmd.Flags().StringVar(&rollbackTo, "to", "", "Specific revision to roll back to (e.g. v12)")
	rootCmd.AddCommand(rollbackCmd)
}
