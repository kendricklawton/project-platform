package cli

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

var initCmd = &cobra.Command{
	Use:   "init",
	Short: "Initialize the platform CLI configuration",
	Run: func(cmd *cobra.Command, args []string) {
		home, err := os.UserHomeDir()
		if err != nil {
			fmt.Printf("Error finding home directory: %v\n", err)
			return
		}

		configPath := filepath.Join(home, ".platform.yaml")

		// Set default values
		viper.Set("api_url", "http://localhost:8080")
		viper.Set("region", "us-east")

		// Write the config file
		err = viper.WriteConfigAs(configPath)
		if err != nil {
			fmt.Printf("Error writing config file: %v\n", err)
			return
		}

		fmt.Printf("✅ Initialized empty configuration at %s\n", configPath)
		fmt.Println("👉 Next step: Run 'platform login' to authenticate.")
	},
}

func init() {
	rootCmd.AddCommand(initCmd)
}
