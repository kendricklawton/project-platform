package main

import (
	"fmt"
	"log"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"golang.org/x/net/http2"
	"golang.org/x/net/http2/h2c"

	"github.com/kendricklawton/project-platform/core/internal/api"
	"github.com/kendricklawton/project-platform/core/internal/config"
	"github.com/kendricklawton/project-platform/core/internal/db"
	"github.com/kendricklawton/project-platform/core/internal/service"
	"github.com/kendricklawton/project-platform/gen/go/platform/v1/platformv1connect"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config error: %v", err)
	}

	store, err := db.Connect(cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("db connection failed: %v", err)
	}
	defer store.Close()

	// Initialize standard handlers (Auth) and Connect services (Teams/Users)
	authHandler := api.NewHandler(nil, store, cfg.WorkOSAPIKey, cfg.WorkOSClientID)
	teamSvc := &service.TeamServer{Store: store}

	// Setup Chi Router
	r := chi.NewRouter()
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)

	// Mount Standard REST Routes (for Auth callbacks)
	r.Get("/v1/auth/login", authHandler.AuthLogin)
	r.Get("/v1/auth/callback", authHandler.AuthCallback)

	// Mount ConnectRPC Routes (Protected by Auth Middleware)
	r.Group(func(protected chi.Router) {
		protected.Use(authHandler.RequireAuth)

		teamPath, teamHandler := platformv1connect.NewTeamServiceHandler(teamSvc)
		protected.Mount(teamPath, teamHandler)
	})

	log.Printf("🚀 Platform Control Plane running on :%d", cfg.Port)

	// h2c allows HTTP/2 for gRPC speed during local dev
	if err := http.ListenAndServe(fmt.Sprintf(":%d", cfg.Port), h2c.NewHandler(r, &http2.Server{})); err != nil {
		log.Fatalf("server crashed: %v", err)
	}
}
