package web

import (
	"context"
	"fmt"
	"net/http"
	"time"
)

const (
	// SessionCookieName is the centralized key used for setting and retrieving the auth cookie.
	SessionCookieName = "platform_session"
)

// sessionKey is used to pass the token down to the ConnectRPC clients
type sessionKey string

const tokenKey sessionKey = "auth_token"

// GetTokenFromContext safely extracts the auth token from the request context.
func GetTokenFromContext(ctx context.Context) (string, bool) {
	token, ok := ctx.Value(tokenKey).(string)
	return token, ok
}

// RequireAuth is a middleware that protects dashboard routes.
// It checks for the session cookie and redirects to login if it's missing.
func (h *Handler) RequireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		cookie, err := r.Cookie(SessionCookieName)
		if err != nil || cookie.Value == "" {
			http.Redirect(w, r, "/auth/login", http.StatusFound)
			return
		}

		// Inject the token into the context so your ConnectRPC clients can use it
		ctx := context.WithValue(r.Context(), tokenKey, cookie.Value)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// AuthLogin redirects the browser to the Core API's central login flow.
func (h *Handler) AuthLogin(w http.ResponseWriter, r *http.Request) {
	state := "web-dashboard-auth-state" // In prod, generate a random string
	redirectURI := "http://localhost:3000/auth/callback"

	// Point the browser to the Core API
	apiLoginURL := fmt.Sprintf("%s/v1/auth/login?redirect_uri=%s&state=%s", h.APIURL, redirectURI, state)
	http.Redirect(w, r, apiLoginURL, http.StatusFound)
}

// AuthCallback catches the token returned by the Core API and sets the cookie.
func (h *Handler) AuthCallback(w http.ResponseWriter, r *http.Request) {
	token := r.URL.Query().Get("token")
	if token == "" {
		http.Error(w, "Authentication failed: No token provided", http.StatusBadRequest)
		return
	}

	// Create a secure, HTTP-only session cookie
	http.SetCookie(w, &http.Cookie{
		Name:     SessionCookieName,
		Value:    token,
		Path:     "/",
		HttpOnly: true,
		Secure:   false, // Set to true in production (HTTPS)
		SameSite: http.SameSiteLaxMode,
		Expires:  time.Now().Add(24 * 7 * time.Hour), // 1 week session
	})

	http.Redirect(w, r, "/dashboard", http.StatusFound)
}

// AuthLogout destroys the session cookie.
func (h *Handler) AuthLogout(w http.ResponseWriter, r *http.Request) {
	http.SetCookie(w, &http.Cookie{
		Name:     SessionCookieName,
		Value:    "",
		Path:     "/",
		HttpOnly: true,
		Expires:  time.Unix(0, 0), // Expire immediately
	})
	http.Redirect(w, r, "/", http.StatusFound)
}
