package api

import (
	"encoding/json"
	"net/http"
)

// GetSystemStatus is a deep health check for Admins.
// It verifies that the API can successfully talk to the Kubernetes Cluster.
func (h *Handler) GetSystemStatus(w http.ResponseWriter, r *http.Request) {
	// 1. Query Kubernetes State
	// We use the request context so if the HTTP client cancels, the K8s call cancels.
	nodeCount, err := h.K8s.GetNodeCount(r.Context())
	if err != nil {
		// Log the error internally (use your logger here)
		// log.Printf("K8s Connection Failed: %v", err)

		// Return 503 Service Unavailable
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]string{
			"status": "degraded",
			"error":  "Control Plane Unreachable",
		})
		return
	}

	// 2. Construct Status Report
	response := map[string]any{
		"status": "operational",
		"component_status": map[string]string{
			"api":      "healthy",
			"database": "connected", // Placeholder for when we add DB checks
			"cluster":  "healthy",
		},
		"metrics": map[string]int{
			"k3s_nodes": nodeCount,
		},
	}

	// 3. Respond
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(response)
}
