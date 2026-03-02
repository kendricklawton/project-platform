package main

import (
	"fmt"
	"log"
	"net/http"

	"github.com/kendricklawton/project-platform/core/internal/config"
	"github.com/kendricklawton/project-platform/core/internal/web"
	"github.com/kendricklawton/project-platform/gen/go/platform/v1/platformv1connect"
)

func main() {
	// 1. Load configuration
	cfg, err := config.LoadWeb()
	if err != nil {
		log.Fatalf("web config error: %v", err)
	}

	// 2. Initialize ConnectRPC clients pointing to the Core API
	apiClient := http.DefaultClient
	userClient := platformv1connect.NewUserServiceClient(apiClient, cfg.APIURL)
	teamClient := platformv1connect.NewTeamServiceClient(apiClient, cfg.APIURL)

	// 3. Mount the Web BFF Handler — no direct DB access, all data via Core API
	webHandler := web.NewHandler(
		cfg.APIURL,
		cfg.InternalSecret,
		cfg.WorkOSAPIKey,
		cfg.WorkOSClientID,
		cfg.WorkOSRedirectURI,
		userClient,
		teamClient,
	)

	// 4. Start the web server
	addr := fmt.Sprintf(":%d", cfg.Port)
	log.Printf("🌐 Platform Web Server starting on http://localhost%s", addr)
	log.Printf("🔗 Connected to Core API at %s", cfg.APIURL)

	if err := http.ListenAndServe(addr, webHandler.Routes()); err != nil {
		log.Fatalf("web server crashed: %v", err)
	}
}
