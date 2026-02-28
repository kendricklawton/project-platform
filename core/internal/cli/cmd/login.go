package cmd

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"

	"github.com/kendricklawton/project-platform/core/internal/cli/tui"
	"github.com/spf13/cobra"
	"github.com/spf13/viper"
)

var loginCmd = &cobra.Command{
	Use:   "login",
	Short: "Authenticate your CLI with Project Platform",
	Run: func(cmd *cobra.Command, args []string) {
		handleLogin()
	},
}

func init() {
	rootCmd.AddCommand(loginCmd)
}

func handleLogin() {
	// 1. Use ShowInfo for a subtle, muted startup message
	tui.ShowInfo("Opening your browser to log in to Project Platform...")

	apiLoginURL := viper.GetString("api_url") + "/v1/auth/login"
	cliPort := "9999"

	tokenChan := make(chan string)

	// Local server to catch the redirect
	m := http.NewServeMux()
	m.HandleFunc("/callback", func(w http.ResponseWriter, r *http.Request) {
		token := r.URL.Query().Get("token")
		if token == "" {
			http.Error(w, "Authentication failed: No token received", http.StatusBadRequest)
			return
		}

		// A terminal-inspired success page
		fmt.Fprintf(w, "<html><body style='font-family: monospace; padding: 2rem; background: #09090b; color: #22c55e;'>")
		fmt.Fprintf(w, "<h2>> AUTHENTICATION_SUCCESSFUL</h2><p>You can safely close this window and return to your terminal.</p>")
		fmt.Fprintf(w, "</body></html>")

		tokenChan <- token
	})

	server := &http.Server{Addr: ":" + cliPort, Handler: m}
	go func() {
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			tui.ShowError(fmt.Sprintf("Failed to start local server: %v", err))
			os.Exit(1)
		}
	}()

	// Trigger the browser
	redirectURI := fmt.Sprintf("http://localhost:%s/callback", cliPort)
	loginURL := fmt.Sprintf("%s?redirect_uri=%s&state=cli-auth-request", apiLoginURL, redirectURI)
	openBrowser(loginURL)

	var token string

	// 2. Wrap the blocking channel in the TUI Loader!
	// This will show a clean dot spinner while the user completes the flow in the browser.
	_ = tui.RunLoader("Waiting for browser authentication...", func() {
		token = <-tokenChan // The spinner spins until this channel receives the token
	})

	// Save token utilizing Viper
	saveToken(token)

	// Clean up
	server.Shutdown(context.Background())

	// 3. Use ShowSuccess for that clean, green checkmark
	tui.ShowSuccess("Successfully logged in! Your CLI is ready to deploy.")
}

func openBrowser(url string) {
	var err error
	switch runtime.GOOS {
	case "linux":
		err = exec.Command("xdg-open", url).Start()
	case "windows":
		err = exec.Command("rundll32", "url.dll,FileProtocolHandler", url).Start()
	case "darwin":
		err = exec.Command("open", url).Start()
	default:
		err = fmt.Errorf("unsupported platform")
	}
	if err != nil {
		// Use ShowError for consistency
		tui.ShowError(fmt.Sprintf("Failed to open browser. Please manually navigate to: %s", url))
	}
}

func saveToken(token string) {
	viper.Set("token", token)

	home, _ := os.UserHomeDir()
	configDir := filepath.Join(home, ".platform")
	os.MkdirAll(configDir, 0755)

	configPath := filepath.Join(configDir, "config.json")

	if err := viper.WriteConfigAs(configPath); err != nil {
		tui.ShowError(fmt.Sprintf("Failed to save configuration: %v", err))
		os.Exit(1)
	}
}
