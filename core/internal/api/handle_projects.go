package api

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/kendricklawton/project-platform/core/pkg/sdk"
)

// -----------------------------------------------------------------------------
// PROJECT HANDLERS (The "Space")
// -----------------------------------------------------------------------------

// CreateProject reserves a name and creates the database record.
// It does NOT touch Kubernetes.
func (h *Handler) CreateProject(w http.ResponseWriter, r *http.Request) {
	// 1. Parse
	var req sdk.CreateProjectRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}

	// 2. Validate
	if req.Name == "" {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(sdk.ErrorResponse{Error: "project name is required"})
		return
	}

	// 3. Generate ID (UUID v7 for DB Performance)
	id, err := uuid.NewV7()
	if err != nil {
		http.Error(w, "system error", http.StatusInternalServerError)
		return
	}

	// 4. Logic: Insert into 'projects' table
	// err = h.DB.Exec("INSERT INTO projects (id, name, region) VALUES ...")

	resp := sdk.CreateProjectResponse{
		ID:        id.String(),
		Name:      req.Name,
		Region:    req.Region,
		CreatedAt: time.Now().UTC(),
	}

	// 5. Respond (201 Created)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(resp)
}

// -----------------------------------------------------------------------------
// DEPLOYMENT HANDLERS (The "Action")
// -----------------------------------------------------------------------------

// CreateDeployment triggers a new rollout for an existing project.
func (h *Handler) CreateDeployment(w http.ResponseWriter, r *http.Request) {
	// 1. Parse
	var req sdk.CreateDeploymentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}

	// 2. Validate
	if req.ProjectID == "" {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(sdk.ErrorResponse{Error: "project_id is required"})
		return
	}
	if req.Image == "" {
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(sdk.ErrorResponse{Error: "container image is required"})
		return
	}

	// 3. Logic: Verify Project Exists
	// project, err := h.DB.GetProject(req.ProjectID)
	// if err != nil { return 404 }

	// 4. Generate Deployment ID (UUID v7)
	deployID, err := uuid.NewV7()
	if err != nil {
		http.Error(w, "system error", http.StatusInternalServerError)
		return
	}

	// 5. Logic: Insert into 'deployments' table & Queue for K8s Worker
	// h.Queue.Push(DeployJob{ID: deployID, Image: req.Image})

	// 6. Generate Preview URL (Vercel Style)
	// e.g., project-name-deployment-id.platform.com
	previewURL := "https://" + req.ProjectID + "-" + deployID.String() + ".platform.com"

	resp := sdk.CreateDeploymentResponse{
		DeploymentID: deployID.String(),
		Status:       "queued",
		URL:          previewURL,
	}

	// 7. Respond (202 Accepted)
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusAccepted)
	json.NewEncoder(w).Encode(resp)
}
