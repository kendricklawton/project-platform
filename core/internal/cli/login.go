package cli

import (
	"context"
	"fmt"
	"net/http"

	"github.com/pkg/browser"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

var loginCmd = &cobra.Command{
	Use:   "login",
	Short: "Authenticate with your platform account via WorkOS",
	Run: func(cmd *cobra.Command, args []string) {
		apiUrl := viper.GetString("api_url")
		if apiUrl == "" {
			apiUrl = "http://localhost:8080"
		}

		// 1. Create a channel to wait for the token
		tokenChan := make(chan string)
		errChan := make(chan error)

		// 2. Setup the temporary local server
		m := http.NewServeMux()
		srv := &http.Server{Addr: ":8989", Handler: m}

		m.HandleFunc("/callback", func(w http.ResponseWriter, r *http.Request) {
			token := r.URL.Query().Get("token")
			if token == "" {
				fmt.Fprintln(w, "Authentication failed: No token received. You can close this window.")
				errChan <- fmt.Errorf("no token received from API")
				return
			}

			// Render a success page to the browser
			fmt.Fprintln(w, "✅ Authentication successful! You can close this window and return to your terminal.")
			tokenChan <- token
		})

		// Start the server in a goroutine
		go func() {
			if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
				errChan <- err
			}
		}()

		// 3. Open the user's browser to your API's login endpoint
		// We pass the local callback URL so the API knows where to send the token
		loginURL := fmt.Sprintf("%s/auth/login?redirect_uri=http://localhost:8989/callback", apiUrl)
		fmt.Println("Opening browser to authenticate...")

		if err := browser.OpenURL(loginURL); err != nil {
			fmt.Printf("Failed to open browser automatically. Please go to: %s\n", loginURL)
		}

		// 4. Wait for the browser to redirect back
		select {
		case token := <-tokenChan:
			// Save the token to ~/.platform.yaml
			viper.Set("token", token)
			if err := viper.WriteConfig(); err != nil {
				fmt.Printf("Error saving token: %v\n", err)
			} else {
				fmt.Println("🎉 Successfully logged in!")
			}
		case err := <-errChan:
			fmt.Printf("❌ Login failed: %v\n", err)
		}

		// 5. Shut down the local server
		srv.Shutdown(context.Background())
	},
}

func init() {
	rootCmd.AddCommand(loginCmd)
}
