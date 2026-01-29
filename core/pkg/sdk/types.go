package sdk

import "time"

// --- Project (The "Space") ---

type CreateProjectRequest struct {
	Name   string `json:"name"`   // e.g. "my-blog"
	Region string `json:"region"` // e.g. "us-east"
}

type CreateProjectResponse struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Region    string    `json:"region"`
	CreatedAt time.Time `json:"created_at"`
}

// --- Deployment (The "Action") ---

type CreateDeploymentRequest struct {
	ProjectID string `json:"project_id"` // Link to the parent space
	Image     string `json:"image"`      // The artifact (e.g. "nginx:alpine")
	Replicas  int    `json:"replicas"`
}

type CreateDeploymentResponse struct {
	DeploymentID string `json:"deployment_id"`
	Status       string `json:"status"` // "queued", "building"
	URL          string `json:"url"`    // "my-blog-git-sha.platform.com"
}

type ErrorResponse struct {
	Error string `json:"error"`
}
