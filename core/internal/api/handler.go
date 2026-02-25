package api

import (
	"github.com/kendricklawton/project-platform/core/internal/db"
	"github.com/kendricklawton/project-platform/core/internal/k8s"
	"github.com/kendricklawton/project-platform/gen/go/platform/v1/platformv1connect"
)

// Services acts as a dependency injection container for all Connect RPC handlers.
// Add new services here as your platform grows.
type Services struct {
	Team platformv1connect.TeamServiceHandler
	User platformv1connect.UserServiceHandler
	// Project platformv1connect.ProjectServiceHandler
	// Billing platformv1connect.BillingServiceHandler
}

type Handler struct {
	K8s            *k8s.Client
	Store          db.Store
	WorkOSAPIKey   string
	WorkOSClientID string
	Services       Services
}

func NewHandler(k8s *k8s.Client, store db.Store, workosAPIKey, workosClientID string, svcs Services) *Handler {
	return &Handler{
		K8s:            k8s,
		Store:          store,
		WorkOSAPIKey:   workosAPIKey,
		WorkOSClientID: workosClientID,
		Services:       svcs,
	}
}
