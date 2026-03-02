package api

import (
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/kendricklawton/project-platform/gen/go/platform/v1/platformv1connect"
)

func (h *handler) Routes() chi.Router {
	router := chi.NewRouter()

	router.Use(middleware.CleanPath)
	router.Use(middleware.Logger)
	router.Use(middleware.Recoverer)

	router.Route("/v1", func(v1 chi.Router) {
		// --- REST Routes (OAuth Flow) ---
		v1.Route("/auth", func(auth chi.Router) {
			auth.Get("/login", h.authLogin)
			auth.Get("/callback", h.authCallback)
			// Internal: called by the web BFF to provision a user after WorkOS OAuth
			auth.With(h.requireInternal).Post("/provision", h.provisionUser)
		})

		// --- RPC Routes (Core API Platform) ---
		v1.Group(func(rpc chi.Router) {
			rpc.Use(h.requireAuth)

			// Mount ConnectRPC handlers utilizing the DI-injected services
			teamPath, teamHandler := platformv1connect.NewTeamServiceHandler(h.Services.Team)
			rpc.Mount(teamPath, teamHandler)

			userPath, userHandler := platformv1connect.NewUserServiceHandler(h.Services.User)
			rpc.Mount(userPath, userHandler)
		})
	})

	return router
}
