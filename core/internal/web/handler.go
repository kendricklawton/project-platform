package web

import (
	"context"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/kendricklawton/project-platform/core/internal/web/ui/pages"
	"github.com/kendricklawton/project-platform/gen/go/platform/v1/platformv1connect"
)

type contextKey string

const userContextKey = contextKey("userName")

type Handler struct {
	UserClient platformv1connect.UserServiceClient
	TeamClient platformv1connect.TeamServiceClient
}

func NewHandler(uc platformv1connect.UserServiceClient, tc platformv1connect.TeamServiceClient) *Handler {
	return &Handler{UserClient: uc, TeamClient: tc}
}

// 2. The Auth Middleware
func (h *Handler) AuthMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		/* TODO: Production logic goes here
		   cookie, err := r.Cookie("auth_token")
		   if err != nil {
		       http.Redirect(w, r, "/login", http.StatusFound)
		       return
		   }
		   // Validate JWT/Cookie and extract name...
		*/

		// For now, mock reading the JWT cookie on init load
		userName := "K-Henry"

		// Inject the user name into the request context
		ctx := context.WithValue(r.Context(), userContextKey, userName)

		// Pass the request down the chain with the new context attached
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func (h *Handler) Routes() chi.Router {
	r := chi.NewRouter()

	fs := http.FileServer(http.Dir("internal/web/ui/static"))
	r.Handle("/static/*", http.StripPrefix("/static/", fs))

	r.Group(func(r chi.Router) {
		r.Use(h.AuthMiddleware)

		// Splash
		r.Get("/", func(w http.ResponseWriter, r *http.Request) {
			userName := r.Context().Value(userContextKey).(string)
			pages.Splash("INITIALIZING...", userName).Render(r.Context(), w)
		})

		// Dashboard Page
		r.Get("/dashboard", func(w http.ResponseWriter, r *http.Request) {
			userName := r.Context().Value(userContextKey).(string)

			// If HTMX is hot-swapping, only send the partial
			if r.Header.Get("HX-Request") == "true" {
				// Tell HTMX to update the browser tab!
				w.Header().Set("HX-Title", "Project Platform | Dashboard")

				pages.DashboardContent().Render(r.Context(), w)
				return
			}

			// If init load, send the whole page
			pages.DashboardPage(userName).Render(r.Context(), w)
		})

		// Settings Page
		r.Get("/settings", func(w http.ResponseWriter, r *http.Request) {
			userName := r.Context().Value(userContextKey).(string)

			if r.Header.Get("HX-Request") == "true" {
				// Tell HTMX to update the browser tab!
				w.Header().Set("HX-Title", "Project Platform | Settings")

				pages.SettingsContent().Render(r.Context(), w)
				return
			}
			pages.SettingsPage(userName).Render(r.Context(), w)
		})

		// Healthz HTMX Target
		r.Get("/healthz", func(w http.ResponseWriter, r *http.Request) {
			readyHTML := `
						<div id="status-container" class="transition-opacity duration-700">
							<p class="text-xs font-mono text-green-600 dark:text-green-400 tracking-widest uppercase mb-12">
								SYSTEMS_READY
							</p>


							<button hx-get="/dashboard" hx-target="#main-content" hx-push-url="true" class="px-8 py-3 border border-zinc-300 dark:border-zinc-800 text-zinc-600 dark:text-zinc-400 text-xs font-mono tracking-widest hover:bg-zinc-200 dark:hover:bg-zinc-900 hover:text-black dark:hover:text-white transition-colors duration-300 cursor-pointer">
								ENTER_WORKSPACE
							</button>
						</div>
					`
			w.Write([]byte(readyHTML))
		})
	})

	return r
}
