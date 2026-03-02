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
	Use:   "plat",
	Short: "The plat CLI",
	Long:  `Deploy and manage your services right from the terminal.`,
}

// Execute runs the root command.
func Execute() {
	cobra.CheckErr(rootCmd.Execute())
}

func init() {
	cobra.OnInitialize(initConfig)

	rootCmd.PersistentFlags().StringVar(&cfgFile, "config", "", "config file (default is $HOME/.plat/config.json)")
	rootCmd.PersistentFlags().String("token", "", "Auth token (overrides PLAT_TOKEN env var)")
	cobra.CheckErr(viper.BindPFlag("token", rootCmd.PersistentFlags().Lookup("token")))

	viper.SetDefault("api_url", "https://api.projectplatform.dev")
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

		viper.AddConfigPath(filepath.Join(home, ".plat"))
		viper.SetConfigType("json")
		viper.SetConfigName("config")
	}

	viper.SetEnvPrefix("PLAT")
	viper.AutomaticEnv()

	if err := viper.ReadInConfig(); err == nil {
		// Silently load config
	}
}
