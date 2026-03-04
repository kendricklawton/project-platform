package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"

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
		platToml := viper.New()
		platToml.SetConfigFile("plat.toml")
		if err := platToml.ReadInConfig(); err != nil {
			tui.ShowError("No plat.toml found in current directory. Run: plat init")
			os.Exit(1)
		}
		serviceName := platToml.GetString("app.name")

		var result map[string]any
		var reqErr error

		_ = tui.RunLoader("Deploying...", func() {
			payload := map[string]any{
				"service":        serviceName,
				"branch":         viper.GetString("deploy.branch"),
				"wait":           deployWait,
				"commit_sha":     gitOutput("rev-parse", "HEAD"),
				"commit_message": gitOutput("log", "-1", "--pretty=%s"),
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

// gitOutput runs a git subcommand and returns trimmed stdout.
// Returns an empty string if git is unavailable or the command fails.
func gitOutput(args ...string) string {
	out, err := exec.Command("git", args...).Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}
