package web

import (
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/kendricklawton/project-platform/core/internal/ui/components"
	"github.com/kendricklawton/project-platform/gen/go/platform/v1/platformv1connect"
)

type Handler struct {
	UserClient platformv1connect.UserServiceClient
	TeamClient platformv1connect.TeamServiceClient
}

func NewHandler(uc platformv1connect.UserServiceClient, tc platformv1connect.TeamServiceClient) *Handler {
	return &Handler{UserClient: uc, TeamClient: tc}
}

func (h *Handler) Routes() chi.Router {
	r := chi.NewRouter()

	// 1. Serve Tailwind CSS
	fs := http.FileServer(http.Dir("internal/ui/static"))
	r.Handle("/static/*", http.StripPrefix("/static/", fs))

	// 2. The main Splash Page
	r.Get("/", func(w http.ResponseWriter, r *http.Request) {
		components.Splash("INITIALIZING...").Render(r.Context(), w)
	})

	r.Get("/dashboard", func(w http.ResponseWriter, r *http.Request) {
		/* TODO: This is where we will make the real ConnectRPC call later!
		   cookie, _ := r.Cookie("auth_token")
		   req := connect.NewRequest(&platformv1.GetMeRequest{})
		   req.Header().Set("Authorization", cookie.Value)
		   res, err := h.UserClient.GetMe(r.Context(), req)
		   userName := res.Msg.User.Name
		*/

		// For now, let's mock the data from the API
		userName := "Kendrick Lawton"

		// Render the Dashboard template, passing in the Go variable
		components.Dashboard(userName).Render(r.Context(), w)
	})

	// 3. HTMX target endpoint
	r.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
		// Updated with light/dark mode support
		readyHTML := `
				<div id="status-container" class="transition-opacity duration-700">
					<p class="text-xs font-mono text-green-600 dark:text-green-400 tracking-widest uppercase mb-12">
						SYSTEMS_READY
					</p>

					<a href="/dashboard" class="px-8 py-3 border border-zinc-300 dark:border-zinc-800 text-zinc-600 dark:text-zinc-400 text-xs font-mono tracking-widest hover:bg-zinc-200 dark:hover:bg-zinc-900 hover:text-black dark:hover:text-white transition-colors duration-300">
						ENTER_WORKSPACE
					</a>
				</div>
			`
		w.Write([]byte(readyHTML))
	})

	return r
}
