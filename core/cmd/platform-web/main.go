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
	// 1. Load the decoupled configuration for the Web BFF
	cfg, err := config.LoadWeb()
	if err != nil {
		log.Fatalf("web config error: %v", err)
	}

	// 2. Initialize ConnectRPC Clients pointing to your Core API
	apiClient := http.DefaultClient
	userClient := platformv1connect.NewUserServiceClient(apiClient, cfg.APIURL)
	teamClient := platformv1connect.NewTeamServiceClient(apiClient, cfg.APIURL)

	// 3. Mount the Web BFF Handler
	// Passing cfg.APIURL here so auth.go knows where to send login requests
	webHandler := web.NewHandler(cfg.APIURL, userClient, teamClient)

	// 4. Start the Web Server on the configured port
	addr := fmt.Sprintf(":%d", cfg.Port)
	log.Printf("🌐 Platform Web Server starting on http://localhost%s", addr)
	log.Printf("🔗 Connected to Core API at %s", cfg.APIURL)

	if err := http.ListenAndServe(addr, webHandler.Routes()); err != nil {
		log.Fatalf("web server crashed: %v", err)
	}
}
