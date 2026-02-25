-- name: GetUser :one
SELECT * FROM users WHERE id = $1 LIMIT 1;

-- name: GetUserByEmail :one
SELECT * FROM users WHERE email = $1 LIMIT 1;

-- name: OnboardUserWithTeam :one
WITH new_user AS (
    INSERT INTO users (id, email, name) VALUES ($1, $2, $3) RETURNING id
),
new_team AS (
    INSERT INTO teams (id, name, slug) VALUES ($4, $5, $6) RETURNING id
)
INSERT INTO team_members (team_id, user_id, role)
SELECT new_team.id, new_user.id, 'owner'
FROM new_user, new_team
RETURNING team_id;


-- --- PROJECT MANAGEMENT ---

-- name: CreateProject :one
-- Only 'owner' or 'member' can create projects
INSERT INTO projects (id, team_id, name, framework, repo_url)
SELECT $1, $2, $3, $4, $5
WHERE EXISTS (
    SELECT 1 FROM team_members
    WHERE team_id = $2 AND user_id = $6 AND role IN ('owner', 'member')
)
RETURNING *;

-- name: ListTeamProjects :many
SELECT p.* FROM projects p
JOIN team_members tm ON p.team_id = tm.team_id
WHERE p.team_id = $1 AND tm.user_id = $2
ORDER BY p.created_at DESC;


-- --- SECRETS MANAGEMENT ---

-- name: UpsertEnvVar :one
-- Upserts an environment variable (creates or updates). Only 'owner' or 'member' can modify secrets.
INSERT INTO project_env_vars (id, project_id, environment, key_name, encrypted_value, encrypted_data_key, encryption_iv, kms_key_id)
SELECT $1, $2, $3, $4, $5, $6, $7, $8
WHERE EXISTS (
    SELECT 1 FROM projects p
    JOIN team_members tm ON p.team_id = tm.team_id
    WHERE p.id = $2 AND tm.user_id = $9 AND tm.role IN ('owner', 'member')
)
ON CONFLICT (project_id, environment, key_name)
DO UPDATE SET
    encrypted_value = EXCLUDED.encrypted_value,
    encrypted_data_key = EXCLUDED.encrypted_data_key,
    encryption_iv = EXCLUDED.encryption_iv,
    kms_key_id = EXCLUDED.kms_key_id,
    updated_at = NOW()
RETURNING *;

-- name: GetEnvVarsForDeployment :many
-- Fetches the encrypted secrets. In a real PaaS, only the internal Build Worker calls this (bypassing user RBAC).
SELECT key_name, encrypted_value, encrypted_data_key, encryption_iv, kms_key_id
FROM project_env_vars
WHERE project_id = $1 AND environment = $2;


-- --- DEPLOYMENTS ---

-- name: CreateDeployment :one
-- Only 'owner' or 'member' can trigger deployments
INSERT INTO deployments (id, project_id, environment, branch, commit_sha, commit_message)
SELECT $1, $2, $3, $4, $5, $6
WHERE EXISTS (
    SELECT 1 FROM projects p
    JOIN team_members tm ON p.team_id = tm.team_id
    WHERE p.id = $2 AND tm.user_id = $7 AND tm.role IN ('owner', 'member')
)
RETURNING *;

-- name: UpdateDeploymentStatus :one
-- Usually called by your internal Build Worker (no user_id check needed here)
UPDATE deployments
SET status = $2, deployment_url = COALESCE($3, deployment_url), updated_at = NOW()
WHERE id = $1
RETURNING *;

-- name: ListProjectDeployments :many
-- Anyone in the team (including 'viewer') can view deployments
SELECT d.* FROM deployments d
JOIN projects p ON d.project_id = p.id
JOIN team_members tm ON p.team_id = tm.team_id
WHERE d.project_id = $1 AND tm.user_id = $2
ORDER BY d.created_at DESC
LIMIT 50;
