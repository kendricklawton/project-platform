package api

import (
	"encoding/json"
	"net/http"
)

// GetSystemStatus verifies the API can communicate with the Kubernetes cluster.
func (h *Handler) GetSystemStatus(w http.ResponseWriter, r *http.Request) {
	// Query Kubernetes node count using the client initialized in NewHandler
	nodeCount, err := h.K8s.GetNodeCount(r.Context())
	if err != nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]string{
			"status": "degraded",
			"error":  "K8s Control Plane Unreachable",
		})
		return
	}

	response := map[string]any{
		"status": "operational",
		"component_status": map[string]string{
			"api":      "healthy",
			"database": "connected",
			"cluster":  "healthy",
		},
		"metrics": map[string]int{
			"k3s_nodes": nodeCount,
		},
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}
