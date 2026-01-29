package cli

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

var cfgFile string

var rootCmd = &cobra.Command{
	Use:   "platform",
	Short: "The Project Platorm CLI",
}

// Execute is the entry point called by main.go
func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func init() {
	cobra.OnInitialize(initConfig)

	// 1. Global Flag: Allow user to specify a custom config file
	rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "", "config file (default is $HOME/.platform.yaml)")

	// 2. Local Flag: Example of a persistent flag (available to all commands)
	rootCmd.PersistentFlags().StringP("region", "r", "us-east", "Target region")

	// 3. Bind Viper to the flag
	// This allows you to access the value via viper.GetString("region")
	viper.BindPFlag("region", rootCmd.PersistentFlags().Lookup("region"))
}

func initConfig() {
	if cfgFile != "" {
		viper.SetConfigFile(cfgFile)
	} else {
		// Find home directory.
		home, err := os.UserHomeDir()
		if err != nil {
			fmt.Println(err)
			os.Exit(1)
		}

		// Search config in home directory with name ".platform" (without extension).
		viper.AddConfigPath(home)
		viper.SetConfigType("yaml")
		viper.SetConfigName(".platform")
	}

	// Read in environment variables that match "PLATFORM_*"
	viper.SetEnvPrefix("platform")
	viper.AutomaticEnv()

	if err := viper.ReadInConfig(); err == nil {
		// Optional: fmt.Println("Using config file:", viper.ConfigFileUsed())
	}
}
