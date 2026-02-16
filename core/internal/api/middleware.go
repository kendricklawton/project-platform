package api

import (
	"context"
	"net/http"
	"strings"
)

type contextKey string

const userTokenKey contextKey = "user_token"

// RequireAuth ensures a valid token is present in the request header.
func (h *Handler) RequireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization")
		if authHeader == "" {
			http.Error(w, "Unauthorized: Missing token", http.StatusUnauthorized)
			return
		}

		// Expected format: "Bearer <token>"
		token := strings.TrimPrefix(authHeader, "Bearer ")
		if token == "" {
			http.Error(w, "Unauthorized: Invalid token format", http.StatusUnauthorized)
			return
		}

		// TODO: Validate token against database or WorkOS
		// For now, we just pass the token into the context
		ctx := context.WithValue(r.Context(), userTokenKey, token)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// GetUserToken retrieves the token from the context.
func GetUserToken(ctx context.Context) string {
	token, ok := ctx.Value(userTokenKey).(string)
	if !ok {
		return ""
	}
	return token
}
