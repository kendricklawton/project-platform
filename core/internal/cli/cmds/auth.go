package cmds

import (
	"context"
	"fmt"
	"net/http"

	"github.com/kendricklawton/project-platform/core/internal/cli"
	"github.com/kendricklawton/project-platform/core/internal/cli/utils"
	"github.com/pkg/browser"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

var authCmd = &cobra.Command{
	Use:   "auth",
	Short: "Manage your platform account and authentication",
	Long:  `Login, logout, and manage your account settings or session tokens.`,
}

// Auth Commands
var loginCmd = &cobra.Command{
	Use:   "login",
	Short: "Log in to your platform account",
	Long:  "Log in to your platform account using the OAuth2 flow.",
	Run: func(cmd *cobra.Command, args []string) {
		apiUrl := viper.GetString("api_url")
		tokenChan := make(chan string)

		state, _ := utils.GenerateState(16)

		m := http.NewServeMux()
		srv := &http.Server{Addr: ":8989", Handler: m}

		m.HandleFunc("/callback", func(w http.ResponseWriter, r *http.Request) {
			if r.URL.Query().Get("state") != state {
				fmt.Fprintln(w, "Security mismatch. Closing.")
				return
			}
			token := r.URL.Query().Get("token")
			fmt.Fprintln(w, "✅ Authenticated! You can close this tab.")
			tokenChan <- token
		})

		go srv.ListenAndServe()

		loginURL := fmt.Sprintf("%s/auth/login?redirect_uri=http://localhost:8989/callback&state=%s", apiUrl, state)
		fmt.Println("Opening browser...")
		browser.OpenURL(loginURL)

		token := <-tokenChan
		viper.Set("token", token)
		viper.WriteConfig()

		fmt.Println("🎉 Successfully logged in!")
		srv.Shutdown(context.Background())
	},
}

var logoutCmd = &cobra.Command{
	Use:   "logout",
	Short: "Log out of your platform account",
	Run: func(cmd *cobra.Command, args []string) {
		viper.Set("token", "")
		if err := viper.WriteConfig(); err != nil {
			fmt.Println("❌ Error clearing session.")
			return
		}
		fmt.Println("👋 Successfully logged out. Session cleared.")
	},
}

var whoamiCmd = &cobra.Command{
	Use:   "whoami",
	Short: "Display information about the current logged-in user",
	Run: func(cmd *cobra.Command, args []string) {
		token := viper.GetString("token")
		if token == "" {
			fmt.Println("🚫 You are not logged in. Run 'plat login' to get started.")
			return
		}

		// In a real implementation, you would call your API's /auth/whoami endpoint here
		fmt.Println("👤 Currently logged in as: (Fetching profile details...)")
		fmt.Printf("🔑 Token: %s...%s\n", token[:5], token[len(token)-5:])
	},
}

func init() {
	authCmd.AddCommand(loginCmd)
	authCmd.AddCommand(logoutCmd)
	authCmd.AddCommand(whoamiCmd)
	cli.RootCmd.AddCommand(authCmd)
}
