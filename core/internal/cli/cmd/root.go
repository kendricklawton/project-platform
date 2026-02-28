package cmd

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

var cfgFile string

// rootCmd represents the base command when called without any subcommands
var rootCmd = &cobra.Command{
	Use:   "platform",
	Short: "The Project Platform CLI",
	Long:  `Deploy and manage your web services, functions, and batch jobs right from the terminal.`,
}

// Execute adds all child commands to the root command and sets flags appropriately.
func Execute() {
	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func init() {
	cobra.OnInitialize(initConfig)

	// Global flags
	rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "", "config file (default is $HOME/.platform/config.json)")

	// Default values
	viper.SetDefault("api_url", "http://localhost:8080")
}

// initConfig reads in config file and ENV variables if set.
func initConfig() {
	if cfgFile != "" {
		viper.SetConfigFile(cfgFile)
	} else {
		home, err := os.UserHomeDir()
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}

		viper.AddConfigPath(filepath.Join(home, ".platform"))
		viper.SetConfigType("json")
		viper.SetConfigName("config")
	}

	viper.SetEnvPrefix("PLATFORM")
	viper.AutomaticEnv()

	if err := viper.ReadInConfig(); err == nil {
		// Silently load config
	}
}
