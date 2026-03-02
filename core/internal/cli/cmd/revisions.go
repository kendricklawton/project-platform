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

var revisionsCmd = &cobra.Command{
	Use:   "revisions",
	Short: "List deployment revisions",
	Run: func(cmd *cobra.Command, args []string) {
		client := api.New()
		if !client.HasToken() {
			tui.ShowError("Not authenticated. Run: plat auth login")
			os.Exit(1)
		}

		path := fmt.Sprintf("/v1/revisions?limit=%d", viper.GetInt("revisions.limit"))

		var rows []tui.RevisionRow
		_ = tui.RunLoader("Fetching revisions...", func() {
			resp, err := client.Get(path)
			if err != nil {
				return
			}
			defer resp.Body.Close()
			var result []map[string]any
			if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
				return
			}
			for _, r := range result {
				rows = append(rows, tui.RevisionRow{
					ID:        fmt.Sprintf("%v", r["id"]),
					Status:    fmt.Sprintf("%v", r["status"]),
					CreatedAt: fmt.Sprintf("%v", r["created_at"]),
					Message:   fmt.Sprintf("%v", r["message"]),
				})
			}
		})

		if len(rows) == 0 {
			tui.ShowInfo("No revisions found.")
			return
		}
		tui.RenderRevisionsTable(rows)
	},
}

func init() {
	revisionsCmd.Flags().Int("limit", 0, "Number of revisions to show (default 10, overridable via config)")
	cobra.CheckErr(viper.BindPFlag("revisions.limit", revisionsCmd.Flags().Lookup("limit")))
	viper.SetDefault("revisions.limit", 10)
	rootCmd.AddCommand(revisionsCmd)
}
