package api

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

func (handler *Handler) Routes() chi.Router {
	router := chi.NewRouter()

	// Standard middleware
	router.Use(middleware.CleanPath)
	router.Use(middleware.Logger)
	router.Use(middleware.Recoverer)

	// Custom JSON Error Handlers
	router.NotFound(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{"error": "endpoint not found"})
	})

	router.MethodNotAllowed(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusMethodNotAllowed)
		json.NewEncoder(w).Encode(map[string]string{"error": "method not allowed"})
	})

	// API Versioning
	router.Route("/v1", func(v1 chi.Router) {
		v1.Route("/auth", func(route chi.Router) {
			route.Get("/login", handler.AuthLogin)
			route.Get("/callback", handler.AuthCallback)
		})

		v1.Group(func(route chi.Router) {
			route.Use(handler.RequireAuth)
			// route.Post("/projects", handler.CreateProject)
			// route.Post("/deployments", handler.CreateDeployment)
		})

		// ADMIN ROUTES
		v1.Route("/admin", func(route chi.Router) {
			// route.Get("/status", handler.GetSystemStatus)
		})
	})

	return router
}
