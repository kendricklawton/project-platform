package main

import (
	"log"
	"net/http"

	"github.com/kendricklawton/project-platform/core/internal/web"
	"github.com/kendricklawton/project-platform/gen/go/platform/v1/platformv1connect"
)

func main() {
	// The URL where your backend platform-api is running
	apiURL := "http://localhost:8080"
	apiClient := http.DefaultClient
	userClient := platformv1connect.NewUserServiceClient(apiClient, apiURL)
	teamClient := platformv1connect.NewTeamServiceClient(apiClient, apiURL)

	webHandler := web.NewHandler(userClient, teamClient)

	log.Println("🌐 Platform Web Server starting on http://localhost:3000")
	if err := http.ListenAndServe(":3000", webHandler.Routes()); err != nil {
		log.Fatalf("web server crashed: %v", err)
	}
}
