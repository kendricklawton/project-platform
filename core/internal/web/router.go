package web

import (
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

func (h *Handler) Routes() chi.Router {
	router := chi.NewRouter()

	router.Use(middleware.Logger)
	router.Use(middleware.Recoverer)

	// --- Serve Static Assets (CSS, JS, Images) ---
	// This tells the router to serve files from your local "web/ui/static" folder
	// whenever a browser requests a URL starting with "/static/"
	fileServer := http.FileServer(http.Dir("internal/web/ui/static"))
	router.Handle("/static/*", http.StripPrefix("/static/", fileServer))

	// --- Public Routes ---
	router.Get("/", h.Splash)
	router.Get("/healthz", h.Healthz)
	router.Connect("/dashboard", h.Dashboard)

	// --- Authentication Flow ---
	router.Route("/auth", func(auth chi.Router) {
		auth.Get("/login", h.AuthLogin)
		auth.Get("/callback", h.AuthCallback)
		auth.Get("/logout", h.AuthLogout)
	})

	// --- Protected Dashboard Routes ---
	router.Group(func(protected chi.Router) {
		protected.Use(h.RequireAuth)
		// protected.Get("/dashboard", h.Dashboard)
	})

	return router
}
