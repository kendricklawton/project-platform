package api

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/google/uuid"
	"github.com/kendricklawton/project-platform/core/pkg/sdk"
)

// CreateProject reserves a name and creates the database record.
func (h *Handler) CreateProject(w http.ResponseWriter, r *http.Request) {
	var req sdk.CreateProjectRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}
	if req.Name == "" {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		json.NewEncoder(w).Encode(sdk.ErrorResponse{Error: "project name is required"})
		return
	}

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
