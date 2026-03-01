package api

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/kendricklawton/project-platform/core/internal/service"
	"github.com/workos/workos-go/v6/pkg/sso"
)

type contextKey string

const userIDKey contextKey = "user_id"

// RequireAuth validates authentication and injects the UserID into the context.
func (h *handler) requireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization")
		if authHeader == "" {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		userID, err := uuid.Parse(authHeader)
		if err != nil {
			http.Error(w, "Invalid token format", http.StatusUnauthorized)
			return
		}

		// Inject the authenticated UUID into the request context
		ctx := context.WithValue(r.Context(), userIDKey, userID)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// AuthLogin initiates the WorkOS OAuth flow.
func (h *handler) authLogin(w http.ResponseWriter, r *http.Request) {
	cliRedirectURI := r.URL.Query().Get("redirect_uri")
	state := r.URL.Query().Get("state")

	if cliRedirectURI == "" || state == "" {
		http.Error(w, "Login must provide redirect_uri and state parameters.", http.StatusBadRequest)
		return
	}

	http.SetCookie(w, &http.Cookie{Name: "cli_state", Value: state, Path: "/", HttpOnly: true, MaxAge: 300})
	http.SetCookie(w, &http.Cookie{Name: "cli_redirect_uri", Value: cliRedirectURI, Path: "/", HttpOnly: true, MaxAge: 300})

	sso.Configure(h.WorkOSAPIKey, h.WorkOSClientID)

	authURL, err := sso.GetAuthorizationURL(sso.GetAuthorizationURLOpts{
		RedirectURI: os.Getenv("WORKOS_REDIRECT_URI"),
		Provider:    "authkit",
		State:       state,
	})
	if err != nil {
		http.Error(w, "Failed to generate auth URL", http.StatusInternalServerError)
		return
	}

	http.Redirect(w, r, authURL.String(), http.StatusFound)
}

// AuthCallback handles the return from WorkOS and provisions the User/Team.
func (h *handler) authCallback(w http.ResponseWriter, r *http.Request) {
	code := r.URL.Query().Get("code")
	returnedState := r.URL.Query().Get("state")

	stateCookie, err := r.Cookie("cli_state")
	if err != nil || stateCookie == nil || returnedState != stateCookie.Value {
		http.Error(w, "Invalid state", http.StatusUnauthorized)
		return
	}

	sso.Configure(h.WorkOSAPIKey, h.WorkOSClientID)
	profileAndToken, err := sso.GetProfileAndToken(r.Context(), sso.GetProfileAndTokenOpts{Code: code})
	if err != nil {
		http.Error(w, "WorkOS exchange failed", http.StatusInternalServerError)
		return
	}

	profile := profileAndToken.Profile

	// Use the DI-injected AuthService!
	user, err := h.Services.Auth.ProvisionUser(r.Context(), service.UserProfile{
		Email:     profile.Email,
		FirstName: profile.FirstName,
		LastName:  profile.LastName,
	})

	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		log.Printf("Failed to provision user: %v", err)
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}

	log.Printf("🚀 Successful Authentication: %s", user.Email)

	redirectCookie, err := r.Cookie("cli_redirect_uri")
	if err != nil || redirectCookie == nil {
		http.Error(w, "Missing redirect URI", http.StatusBadRequest)
		return
	}

	redirectURL := fmt.Sprintf("%s?token=%s&state=%s", redirectCookie.Value, user.ID.String(), returnedState)
	http.Redirect(w, r, redirectURL, http.StatusFound)
}
