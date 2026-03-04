package cmd

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"net/url"
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

	// Grab a random free port — hold the listener open so the OS doesn't
	// reuse the port before our HTTP server calls Serve on it.
	ln, err := net.Listen("tcp", "localhost:0")
	if err != nil {
		tui.ShowError(fmt.Sprintf("Failed to bind local port: %v", err))
		os.Exit(1)
	}
	port := ln.Addr().(*net.TCPAddr).Port
	redirectURI := fmt.Sprintf("http://localhost:%d/callback", port)

	tokenChan := make(chan string, 1)

	m := http.NewServeMux()
	m.HandleFunc("/callback", func(w http.ResponseWriter, r *http.Request) {
		token := r.URL.Query().Get("token")
		if token == "" {
			http.Error(w, "Authentication failed: no token received", http.StatusBadRequest)
			tokenChan <- ""
			return
		}
		fmt.Fprintf(w, `<html><body style="font-family:monospace;padding:2rem;background:#09090b;color:#22c55e;">`)
		fmt.Fprintf(w, `<h2>&gt; AUTHENTICATION_SUCCESSFUL</h2><p>You can close this window and return to your terminal.</p>`)
		fmt.Fprintf(w, `</body></html>`)
		tokenChan <- token
	})

	server := &http.Server{Handler: m}
	go func() {
		if err := server.Serve(ln); err != nil && err != http.ErrServerClosed {
			tui.ShowError(fmt.Sprintf("Local server error: %v", err))
			os.Exit(1)
		}
	}()

	webLoginURL := viper.GetString("web_url") + "/auth/cli/login"
	loginURL := fmt.Sprintf("%s?redirect_uri=%s", webLoginURL, url.QueryEscape(redirectURI))
	openBrowser(loginURL)

	var token string
	_ = tui.RunLoader("Waiting for browser authentication...", func() {
		token = <-tokenChan
	})

	server.Shutdown(context.Background())

	if token == "" {
		tui.ShowError("Authentication failed.")
		os.Exit(1)
	}

	saveToken(token)
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
