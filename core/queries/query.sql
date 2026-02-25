-- ============================================================================
-- QUERIES: sqlc query definitions
-- Naming: sqlc conventions (:one, :many, :exec, :execrows)
-- Auth pattern: WHERE EXISTS subquery for RBAC inline with mutations
-- ============================================================================

-- ============================================================================
-- USERS
-- ============================================================================

-- name: GetUser :one
SELECT * FROM users WHERE id = $1;

-- name: GetUserByEmail :one
SELECT * FROM users WHERE email = $1;

-- name: UpdateUserTier :one
UPDATE users SET tier = $2 WHERE id = $1 RETURNING *;

-- name: UpdateUserStripeCustomerID :one
UPDATE users SET stripe_customer_id = $2 WHERE id = $1 RETURNING *;

-- name: UpdateUserProfile :one
UPDATE users SET name = $2, avatar_url = $3 WHERE id = $1 RETURNING *;

-- ============================================================================
-- TEAMS
-- ============================================================================

-- name: GetTeam :one
SELECT * FROM teams WHERE id = $1;

-- name: GetTeamBySlug :one
SELECT * FROM teams WHERE slug = $1;

-- name: GetTeamsForUser :many
SELECT t.*, tm.role FROM teams t
JOIN team_members tm ON t.id = tm.team_id
WHERE tm.user_id = $1
ORDER BY t.name;

-- name: UpdateTeam :one
UPDATE teams SET name = $2, slug = $3
WHERE id = $1
AND EXISTS (
    SELECT 1 FROM team_members
    WHERE team_id = $1 AND user_id = $4 AND role = 'owner'
)
RETURNING *;

-- ============================================================================
-- ONBOARDING
-- ============================================================================

-- name: OnboardUserWithTeam :one
-- Atomic: creates user + personal team + owner membership in one transaction
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

-- ============================================================================
-- TEAM MEMBERS
-- ============================================================================

-- name: AddTeamMember :one
-- Only owners can add members
INSERT INTO team_members (team_id, user_id, role)
SELECT $1, $2, $3
WHERE EXISTS (
    SELECT 1 FROM team_members
    WHERE team_id = $1 AND user_id = $4 AND role = 'owner'
)
RETURNING *;

-- name: UpdateTeamMemberRole :execrows
-- Only owners can change roles; cannot demote the last owner
UPDATE team_members SET role = $3
WHERE team_id = $1 AND user_id = $2
AND EXISTS (
    SELECT 1 FROM team_members
    WHERE team_id = $1 AND user_id = $4 AND role = 'owner'
)
AND NOT (
    -- Prevent removing the last owner
    $3 != 'owner' AND (
        SELECT COUNT(*) FROM team_members
        WHERE team_id = $1 AND role = 'owner'
    ) <= 1 AND user_id = (
        SELECT user_id FROM team_members
        WHERE team_id = $1 AND role = 'owner' LIMIT 1
    )
);

-- name: RemoveTeamMember :execrows
-- Only owners can remove members; cannot remove the last owner
DELETE FROM team_members
WHERE team_id = $1 AND user_id = $2
AND EXISTS (
    SELECT 1 FROM team_members
    WHERE team_id = $1 AND user_id = $3 AND role = 'owner'
)
AND NOT (
    role = 'owner' AND (
        SELECT COUNT(*) FROM team_members
        WHERE team_id = $1 AND role = 'owner'
    ) <= 1
);

-- name: ListTeamMembers :many
SELECT tm.*, u.email, u.name, u.avatar_url FROM team_members tm
JOIN users u ON tm.user_id = u.id
WHERE tm.team_id = $1
ORDER BY tm.role, u.name;

-- name: GetTeamMember :one
SELECT tm.*, u.email, u.name FROM team_members tm
JOIN users u ON tm.user_id = u.id
WHERE tm.team_id = $1 AND tm.user_id = $2;

-- ============================================================================
-- PROJECTS
-- ============================================================================

-- name: CreateProject :one
-- Only owner or member can create projects
INSERT INTO projects (id, team_id, name, framework, repo_url, default_branch, root_directory, build_command, install_command, output_directory)
SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9, $10
WHERE EXISTS (
    SELECT 1 FROM team_members
    WHERE team_id = $2 AND user_id = $11 AND role IN ('owner', 'member')
)
RETURNING *;

-- name: GetProject :one
SELECT p.* FROM projects p
JOIN team_members tm ON p.team_id = tm.team_id
WHERE p.id = $1 AND tm.user_id = $2;

-- name: ListTeamProjects :many
SELECT p.* FROM projects p
JOIN team_members tm ON p.team_id = tm.team_id
WHERE p.team_id = $1 AND tm.user_id = $2
ORDER BY p.created_at DESC;

-- name: UpdateProject :one
UPDATE projects SET
    name = COALESCE(NULLIF($3, ''), name),
    framework = COALESCE(NULLIF($4, ''), framework),
    repo_url = COALESCE(NULLIF($5, ''), repo_url),
    default_branch = COALESCE(NULLIF($6, ''), default_branch),
    root_directory = COALESCE(NULLIF($7, ''), root_directory),
    build_command = $8,
    install_command = $9,
    output_directory = $10
WHERE id = $1
AND EXISTS (
    SELECT 1 FROM projects p
    JOIN team_members tm ON p.team_id = tm.team_id
    WHERE p.id = $1 AND tm.user_id = $2 AND tm.role IN ('owner', 'member')
)
RETURNING *;

-- name: DeleteProject :execrows
-- Only owners can delete projects
DELETE FROM projects
WHERE id = $1
AND EXISTS (
    SELECT 1 FROM projects p
    JOIN team_members tm ON p.team_id = tm.team_id
    WHERE p.id = $1 AND tm.user_id = $2 AND tm.role = 'owner'
);

-- ============================================================================
-- DOMAINS
-- ============================================================================

-- name: AddDomain :one
INSERT INTO domains (id, project_id, domain)
SELECT $1, $2, $3
WHERE EXISTS (
    SELECT 1 FROM projects p
    JOIN team_members tm ON p.team_id = tm.team_id
    WHERE p.id = $2 AND tm.user_id = $4 AND tm.role IN ('owner', 'member')
)
RETURNING *;

-- name: ListProjectDomains :many
SELECT d.* FROM domains d
JOIN projects p ON d.project_id = p.id
JOIN team_members tm ON p.team_id = tm.team_id
WHERE d.project_id = $1 AND tm.user_id = $2
ORDER BY d.created_at DESC;

-- name: VerifyDomain :one
-- Called by your domain verification worker (internal, no user RBAC)
UPDATE domains SET is_verified = true, tls_status = 'provisioning'
WHERE id = $1 RETURNING *;

-- name: UpdateDomainTLSStatus :one
-- Called by your cert provisioning worker (internal)
UPDATE domains SET tls_status = $2
WHERE id = $1 RETURNING *;

-- name: DeleteDomain :execrows
DELETE FROM domains
WHERE id = $1
AND EXISTS (
    SELECT 1 FROM domains d
    JOIN projects p ON d.project_id = p.id
    JOIN team_members tm ON p.team_id = tm.team_id
    WHERE d.id = $1 AND tm.user_id = $2 AND tm.role IN ('owner', 'member')
);

-- name: GetDomainByName :one
-- Used by the edge router / ingress controller to resolve custom domains
SELECT d.*, p.id AS project_id, p.team_id FROM domains d
JOIN projects p ON d.project_id = p.id
WHERE d.domain = $1 AND d.is_verified = true AND d.tls_status = 'active';

-- ============================================================================
-- SECRETS MANAGEMENT
-- ============================================================================

-- name: UpsertEnvVar :one
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
    kms_key_id = EXCLUDED.kms_key_id
RETURNING *;

-- name: DeleteEnvVar :execrows
DELETE FROM project_env_vars
WHERE project_id = $1 AND environment = $2 AND key_name = $3
AND EXISTS (
    SELECT 1 FROM projects p
    JOIN team_members tm ON p.team_id = tm.team_id
    WHERE p.id = $1 AND tm.user_id = $4 AND tm.role IN ('owner', 'member')
);

-- name: ListEnvVarKeys :many
-- Returns key names only (never expose encrypted values to the dashboard)
SELECT id, key_name, environment, kms_key_id, created_at, updated_at
FROM project_env_vars
WHERE project_id = $1
AND EXISTS (
    SELECT 1 FROM projects p
    JOIN team_members tm ON p.team_id = tm.team_id
    WHERE p.id = $1 AND tm.user_id = $2
)
ORDER BY environment, key_name;

-- name: GetEnvVarsForDeployment :many
-- INTERNAL ONLY: called by the build worker to inject secrets into the build
-- No user RBAC — this is a service-to-service call authed by internal token
SELECT key_name, encrypted_value, encrypted_data_key, encryption_iv, kms_key_id
FROM project_env_vars
WHERE project_id = $1 AND environment = $2;

-- ============================================================================
-- WEBHOOKS
-- ============================================================================

-- name: CreateWebhook :one
INSERT INTO webhooks (id, project_id, provider, provider_install_id, hook_secret_encrypted, events)
SELECT $1, $2, $3, $4, $5, $6
WHERE EXISTS (
    SELECT 1 FROM projects p
    JOIN team_members tm ON p.team_id = tm.team_id
    WHERE p.id = $2 AND tm.user_id = $7 AND tm.role IN ('owner', 'member')
)
RETURNING *;

-- name: GetWebhookByProviderInstall :one
-- Used by the webhook ingress handler to match an incoming push event to a project
SELECT w.*, p.team_id FROM webhooks w
JOIN projects p ON w.project_id = p.id
WHERE w.provider = $1 AND w.provider_install_id = $2 AND w.is_active = true;

-- name: ListProjectWebhooks :many
SELECT w.* FROM webhooks w
JOIN projects p ON w.project_id = p.id
JOIN team_members tm ON p.team_id = tm.team_id
WHERE w.project_id = $1 AND tm.user_id = $2
ORDER BY w.created_at DESC;

-- name: DeleteWebhook :execrows
DELETE FROM webhooks
WHERE id = $1
AND EXISTS (
    SELECT 1 FROM webhooks w
    JOIN projects p ON w.project_id = p.id
    JOIN team_members tm ON p.team_id = tm.team_id
    WHERE w.id = $1 AND tm.user_id = $2 AND tm.role IN ('owner', 'member')
);

-- ============================================================================
-- DEPLOYMENTS
-- ============================================================================

-- name: CreateDeployment :one
INSERT INTO deployments (id, project_id, environment, branch, commit_sha, commit_message)
SELECT $1, $2, $3, $4, $5, $6
WHERE EXISTS (
    SELECT 1 FROM projects p
    JOIN team_members tm ON p.team_id = tm.team_id
    WHERE p.id = $2 AND tm.user_id = $7 AND tm.role IN ('owner', 'member')
)
RETURNING *;

-- name: GetDeployment :one
SELECT d.* FROM deployments d
JOIN projects p ON d.project_id = p.id
JOIN team_members tm ON p.team_id = tm.team_id
WHERE d.id = $1 AND tm.user_id = $2 AND d.deleted_at IS NULL;

-- name: ListProjectDeployments :many
SELECT d.* FROM deployments d
JOIN projects p ON d.project_id = p.id
JOIN team_members tm ON p.team_id = tm.team_id
WHERE d.project_id = $1 AND tm.user_id = $2 AND d.deleted_at IS NULL
ORDER BY d.created_at DESC
LIMIT $3 OFFSET $4;

-- name: GetLatestDeployment :one
-- Powers the "current production" badge on the project dashboard
SELECT * FROM deployments
WHERE project_id = $1 AND environment = $2 AND status = 'ready' AND deleted_at IS NULL
ORDER BY created_at DESC
LIMIT 1;

-- name: UpdateDeploymentStatus :one
-- INTERNAL: called by the build worker
UPDATE deployments SET
    status = $2,
    deployment_url = COALESCE($3, deployment_url),
    build_logs_uri = COALESCE($4, build_logs_uri),
    build_started_at = CASE WHEN $2 = 'building' AND build_started_at IS NULL THEN NOW() ELSE build_started_at END,
    build_finished_at = CASE WHEN $2 IN ('ready', 'error', 'canceled') AND build_finished_at IS NULL THEN NOW() ELSE build_finished_at END
WHERE id = $1
RETURNING *;

-- name: CancelDeployment :one
UPDATE deployments SET status = 'canceled'
WHERE id = $1 AND status IN ('queued', 'building')
AND EXISTS (
    SELECT 1 FROM projects p
    JOIN team_members tm ON p.team_id = tm.team_id
    WHERE p.id = deployments.project_id AND tm.user_id = $2 AND tm.role IN ('owner', 'member')
)
RETURNING *;

-- name: SoftDeleteDeployment :execrows
UPDATE deployments SET deleted_at = NOW()
WHERE id = $1 AND deleted_at IS NULL
AND EXISTS (
    SELECT 1 FROM projects p
    JOIN team_members tm ON p.team_id = tm.team_id
    WHERE p.id = deployments.project_id AND tm.user_id = $2 AND tm.role = 'owner'
);

-- name: CountQueuedDeployments :one
-- Used for backpressure / concurrency limits in the build queue
SELECT COUNT(*) FROM deployments
WHERE status IN ('queued', 'building') AND deleted_at IS NULL;

-- name: CountTeamQueuedDeployments :one
-- Per-team concurrency limit check
SELECT COUNT(*) FROM deployments d
JOIN projects p ON d.project_id = p.id
WHERE p.team_id = $1 AND d.status IN ('queued', 'building') AND d.deleted_at IS NULL;

-- name: GetStaleBuilds :many
-- INTERNAL: build watchdog picks up builds that have been stuck too long
SELECT * FROM deployments
WHERE status = 'building'
AND build_started_at < NOW() - INTERVAL '30 minutes'
AND deleted_at IS NULL
ORDER BY build_started_at
LIMIT 50;

-- ============================================================================
-- BUILD LOG LINES
-- ============================================================================

-- name: InsertBuildLogLine :exec
-- INTERNAL: called by the build worker streaming logs
INSERT INTO build_log_lines (id, deployment_id, line_number, content, stream, created_at)
VALUES ($1, $2, $3, $4, $5, $6);

-- name: InsertBuildLogBatch :copyfrom
-- INTERNAL: batch insert for high-throughput log streaming
INSERT INTO build_log_lines (id, deployment_id, line_number, content, stream, created_at)
VALUES ($1, $2, $3, $4, $5, $6);

-- name: GetBuildLogs :many
-- Paginated log retrieval for the deployment detail page
SELECT line_number, content, stream, created_at
FROM build_log_lines
WHERE deployment_id = $1
AND line_number > $2
ORDER BY line_number
LIMIT $3;

-- name: GetBuildLogCount :one
SELECT COUNT(*) FROM build_log_lines WHERE deployment_id = $1;

-- ============================================================================
-- AUDIT LOG
-- ============================================================================

-- name: CreateAuditEntry :exec
INSERT INTO audit_log (id, team_id, actor_id, action, resource_type, resource_id, metadata, ip_address, user_agent, created_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10);

-- name: ListTeamAuditLog :many
-- Paginated audit log for team settings page
SELECT al.*, u.email AS actor_email, u.name AS actor_name
FROM audit_log al
LEFT JOIN users u ON al.actor_id = u.id
WHERE al.team_id = $1
AND al.created_at >= $2
AND al.created_at < $3
ORDER BY al.created_at DESC
LIMIT $4 OFFSET $5;

-- name: ListResourceAuditLog :many
-- Audit trail for a specific resource (e.g., all actions on a project)
SELECT al.*, u.email AS actor_email, u.name AS actor_name
FROM audit_log al
LEFT JOIN users u ON al.actor_id = u.id
WHERE al.resource_type = $1 AND al.resource_id = $2
AND al.created_at >= $3
AND al.created_at < $4
ORDER BY al.created_at DESC
LIMIT $5;

-- ============================================================================
-- USAGE / BILLING
-- ============================================================================

-- name: RecordUsage :exec
INSERT INTO usage_records (id, team_id, metric, quantity, period_start, period_end)
VALUES ($1, $2, $3, $4, $5, $6);

-- name: GetTeamUsageSummary :many
-- Dashboard usage widget: aggregated by metric for current billing period
SELECT metric, SUM(quantity) AS total
FROM usage_records
WHERE team_id = $1 AND period_start >= $2 AND period_end <= $3
GROUP BY metric;

-- name: GetTeamUsageDetail :many
-- Detailed usage breakdown for billing page
SELECT * FROM usage_records
WHERE team_id = $1 AND metric = $2 AND period_start >= $3
ORDER BY period_start DESC
LIMIT $4;
