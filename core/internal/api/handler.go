package api

import (
	"github.com/kendricklawton/project-platform/core/internal/db"
	"github.com/kendricklawton/project-platform/core/internal/k8s"
)

type Handler struct {
	K8s   *k8s.Client
	Store *db.Store // Renamed from DB to Store
}

func NewHandler(k8s *k8s.Client, store *db.Store) *Handler {
	return &Handler{
		K8s:   k8s,
		Store: store,
	}
}
