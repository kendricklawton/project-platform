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
	Short: "Authenticate via browser OAuth",
	Run: func(cmd *cobra.Command, args []string) {
		handleLogin()
	},
}

func init() {
	authCmd.AddCommand(loginCmd)
}

func handleLogin() {
	tui.ShowInfo("Opening your browser to log in...")

	apiLoginURL := viper.GetString("api_url") + "/v1/auth/login"
	cliPort := "9999"

	tokenChan := make(chan string)

	m := http.NewServeMux()
	m.HandleFunc("/callback", func(w http.ResponseWriter, r *http.Request) {
		token := r.URL.Query().Get("token")
		if token == "" {
			http.Error(w, "Authentication failed: no token received", http.StatusBadRequest)
			return
		}
		fmt.Fprintf(w, `<html><body style="font-family:monospace;padding:2rem;background:#09090b;color:#22c55e;">`)
		fmt.Fprintf(w, `<h2>> AUTHENTICATION_SUCCESSFUL</h2><p>You can close this window and return to your terminal.</p>`)
		fmt.Fprintf(w, `</body></html>`)
		tokenChan <- token
	})

	server := &http.Server{Addr: ":" + cliPort, Handler: m}
	go func() {
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			tui.ShowError(fmt.Sprintf("Failed to start local server: %v", err))
			os.Exit(1)
		}
	}()

	redirectURI := fmt.Sprintf("http://localhost:%s/callback", cliPort)
	loginURL := fmt.Sprintf("%s?redirect_uri=%s&state=cli-auth-request", apiLoginURL, redirectURI)
	openBrowser(loginURL)

	var token string
	_ = tui.RunLoader("Waiting for browser authentication...", func() {
		token = <-tokenChan
	})

	saveToken(token)
	server.Shutdown(context.Background())

	tui.ShowSuccess("Authenticated. Your CLI is ready to deploy.")
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
		tui.ShowError(fmt.Sprintf("Could not open browser. Navigate manually to: %s", url))
	}
}

func saveToken(token string) {
	viper.Set("token", token)

	home, _ := os.UserHomeDir()
	configDir := filepath.Join(home, ".plat")
	os.MkdirAll(configDir, 0755)

	configPath := filepath.Join(configDir, "config.json")
	if err := viper.WriteConfigAs(configPath); err != nil {
		tui.ShowError(fmt.Sprintf("Failed to save credentials: %v", err))
		os.Exit(1)
	}
}
