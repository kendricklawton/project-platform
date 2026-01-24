package handler

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"log"
	"log/slog"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/kendricklawton/project-dupes/backend/internal/api"
	"github.com/kendricklawton/project-dupes/backend/internal/config"
	"github.com/kendricklawton/project-dupes/backend/internal/store"
	"github.com/workos/workos-go/v6/pkg/usermanagement"
)

type AuthHandler struct {
	cfg         *config.Config
	log         *slog.Logger
	memoryStore store.MemoryStore
}

func NewAuthHandler(cfg *config.Config, log *slog.Logger, s store.MemoryStore) *AuthHandler {
	return &AuthHandler{cfg: cfg, log: log, memoryStore: s}
}

// GetLoginUrl initiates the flow.
// GET /auth/login?platform=mobile|web
func (h *AuthHandler) Login(c *gin.Context) {
	platform := c.Query("platform")
	if platform != "mobile" && platform != "web" {
		c.JSON(http.StatusBadRequest, api.ErrorResponse{Error: "platform must be 'mobile' or 'web'"})
		return
	}

	url, err := h.cfg.WorkOSClient.GetAuthorizationURL(usermanagement.GetAuthorizationURLOpts{
		ClientID:    h.cfg.ClientID,
		RedirectURI: h.cfg.RedirectURI,
		Provider:    "authkit",
		State:       platform,
	})

	if err != nil {
		h.log.Error("workos url generation failed", "error", err)
		c.JSON(http.StatusInternalServerError, api.ErrorResponse{Error: "internal server error"})
		return
	}

	c.JSON(http.StatusOK, api.LoginResponse{Url: url.String()})
}

// HandleCallback receives the code from WorkOS.
// GET /auth/callback
func (h *AuthHandler) Callback(c *gin.Context) {
	// Parse Query Parameters
	code := c.Query("code")
	errMsg := c.Query("error")
	state := c.Query("state") // used for 'platform'

	if errMsg != "" {
		h.log.Warn("callback error received", "error", errMsg)
		c.JSON(http.StatusBadRequest, api.ErrorResponse{Error: errMsg})
		return
	}

	if code == "" {
		c.JSON(http.StatusBadRequest, api.ErrorResponse{Error: "missing code parameter"})
		return
	}

	authRes, err := h.cfg.WorkOSClient.AuthenticateWithCode(c.Request.Context(), usermanagement.AuthenticateWithCodeOpts{
		ClientID: h.cfg.ClientID,
		Code:     code,
	})

	if err != nil {
		h.log.Error("workos authentication failed", "error", err)
		c.JSON(http.StatusUnauthorized, api.ErrorResponse{Error: "authentication failed"})
		return
	}

	// Generate a short-lived handoff code
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		h.log.Error("crypto rand failed", "error", err)
		c.JSON(http.StatusInternalServerError, api.ErrorResponse{Error: "internal server error"})
		return
	}
	handoffCode := hex.EncodeToString(b)

	if err := h.memoryStore.Save(c.Request.Context(), handoffCode, authRes); err != nil {
		h.log.Error("store save failed", "error", err)
		c.JSON(http.StatusInternalServerError, api.ErrorResponse{Error: "internal server error"})
		return
	}

	// Routing logic: Where does the user go next?
	redirectTarget := fmt.Sprintf("project-dupes://login-callback?handoff_code=%s", handoffCode)

	// If state was 'web', redirect to localhost:3000
	if state == "web" {
		redirectTarget = fmt.Sprintf("http://localhost:3000/auth/callback?code=%s", handoffCode)
	}

	c.Redirect(http.StatusFound, redirectTarget)
}

// ExchangeHandoff claims the session.
// POST /auth/exchange
func (h *AuthHandler) Exchange(c *gin.Context) {
	var req api.ExchangeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, api.ErrorResponse{Error: "invalid request body"})
		return
	}

	authRes, err := h.memoryStore.Get(c.Request.Context(), req.HandoffCode)
	if err != nil {
		h.log.Warn("invalid handoff attempt", "code", req.HandoffCode)
		c.JSON(http.StatusUnauthorized, api.ErrorResponse{Error: "invalid or expired code"})
		return
	}

	log.Printf("ExchangeHandoff: %v", authRes)
	log.Printf("ExchangeHandoff: %v", authRes.User.ID)

	// Burn the code after use
	_ = h.memoryStore.Delete(c.Request.Context(), req.HandoffCode)

	log.Printf("Confirm deletion %v", authRes.User.ID)

	// We use the WorkOS User ID as the session identifier
	sid := authRes.User.ID

	c.JSON(http.StatusOK, api.ExchangeResponse{
		AccessToken:  authRes.AccessToken,
		RefreshToken: &authRes.RefreshToken,
		Email:        authRes.User.Email,
		SessionId:    &sid,
	})
}

// Logout initiates logout.
// GET /auth/logout?session_id=...
// func (h *AuthHandler) Logout(c *gin.Context) {
// 	sessionId := c.Query("session_id")
// 	if sessionId == "" {
// 		c.JSON(http.StatusBadRequest, api.ErrorResponse{
// 			Error: "Missing session_id",
// 		})
// 		return
// 	}

// 	// 1. Tell WorkOS where to send the user after logout
// 	returnTo := "project-dupes://logout-callback"

// 	url, err := h.cfg.WorkOSClient.GetLogoutURL(usermanagement.GetLogoutURLOpts{
// 		SessionID: sessionId,
// 		ReturnTo:  returnTo,
// 	})

// 	if err != nil {
// 		h.log.Error("failed_to_generate_logout_url", slog.Any("error", err))
// 		c.JSON(http.StatusInternalServerError, api.ErrorResponse{
// 			Error: "Failed to generate logout URL",
// 		})
// 		return
// 	}

// 	// 2. Return URL as JSON
// 	c.JSON(http.StatusOK, api.LoginResponse{
// 		Url: url.String(),
// 	})
// }
