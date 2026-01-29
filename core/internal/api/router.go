package api

import (
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

func (h *Handler) Routes() chi.Router {
	r := chi.NewRouter()

	// Global Middleware (Logging, RequestID)
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)

	// -----------------------------------------------------------
	// 1. PUBLIC / USER ROUTES
	// -----------------------------------------------------------
	r.Group(func(r chi.Router) {
		// 1. Create the Space
		r.Post("/projects", h.CreateProject)

		// 2. Deploy to the Space
		r.Post("/deployments", h.CreateDeployment)
	})
	// -----------------------------------------------------------
	// 2. ADMIN ROUTES
	// -----------------------------------------------------------
	r.Route("/admin", func(r chi.Router) {
		// CRITICAL: Admin-only Middleware
		// r.Use(AdminOnlyMiddleware)

		r.Get("/status", h.GetSystemStatus) // Calls handle_admin.go
	})

	return r
}
