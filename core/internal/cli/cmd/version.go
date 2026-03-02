package cmd

import (
	"fmt"
	"runtime"

	"github.com/spf13/cobra"
)

var Version = "v0.1.0-alpha"

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Print the plat CLI version",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Printf("plat %s (%s %s/%s)\n", Version, runtime.Version(), runtime.GOOS, runtime.GOARCH)
	},
}

func init() {
	rootCmd.AddCommand(versionCmd)
}
