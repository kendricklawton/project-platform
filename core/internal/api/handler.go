package api

import (
	"github.com/kendricklawton/project-platform/core/internal/k8s"
)

// Handler holds the dependencies shared by ALL endpoints.
type Handler struct {
	K8s *k8s.Client
	// DB *database.Client (You will add this later)
}

func NewHandler(k8s *k8s.Client) *Handler {
	return &Handler{
		K8s: k8s,
	}
}
