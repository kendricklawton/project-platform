-- USERS

-- name: CreateUser :one
INSERT INTO users (
    id, email, name, stripe_customer_id, tier
) VALUES (
    $1, $2, $3, $4, $5
)
RETURNING *;

-- name: GetUser :one
SELECT * FROM users
WHERE id = $1 LIMIT 1;

-- name: GetUserByEmail :one
SELECT * FROM users
WHERE email = $1 LIMIT 1;

-- PROJECTS & RBAC
-- name: CreateProject :one
INSERT INTO projects (
    id, name, region
) VALUES (
    $1, $2, $3
)
RETURNING *;

-- name: GetProject :one
SELECT * FROM projects
WHERE id = $1 LIMIT 1;

-- name: AddProjectMember :one
INSERT INTO project_members (
    id, project_id, user_id, role
) VALUES (
    $1, $2, $3, $4
)
RETURNING *;

-- name: ListUserProjects :many
-- Fetch all projects a user has access to, ordered by newest first using UUIDv7
SELECT p.*, pm.role
FROM projects p
JOIN project_members pm ON p.id = pm.project_id
WHERE pm.user_id = $1
ORDER BY p.id DESC;

-- name: CheckUserProjectAccess :one
-- Fast RBAC check to ensure a user is allowed to deploy to a project
SELECT role FROM project_members
WHERE project_id = $1 AND user_id = $2 LIMIT 1;

-- DEPLOYMENTS

-- name: CreateDeployment :one
INSERT INTO deployments (
    id, project_id, image, replicas, status, url
) VALUES (
    $1, $2, $3, $4, $5, $6
)
RETURNING *;

-- name: GetDeployment :one
SELECT * FROM deployments
WHERE id = $1 LIMIT 1;

-- name: ListRecentDeployments :many
-- Highly optimized: Uses the idx_deployments_project_id_id index to fetch recent deployments instantly
SELECT * FROM deployments
WHERE project_id = $1
ORDER BY id DESC
LIMIT $2;

-- name: UpdateDeploymentStatus :one
UPDATE deployments
SET status = $2, updated_at = NOW()
WHERE id = $1
RETURNING *;

-- name: GetNextQueuedDeployment :one
-- Used by the background worker to grab the next job
SELECT * FROM deployments
WHERE status = 'queued'
ORDER BY id ASC
LIMIT 1;

-- USAGE (BILLING)

-- name: IncrementProjectUsage :one
-- "Upsert" logic: If the month record exists, add to it. If not, create it.
INSERT INTO project_usage (
    id, project_id, billing_period, compute_seconds, bandwidth_bytes
) VALUES (
    $1, $2, $3, $4, $5
)
ON CONFLICT (project_id, billing_period)
DO UPDATE SET
    compute_seconds = project_usage.compute_seconds + EXCLUDED.compute_seconds,
    bandwidth_bytes = project_usage.bandwidth_bytes + EXCLUDED.bandwidth_bytes,
    updated_at = NOW()
RETURNING *;

-- name: GetProjectUsage :one
SELECT * FROM project_usage
WHERE project_id = $1 AND billing_period = $2 LIMIT 1;
