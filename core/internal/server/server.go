package server

import (
	"fmt"
	"net/http"

	"golang.org/x/net/http2"
	"golang.org/x/net/http2/h2c"

	"github.com/kendricklawton/project-platform/core/internal/api"
	"github.com/kendricklawton/project-platform/core/internal/config"
	"github.com/kendricklawton/project-platform/core/internal/db"
	"github.com/kendricklawton/project-platform/core/internal/k8s"
	"github.com/kendricklawton/project-platform/core/internal/service"
)

type Server struct {
	httpServer *http.Server
	port       int
}

// New creates the server and handles all dependency injection.
func New(cfg *config.Config, store db.Store, k8sClient *k8s.Client) *Server {
	// 1. Initialize Individual Services
	teamSvc := &service.TeamServer{Store: store}
	userSvc := &service.UserServer{Store: store}

	// 2. Pack them into the API Registry
	registry := api.Services{
		Team: teamSvc,
		User: userSvc,
	}

	// 3. Initialize Core API Handler
	apiHandler := api.NewHandler(k8sClient, store, cfg.WorkOSAPIKey, cfg.WorkOSClientID, registry)

	// 4. Load Centralized Routes
	router := apiHandler.Routes()

	// 5. Configure the HTTP Server
	addr := fmt.Sprintf(":%d", cfg.Port)
	httpServer := &http.Server{
		Addr:    addr,
		Handler: h2c.NewHandler(router, &http2.Server{}),
	}

	return &Server{
		httpServer: httpServer,
		port:       cfg.Port,
	}
}

// Run starts the HTTP server.
func (s *Server) Run() error {
	return s.httpServer.ListenAndServe()
}
