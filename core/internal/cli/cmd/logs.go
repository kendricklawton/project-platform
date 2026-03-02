package cmd

import (
	"bufio"
	"fmt"
	"os"

	"github.com/kendricklawton/project-platform/core/internal/cli/api"
	"github.com/kendricklawton/project-platform/core/internal/cli/tui"
	"github.com/spf13/cobra"
)

var (
	logsService string
	logsSince   string
)

var logsCmd = &cobra.Command{
	Use:   "logs",
	Short: "Stream live logs",
	Run: func(cmd *cobra.Command, args []string) {
		client := api.New()
		if !client.HasToken() {
			tui.ShowError("Not authenticated. Run: plat auth login")
			os.Exit(1)
		}

		path := "/v1/logs"
		sep := "?"
		if logsService != "" {
			path += sep + "service=" + logsService
			sep = "&"
		}
		if logsSince != "" {
			path += sep + "since=" + logsSince
		}

		label := "logs"
		if logsService != "" {
			label = logsService + " logs"
		}
		tui.ShowInfo(fmt.Sprintf("Streaming %s...", label))

		resp, err := client.Get(path)
		if err != nil {
			tui.ShowError("Failed to connect: " + err.Error())
			os.Exit(1)
		}
		defer resp.Body.Close()

		scanner := bufio.NewScanner(resp.Body)
		for scanner.Scan() {
			tui.StreamLog("stdout", scanner.Text())
		}
	},
}

func init() {
	logsCmd.Flags().StringVar(&logsService, "service", "", "Logs for a specific service")
	logsCmd.Flags().StringVar(&logsSince, "since", "", "Show logs from a duration ago (e.g. 1h, 30m)")
	rootCmd.AddCommand(logsCmd)
}
