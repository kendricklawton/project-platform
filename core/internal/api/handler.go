package api

import (
	"github.com/kendricklawton/project-platform/core/internal/db"
	"github.com/kendricklawton/project-platform/core/internal/k8s"
)

type Handler struct {
	K8s            *k8s.Client
	Store          *db.Store
	WorkOSAPIKey   string
	WorkOSClientID string
}

func NewHandler(k8s *k8s.Client, store *db.Store, workosAPIKey, workosClientID string) *Handler {
	return &Handler{
		K8s:            k8s,
		Store:          store,
		WorkOSAPIKey:   workosAPIKey,
		WorkOSClientID: workosClientID,
	}
}
