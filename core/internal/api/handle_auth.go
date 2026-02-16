package api

import (
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"os"

	"github.com/google/uuid"
	"github.com/kendricklawton/project-platform/core/internal/db"
	"github.com/workos/workos-go/v6/pkg/sso"
)

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
	authURL, _ := sso.GetAuthorizationURL(sso.GetAuthorizationURLOpts{
		RedirectURI: os.Getenv("WORKOS_REDIRECT_URI"),
		Provider:    "authkit",
		State:       state,
	})

	http.Redirect(w, r, authURL.String(), http.StatusFound)
}

func (h *Handler) AuthCallback(w http.ResponseWriter, r *http.Request) {
	code := r.URL.Query().Get("code")
	returnedState := r.URL.Query().Get("state")

	stateCookie, _ := r.Cookie("cli_state")
	if stateCookie == nil || returnedState != stateCookie.Value {
		http.Error(w, "Invalid state", http.StatusUnauthorized)
		return
	}

	sso.Configure(h.WorkOSAPIKey, h.WorkOSClientID)
	profileAndToken, err := sso.GetProfileAndToken(r.Context(), sso.GetProfileAndTokenOpts{Code: code})
	if err != nil {
		http.Error(w, "Exchange failed", http.StatusInternalServerError)
		return
	}

	profile := profileAndToken.Profile
	user, err := h.Store.GetUserByEmail(r.Context(), profile.Email)
	if err == sql.ErrNoRows {
		id, _ := uuid.NewV7()
		user, _ = h.Store.CreateUser(r.Context(), db.CreateUserParams{
			ID:    id,
			Email: profile.Email,
			Name:  fmt.Sprintf("%s %s", profile.FirstName, profile.LastName),
			Tier:  "free",
		})
		log.Printf("New User: %s", user.Email)
	}

	redirectCookie, _ := r.Cookie("cli_redirect_uri")
	http.Redirect(w, r, fmt.Sprintf("%s?token=%s&state=%s", redirectCookie.Value, profileAndToken.AccessToken, returnedState), http.StatusFound)
}
