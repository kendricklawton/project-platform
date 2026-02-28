package api

import (
	"github.com/kendricklawton/project-platform/core/internal/db"
	"github.com/kendricklawton/project-platform/core/internal/k8s"
	"github.com/kendricklawton/project-platform/core/internal/service"
)

// Services holds pointers to your actual Business Logic (The internal services).
type Services struct {
	Team *service.TeamServer
	User *service.UserServer
	Auth *service.AuthService
}

// Handler is the core API layer.
type Handler struct {
	K8s            *k8s.Client
	Store          db.Store
	WorkOSAPIKey   string
	WorkOSClientID string
	Services       Services
}

// NewHandler creates a new API Handler with all injected dependencies.
func NewHandler(k8s *k8s.Client, store db.Store, workosAPIKey, workosClientID string, svcs Services) *Handler {
	return &Handler{
		K8s:            k8s,
		Store:          store,
		WorkOSAPIKey:   workosAPIKey,
		WorkOSClientID: workosClientID,
		Services:       svcs,
	}
}
