package cmd

import "github.com/spf13/cobra"

var authCmd = &cobra.Command{
	Use:   "auth",
	Short: "Manage authentication credentials",
	Long:  `Authenticate with the platform and manage stored credentials.`,
}

func init() {
	rootCmd.AddCommand(authCmd)
}
