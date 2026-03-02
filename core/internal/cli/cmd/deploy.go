package cmd

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/kendricklawton/project-platform/core/internal/cli/api"
	"github.com/kendricklawton/project-platform/core/internal/cli/tui"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

var deployWait bool

var deployCmd = &cobra.Command{
	Use:   "deploy",
	Short: "Deploy the current project",
	Run: func(cmd *cobra.Command, args []string) {
		client := api.New()
		if !client.HasToken() {
			tui.ShowError("Not authenticated. Run: plat auth login")
			os.Exit(1)
		}
		if _, err := os.Stat("plat.toml"); os.IsNotExist(err) {
			tui.ShowError("No plat.toml found in current directory. Run: plat init")
			os.Exit(1)
		}

		var result map[string]any
		var reqErr error

		_ = tui.RunLoader("Deploying...", func() {
			payload := map[string]any{
				"branch": viper.GetString("deploy.branch"),
				"wait":   deployWait,
			}
			resp, err := client.Post("/v1/deploy", payload)
			if err != nil {
				reqErr = err
				return
			}
			defer resp.Body.Close()
			json.NewDecoder(resp.Body).Decode(&result)
		})

		if reqErr != nil {
			tui.ShowError(fmt.Sprintf("Deploy failed: %v", reqErr))
			os.Exit(1)
		}
		if errMsg, ok := result["error"].(string); ok {
			tui.ShowError(fmt.Sprintf("Deploy failed: %s", errMsg))
			os.Exit(1)
		}
		if url, ok := result["url"].(string); ok {
			tui.ShowSuccess(fmt.Sprintf("Deployed → %s", url))
		} else {
			tui.ShowSuccess("Deployment triggered.")
		}
	},
}

func init() {
	deployCmd.Flags().String("branch", "", "Deploy a specific branch (overrides deploy.branch in config)")
	deployCmd.Flags().BoolVar(&deployWait, "wait", false, "Block until deploy completes")
	cobra.CheckErr(viper.BindPFlag("deploy.branch", deployCmd.Flags().Lookup("branch")))
	rootCmd.AddCommand(deployCmd)
}
