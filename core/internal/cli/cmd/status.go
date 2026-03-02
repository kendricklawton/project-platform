package cmd

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/kendricklawton/project-platform/core/internal/cli/api"
	"github.com/kendricklawton/project-platform/core/internal/cli/tui"
	"github.com/spf13/cobra"
)

var statusService string

var statusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show services and their state",
	Run: func(cmd *cobra.Command, args []string) {
		client := api.New()
		if !client.HasToken() {
			tui.ShowError("Not authenticated. Run: plat auth login")
			os.Exit(1)
		}

		path := "/v1/services"
		if statusService != "" {
			path = fmt.Sprintf("/v1/services/%s", statusService)
		}

		var rows []tui.ServiceRow
		_ = tui.RunLoader("Fetching status...", func() {
			resp, err := client.Get(path)
			if err != nil {
				return
			}
			defer resp.Body.Close()
			var result []map[string]any
			if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
				return
			}
			for _, s := range result {
				rows = append(rows, tui.ServiceRow{
					Name:     fmt.Sprintf("%v", s["name"]),
					Lang:     fmt.Sprintf("%v", s["lang"]),
					Status:   fmt.Sprintf("%v", s["status"]),
					Revision: fmt.Sprintf("%v", s["revision"]),
					URL:      fmt.Sprintf("%v", s["url"]),
				})
			}
		})

		if len(rows) == 0 {
			tui.ShowInfo("No services found.")
			return
		}
		tui.RenderServicesTable(rows)
	},
}

func init() {
	statusCmd.Flags().StringVar(&statusService, "service", "", "Show a specific service")
	rootCmd.AddCommand(statusCmd)
}
