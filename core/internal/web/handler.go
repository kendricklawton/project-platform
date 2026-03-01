package web

import (
	"net/http"

	"github.com/kendricklawton/project-platform/core/internal/web/ui/components"
	"github.com/kendricklawton/project-platform/core/internal/web/ui/pages"
	"github.com/kendricklawton/project-platform/gen/go/platform/v1/platformv1connect"
)

// Handler acts as the Backend-For-Frontend (BFF) controller.
type Handler struct {
	APIURL     string
	UserClient platformv1connect.UserServiceClient
	TeamClient platformv1connect.TeamServiceClient
}

// NewHandler creates a new Web Handler with the required API clients.
func NewHandler(apiURL string, userClient platformv1connect.UserServiceClient, teamClient platformv1connect.TeamServiceClient) *Handler {
	return &Handler{
		APIURL:     apiURL,
		UserClient: userClient,
		TeamClient: teamClient,
	}
}

// isMainContentSwap checks if the request is an HTMX request explicitly targeting the main content area.
func (h *Handler) isMainContentSwap(r *http.Request) bool {
	isHTMX := r.Header.Get("HX-Request") == "true"
	isMainContentTarget := r.Header.Get("HX-Target") == "main-content"
	return isHTMX && isMainContentTarget
}

// Splash renders the initial boot screen.
func (h *Handler) Splash(w http.ResponseWriter, r *http.Request) {
	initialStatus := "INITIALIZING PLATFORM..."
	userName := ""

	cookie, err := r.Cookie(SessionCookieName)
	if err == nil && cookie.Value != "" {
		userName = "AUTH_ACTIVE"
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")

	// Use our helper to check for HTMX partial swaps
	if h.isMainContentSwap(r) {
		component := pages.SplashContent(initialStatus)
		if err := component.Render(r.Context(), w); err != nil {
			http.Error(w, "Failed to render splash content", http.StatusInternalServerError)
		}
		return
	}

	// Standard full page load
	component := pages.SplashPage(initialStatus, userName)
	if err := component.Render(r.Context(), w); err != nil {
		http.Error(w, "Failed to render splash page", http.StatusInternalServerError)
	}
}

// Healthz handles the connection status check and returns the appropriate action button.
func (h *Handler) Healthz(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")

	_, err := r.Cookie(SessionCookieName)
	isLoggedIn := err == nil

	actionURL := "/auth/login"
	buttonText := "INITIALIZE LOGIN SEQUENCE"

	if isLoggedIn {
		actionURL = "/dashboard"
		buttonText = "ENTER SECURE CONSOLE"
	}

	// Render the pure Templ component instead of a raw HTML string
	component := components.HealthzStatus(actionURL, buttonText)
	if err := component.Render(r.Context(), w); err != nil {
		http.Error(w, "Failed to render health status", http.StatusInternalServerError)
	}
}

// Dashboard renders the protected dashboard area.
func (h *Handler) Dashboard(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")

	// Extract the token using our new helper (injected by RequireAuth middleware)
	_, ok := GetTokenFromContext(r.Context())
	if !ok {
		// Fallback if something went terribly wrong with middleware
		http.Redirect(w, r, "/auth/login", http.StatusFound)
		return
	}

	// TODO: Use the token to fetch actual user details from h.UserClient
	userName := "AUTH_ACTIVE"

	if h.isMainContentSwap(r) {
		component := pages.DashboardContent()
		if err := component.Render(r.Context(), w); err != nil {
			http.Error(w, "Failed to render dashboard content", http.StatusInternalServerError)
		}
		return
	}

	component := pages.DashboardPage(userName)
	if err := component.Render(r.Context(), w); err != nil {
		http.Error(w, "Failed to render dashboard page", http.StatusInternalServerError)
	}
}
