package cmd

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/kendricklawton/project-platform/core/internal/cli/api"
	"github.com/kendricklawton/project-platform/core/internal/cli/tui"
	"github.com/spf13/cobra"
)

var secretCmd = &cobra.Command{
	Use:   "secret",
	Short: "Manage service secrets",
}

var secretSetCmd = &cobra.Command{
	Use:   "set KEY VALUE",
	Short: "Set a secret",
	Args:  cobra.ExactArgs(2),
	Run: func(cmd *cobra.Command, args []string) {
		key, value := args[0], args[1]
		client := api.New()
		if !client.HasToken() {
			tui.ShowError("Not authenticated. Run: plat auth login")
			os.Exit(1)
		}
		var reqErr error
		_ = tui.RunLoader(fmt.Sprintf("Setting %s...", key), func() {
			payload := map[string]any{"key": key, "value": value}
			resp, err := client.Post("/v1/secrets", payload)
			if err != nil {
				reqErr = err
				return
			}
			resp.Body.Close()
		})
		if reqErr != nil {
			tui.ShowError(fmt.Sprintf("Failed: %v", reqErr))
			os.Exit(1)
		}
		tui.ShowSuccess(fmt.Sprintf("Secret %s set.", key))
	},
}

var secretListCmd = &cobra.Command{
	Use:   "list",
	Short: "List secret keys (not values)",
	Run: func(cmd *cobra.Command, args []string) {
		client := api.New()
		if !client.HasToken() {
			tui.ShowError("Not authenticated. Run: plat auth login")
			os.Exit(1)
		}
		var keys []string
		_ = tui.RunLoader("Fetching secrets...", func() {
			resp, err := client.Get("/v1/secrets")
			if err != nil {
				return
			}
			defer resp.Body.Close()
			json.NewDecoder(resp.Body).Decode(&keys)
		})
		if len(keys) == 0 {
			tui.ShowInfo("No secrets set.")
			return
		}
		for _, k := range keys {
			fmt.Println(tui.BaseStyle.Render("  " + k))
		}
	},
}

var secretDeleteCmd = &cobra.Command{
	Use:   "delete KEY",
	Short: "Delete a secret",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		key := args[0]
		client := api.New()
		if !client.HasToken() {
			tui.ShowError("Not authenticated. Run: plat auth login")
			os.Exit(1)
		}
		confirm, err := tui.Confirm(fmt.Sprintf("Delete secret %s?", key))
		if err != nil || !confirm {
			tui.ShowInfo("Cancelled.")
			return
		}
		var reqErr error
		_ = tui.RunLoader(fmt.Sprintf("Deleting %s...", key), func() {
			resp, err := client.Delete("/v1/secrets/" + key)
			if err != nil {
				reqErr = err
				return
			}
			resp.Body.Close()
		})
		if reqErr != nil {
			tui.ShowError(fmt.Sprintf("Failed: %v", reqErr))
			os.Exit(1)
		}
		tui.ShowSuccess(fmt.Sprintf("Secret %s deleted.", key))
	},
}

func init() {
	secretCmd.AddCommand(secretSetCmd)
	secretCmd.AddCommand(secretListCmd)
	secretCmd.AddCommand(secretDeleteCmd)
	rootCmd.AddCommand(secretCmd)
}
