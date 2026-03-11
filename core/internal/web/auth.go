package web

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"

	"github.com/kendricklawton/project-platform/core/internal/web/ui/pages"
)

const (
	// SessionCookieName holds the authenticated user's UUID.
	// HttpOnly — never exposed to JavaScript.
	SessionCookieName = "platform_session"

	// nameCookieName holds the user's display name for server-side rendering.
	// HttpOnly — read by Go on each request, not by JS.
	nameCookieName = "platform_name"

	// slugCookieName holds the user's workspace slug (e.g. "acme-corp-workspace").
	// Used to build slug-scoped URLs like /{slug}/services.
	slugCookieName = "platform_slug"

	// emailCookieName holds the user's email address for server-side rendering.
	// Used by AccountDelete to validate the confirmation input.
	// HttpOnly — read by Go only, not exposed to JavaScript.
	emailCookieName = "platform_email"

	// stateCookieName is a reserved CSRF cookie name (unused in password auth, kept for future use).
	stateCookieName = "auth_state"
)

// sessionKey is the context key used to pass the user UUID through middleware.
type sessionKey string

const tokenKey sessionKey = "auth_token"

// GetTokenFromContext safely extracts the user UUID from the request context.
// It is set by RequireAuth after validating the session cookie.
func GetTokenFromContext(ctx context.Context) (string, bool) {
	token, ok := ctx.Value(tokenKey).(string)
	return token, ok
}

// GetDisplayName reads the stored display name cookie for server-side rendering.
// Returns an empty string if the user is not authenticated.
func GetDisplayName(r *http.Request) string {
	cookie, err := r.Cookie(nameCookieName)
	if err != nil || cookie.Value == "" {
		return ""
	}
	return cookie.Value
}

// GetSlug reads the workspace slug cookie for slug-scoped URL routing.
// Returns an empty string if the user is not authenticated.
func GetSlug(r *http.Request) string {
	cookie, err := r.Cookie(slugCookieName)
	if err != nil || cookie.Value == "" {
		return ""
	}
	return cookie.Value
}

// GetEmail reads the stored email cookie for account confirmation flows.
// Returns an empty string if the user is not authenticated.
func GetEmail(r *http.Request) string {
	cookie, err := r.Cookie(emailCookieName)
	if err != nil || cookie.Value == "" {
		return ""
	}
	return cookie.Value
}

// RequireAuth protects routes by checking for a valid session cookie.
//
// HTMX challenge: a plain 302 redirect causes HTMX to load the login page
// HTML fragment into #main-content instead of navigating the full page.
// Fix: detect HX-Request header and respond with HX-Redirect instead,
// which instructs HTMX to perform a full browser navigation.
func (h *Handler) RequireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		cookie, err := r.Cookie(SessionCookieName)
		if err != nil || cookie.Value == "" {
			if r.Header.Get("HX-Request") == "true" {
				w.Header().Set("HX-Redirect", "/auth/login")
				w.WriteHeader(http.StatusOK)
				return
			}
			http.Redirect(w, r, "/auth/login", http.StatusFound)
			return
		}
		ctx := context.WithValue(r.Context(), tokenKey, cookie.Value)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// AuthLogin handles GET /auth/login (render form) and POST /auth/login (verify credentials).
func (h *Handler) AuthLogin(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")

	if r.Method == http.MethodGet {
		pages.LoginPage("").Render(r.Context(), w)
		return
	}

	// POST — verify credentials
	email := strings.TrimSpace(r.FormValue("email"))
	password := r.FormValue("password")

	if email == "" || password == "" {
		pages.LoginPage("Email and password are required.").Render(r.Context(), w)
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(h.AdminPasswordHash), []byte(password)); err != nil {
		pages.LoginPage("Invalid credentials.").Render(r.Context(), w)
		return
	}

	// Derive display name from email (e.g. "john.doe@example.com" → "John Doe")
	firstName, lastName := nameFromEmail(email)

	userID, userName, workspaceSlug, err := h.provisionUserViaAPI(r.Context(), email, firstName, lastName)
	if err != nil {
		log.Printf("provisionUserViaAPI error: %v", err)
		pages.LoginPage("Failed to initialize session. Try again.").Render(r.Context(), w)
		return
	}

	exp := time.Now().Add(7 * 24 * time.Hour)

	http.SetCookie(w, &http.Cookie{
		Name:     SessionCookieName,
		Value:    userID,
		Path:     "/",
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
		Expires:  exp,
	})
	http.SetCookie(w, &http.Cookie{
		Name:     nameCookieName,
		Value:    userName,
		Path:     "/",
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
		Expires:  exp,
	})
	http.SetCookie(w, &http.Cookie{
		Name:     emailCookieName,
		Value:    email,
		Path:     "/",
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
		Expires:  exp,
	})
	http.SetCookie(w, &http.Cookie{
		Name:     slugCookieName,
		Value:    workspaceSlug,
		Path:     "/",
		HttpOnly: true,
		SameSite: http.SameSiteLaxMode,
		Expires:  exp,
	})

	if workspaceSlug == "" {
		http.Redirect(w, r, "/dashboard", http.StatusFound)
		return
	}
	http.Redirect(w, r, "/"+workspaceSlug, http.StatusFound)
}

// AuthLogout clears all session cookies and redirects home.
func (h *Handler) AuthLogout(w http.ResponseWriter, r *http.Request) {
	past := time.Unix(0, 0)
	for _, name := range []string{SessionCookieName, nameCookieName, emailCookieName, slugCookieName, stateCookieName} {
		http.SetCookie(w, &http.Cookie{
			Name:     name,
			Value:    "",
			Path:     "/",
			HttpOnly: true,
			SameSite: http.SameSiteLaxMode,
			MaxAge:   -1,
			Expires:  past,
		})
	}
	http.Redirect(w, r, h.BaseURL, http.StatusSeeOther)
}

// nameFromEmail derives a first and last name from an email address.
// "john.doe@example.com" → "John", "Doe"
// "johndoe@example.com"  → "Johndoe", ""
func nameFromEmail(email string) (firstName, lastName string) {
	local := email
	if idx := strings.Index(email, "@"); idx > 0 {
		local = email[:idx]
	}
	parts := strings.SplitN(local, ".", 2)
	firstName = capitalize(parts[0])
	if len(parts) == 2 {
		lastName = capitalize(parts[1])
	}
	return
}

func capitalize(s string) string {
	if s == "" {
		return ""
	}
	return strings.ToUpper(s[:1]) + s[1:]
}

// provisionUserViaAPI calls POST /v1/auth/provision on the Core API.
// Returns the user's ID, display name, and primary workspace slug.
func (h *Handler) provisionUserViaAPI(ctx context.Context, email, firstName, lastName string) (userID, userName, slug string, err error) {
	body, marshalErr := json.Marshal(map[string]string{
		"email":      email,
		"first_name": firstName,
		"last_name":  lastName,
	})
	if marshalErr != nil {
		err = fmt.Errorf("marshal provision request: %w", marshalErr)
		return
	}

	req, reqErr := http.NewRequestWithContext(ctx, http.MethodPost, h.APIURL+"/v1/auth/provision", bytes.NewReader(body))
	if reqErr != nil {
		err = fmt.Errorf("create provision request: %w", reqErr)
		return
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Internal-Secret", h.InternalSecret)

	resp, doErr := http.DefaultClient.Do(req)
	if doErr != nil {
		err = fmt.Errorf("provision request failed: %w", doErr)
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		err = fmt.Errorf("provision returned %d", resp.StatusCode)
		return
	}

	var result struct {
		ID    string `json:"id"`
		Name  string `json:"name"`
		Email string `json:"email"`
		Slug  string `json:"slug"`
	}
	if decErr := json.NewDecoder(resp.Body).Decode(&result); decErr != nil {
		err = fmt.Errorf("decode provision response: %w", decErr)
		return
	}

	userID = result.ID
	userName = result.Name
	slug = result.Slug
	return
}

// deleteAccountViaAPI calls DELETE /v1/auth/account on the Core API.
func (h *Handler) deleteAccountViaAPI(ctx context.Context, userID string) error {
	body, err := json.Marshal(map[string]string{"user_id": userID})
	if err != nil {
		return fmt.Errorf("marshal delete request: %w", err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodDelete, h.APIURL+"/v1/auth/account", bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("create delete request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Internal-Secret", h.InternalSecret)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("delete request failed: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent {
		return fmt.Errorf("delete account returned %d", resp.StatusCode)
	}
	return nil
}
