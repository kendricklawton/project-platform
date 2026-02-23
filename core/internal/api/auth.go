package api

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"os"
	"regexp"
	"strings"

	"github.com/google/uuid"
	"github.com/kendricklawton/project-platform/core/internal/db"
	"github.com/workos/workos-go/v6/pkg/sso"
)

type contextKey string

const userIDKey contextKey = "user_id"

func GetUserID(ctx context.Context) (uuid.UUID, bool) {
	id, ok := ctx.Value(userIDKey).(uuid.UUID)
	return id, ok
}

// RequireAuth is a middleware that validates authentication and injects the UserID into the context.
func (h *Handler) RequireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Example: Get token from header (usually "Authorization: <uuid>")
		authHeader := r.Header.Get("Authorization")
		if authHeader == "" {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		userID, err := uuid.Parse(authHeader)
		if err != nil {
			http.Error(w, "Invalid token", http.StatusUnauthorized)
			return
		}

		ctx := context.WithValue(r.Context(), userIDKey, userID)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// AuthLogin initiates the WorkOS OAuth flow.
func (h *Handler) AuthLogin(w http.ResponseWriter, r *http.Request) {
	cliRedirectURI := r.URL.Query().Get("redirect_uri")
	state := r.URL.Query().Get("state")

	if cliRedirectURI == "" || state == "" {
		http.Error(w, "Login must be initiated from the CLI.", http.StatusBadRequest)
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

// AuthCallback handles the return from WorkOS and provisions the User/Team atomically.
func (h *Handler) AuthCallback(w http.ResponseWriter, r *http.Request) {
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
	fullName := fmt.Sprintf("%s %s", profile.FirstName, profile.LastName)

	// Check if user already exists
	user, err := h.Store.GetUserByEmail(r.Context(), profile.Email)

	if err == sql.ErrNoRows {
		// --- ATOMIC ONBOARDING TRANSACTION ---
		userID, _ := uuid.NewV7()
		teamID, _ := uuid.NewV7()
		baseSlug := generateSlug(fullName)

		err = h.Store.ExecTx(r.Context(), func(q *db.Queries) error {
			var txErr error
			user, txErr = q.CreateUser(r.Context(), db.CreateUserParams{
				ID:    userID,
				Email: profile.Email,
				Name:  fullName,
			})
			if txErr != nil {
				return txErr
			}

			_, txErr = q.CreateTeam(r.Context(), db.CreateTeamParams{
				ID:   teamID,
				Name: fmt.Sprintf("%s's Team", profile.FirstName),
				Slug: fmt.Sprintf("%s-team", baseSlug),
			})
			if txErr != nil {
				return txErr
			}

			// C. Assign Owner
			return q.AddTeamMember(r.Context(), db.AddTeamMemberParams{
				TeamID: teamID,
				UserID: user.ID,
				Role:   "owner",
			})
		})

		if err != nil {
			log.Printf("Failed to onboard user: %v", err)
			http.Error(w, "Failed to provision account", http.StatusInternalServerError)
			return
		}
		log.Printf("🚀 Onboarded new developer: %s", user.Email)
	} else if err != nil {
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}

	redirectCookie, err := r.Cookie("cli_redirect_uri")
	if err != nil || redirectCookie == nil {
		http.Error(w, "Missing redirect URI", http.StatusBadRequest)
		return
	}

	redirectURL := fmt.Sprintf("%s?token=%s&state=%s", redirectCookie.Value, user.ID.String(), returnedState)
	http.Redirect(w, r, redirectURL, http.StatusFound)
}

func generateSlug(name string) string {
	lower := strings.ToLower(name)
	reg := regexp.MustCompile("[^a-z0-9]+")
	slug := reg.ReplaceAllString(lower, "-")
	return strings.Trim(slug, "-")
}
