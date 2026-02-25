-- ============================================================================
-- SCHEMA: PaaS Platform
-- Database: PostgreSQL 16+
-- PK Strategy: UUIDv7 (application-generated, time-sortable)
-- Encryption: Envelope encryption via KMS for secrets
-- Partitioning: build_log_lines, audit_log (monthly by created_at)
-- ============================================================================

-- Required extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- UTILITY: updated_at trigger function
-- Applied to all mutable tables so application code never has to set it
-- ============================================================================
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- USERS
-- ============================================================================
CREATE TABLE users (
    id UUID PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    avatar_url TEXT,
    stripe_customer_id TEXT UNIQUE,
    tier TEXT NOT NULL DEFAULT 'free' CHECK (tier IN ('free', 'pro', 'enterprise')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================================
-- TEAMS
-- ============================================================================
CREATE TABLE teams (
    id UUID PRIMARY KEY,
    name TEXT NOT NULL,
    slug TEXT UNIQUE NOT NULL,
    stripe_subscription_id TEXT UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_teams_updated_at
    BEFORE UPDATE ON teams
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================================
-- TEAM MEMBERS (RBAC: owner, member, viewer)
-- ============================================================================
CREATE TABLE team_members (
    team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('owner', 'member', 'viewer')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (team_id, user_id)
);

CREATE INDEX idx_team_members_user ON team_members(user_id);

-- ============================================================================
-- PROJECTS
-- ============================================================================
CREATE TABLE projects (
    id UUID PRIMARY KEY,
    team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    framework TEXT NOT NULL DEFAULT 'other' CHECK (framework IN (
        'nextjs', 'remix', 'astro', 'nuxt', 'svelte',
        'go', 'docker', 'static', 'other'
    )),
    repo_url TEXT NOT NULL,
    default_branch TEXT NOT NULL DEFAULT 'main',
    root_directory TEXT NOT NULL DEFAULT './',
    build_command TEXT,
    install_command TEXT,
    output_directory TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(team_id, name)
);

CREATE INDEX idx_projects_team_created ON projects(team_id, created_at DESC);

CREATE TRIGGER trg_projects_updated_at
    BEFORE UPDATE ON projects
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================================
-- DOMAINS
-- ============================================================================
CREATE TABLE domains (
    id UUID PRIMARY KEY,
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    domain TEXT UNIQUE NOT NULL,
    is_verified BOOLEAN NOT NULL DEFAULT false,
    verification_type TEXT NOT NULL DEFAULT 'cname' CHECK (verification_type IN ('cname', 'txt')),
    verification_token TEXT NOT NULL DEFAULT encode(gen_random_bytes(32), 'hex'),
    tls_status TEXT NOT NULL DEFAULT 'pending' CHECK (tls_status IN (
        'pending', 'provisioning', 'active', 'error'
    )),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_domains_project ON domains(project_id);

CREATE TRIGGER trg_domains_updated_at
    BEFORE UPDATE ON domains
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================================
-- SECRETS MANAGEMENT (Envelope Encryption)
-- ============================================================================
CREATE TABLE project_env_vars (
    id UUID PRIMARY KEY,
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    environment TEXT NOT NULL CHECK (environment IN ('production', 'preview', 'development')),
    key_name TEXT NOT NULL,
    encrypted_value BYTEA NOT NULL,
    encrypted_data_key BYTEA NOT NULL,
    encryption_iv BYTEA NOT NULL,
    kms_key_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(project_id, environment, key_name)
);

CREATE INDEX idx_env_vars_project_env ON project_env_vars(project_id, environment);

CREATE TRIGGER trg_env_vars_updated_at
    BEFORE UPDATE ON project_env_vars
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================================
-- WEBHOOKS (GitHub / GitLab / Bitbucket)
-- ============================================================================
CREATE TABLE webhooks (
    id UUID PRIMARY KEY,
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    provider TEXT NOT NULL CHECK (provider IN ('github', 'gitlab', 'bitbucket')),
    provider_install_id TEXT NOT NULL,
    hook_secret_encrypted BYTEA NOT NULL,
    events TEXT[] NOT NULL DEFAULT '{push}',
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_webhooks_project ON webhooks(project_id);
CREATE UNIQUE INDEX idx_webhooks_provider_install ON webhooks(provider, provider_install_id);

CREATE TRIGGER trg_webhooks_updated_at
    BEFORE UPDATE ON webhooks
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================================
-- DEPLOYMENTS
-- ============================================================================
CREATE TABLE deployments (
    id UUID PRIMARY KEY,
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    environment TEXT NOT NULL CHECK (environment IN ('production', 'preview')),
    status TEXT NOT NULL DEFAULT 'queued' CHECK (status IN (
        'queued', 'building', 'deploying', 'ready', 'error', 'canceled'
    )),
    -- Git metadata
    branch TEXT NOT NULL,
    commit_sha TEXT NOT NULL,
    commit_message TEXT NOT NULL,
    -- Infrastructure links
    deployment_url TEXT,
    build_logs_uri TEXT,
    -- Timing
    build_started_at TIMESTAMPTZ,
    build_finished_at TIMESTAMPTZ,
    -- Soft delete
    deleted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_deployments_project_created ON deployments(project_id, created_at DESC);
CREATE INDEX idx_deployments_project_env_status ON deployments(project_id, environment, status)
    WHERE deleted_at IS NULL;
-- Partial index: only index active work for the build queue
CREATE INDEX idx_deployments_queue ON deployments(status, created_at)
    WHERE status IN ('queued', 'building') AND deleted_at IS NULL;

CREATE TRIGGER trg_deployments_updated_at
    BEFORE UPDATE ON deployments
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================================
-- BUILD LOG LINES (Partitioned by month)
--
-- UUIDv7 PKs are time-sortable so they work well with range partitions.
-- The PK is (id, created_at) because Postgres requires the partition key
-- in the primary key for partitioned tables.
-- ============================================================================
CREATE TABLE build_log_lines (
    id UUID NOT NULL,
    deployment_id UUID NOT NULL,
    line_number INT NOT NULL,
    content TEXT NOT NULL,
    stream TEXT NOT NULL DEFAULT 'stdout' CHECK (stream IN ('stdout', 'stderr')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

-- FK not supported on partitioned tables in PG < 17, enforced in application layer
-- If PG 17+, uncomment:
-- ALTER TABLE build_log_lines ADD CONSTRAINT fk_build_logs_deployment
--     FOREIGN KEY (deployment_id) REFERENCES deployments(id) ON DELETE CASCADE;

CREATE INDEX idx_build_logs_deployment ON build_log_lines(deployment_id, line_number);

-- Pre-create 12 months of partitions + a default catch-all
CREATE TABLE build_log_lines_2026_01 PARTITION OF build_log_lines
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE build_log_lines_2026_02 PARTITION OF build_log_lines
    FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
CREATE TABLE build_log_lines_2026_03 PARTITION OF build_log_lines
    FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');
CREATE TABLE build_log_lines_2026_04 PARTITION OF build_log_lines
    FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE build_log_lines_2026_05 PARTITION OF build_log_lines
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE build_log_lines_2026_06 PARTITION OF build_log_lines
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE build_log_lines_2026_07 PARTITION OF build_log_lines
    FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
CREATE TABLE build_log_lines_2026_08 PARTITION OF build_log_lines
    FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE build_log_lines_2026_09 PARTITION OF build_log_lines
    FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE build_log_lines_2026_10 PARTITION OF build_log_lines
    FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE build_log_lines_2026_11 PARTITION OF build_log_lines
    FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');
CREATE TABLE build_log_lines_2026_12 PARTITION OF build_log_lines
    FOR VALUES FROM ('2026-12-01') TO ('2027-01-01');
CREATE TABLE build_log_lines_default PARTITION OF build_log_lines DEFAULT;

-- ============================================================================
-- AUDIT LOG (Partitioned by month)
--
-- Every mutation in the system gets an audit entry. Partitioned because
-- this grows fastest of any table. Old partitions can be detached and
-- archived to S3/GCS after 12-18 months.
-- ============================================================================
CREATE TABLE audit_log (
    id UUID NOT NULL,
    team_id UUID NOT NULL,
    actor_id UUID,
    action TEXT NOT NULL,
    resource_type TEXT NOT NULL,
    resource_id UUID,
    metadata JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

-- FK enforced at application layer for partitioned tables
CREATE INDEX idx_audit_team_created ON audit_log(team_id, created_at DESC);
CREATE INDEX idx_audit_actor_created ON audit_log(actor_id, created_at DESC);
CREATE INDEX idx_audit_resource ON audit_log(resource_type, resource_id, created_at DESC);

-- Pre-create 12 months of partitions + default
CREATE TABLE audit_log_2026_01 PARTITION OF audit_log
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE audit_log_2026_02 PARTITION OF audit_log
    FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
CREATE TABLE audit_log_2026_03 PARTITION OF audit_log
    FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');
CREATE TABLE audit_log_2026_04 PARTITION OF audit_log
    FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE audit_log_2026_05 PARTITION OF audit_log
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE audit_log_2026_06 PARTITION OF audit_log
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
CREATE TABLE audit_log_2026_07 PARTITION OF audit_log
    FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
CREATE TABLE audit_log_2026_08 PARTITION OF audit_log
    FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE audit_log_2026_09 PARTITION OF audit_log
    FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE audit_log_2026_10 PARTITION OF audit_log
    FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE audit_log_2026_11 PARTITION OF audit_log
    FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');
CREATE TABLE audit_log_2026_12 PARTITION OF audit_log
    FOR VALUES FROM ('2026-12-01') TO ('2027-01-01');
CREATE TABLE audit_log_default PARTITION OF audit_log DEFAULT;

-- ============================================================================
-- USAGE / BILLING TRACKING
-- ============================================================================
CREATE TABLE usage_records (
    id UUID PRIMARY KEY,
    team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    metric TEXT NOT NULL CHECK (metric IN (
        'build_minutes', 'bandwidth_gb', 'function_invocations',
        'concurrent_builds', 'storage_gb'
    )),
    quantity NUMERIC NOT NULL,
    period_start DATE NOT NULL,
    period_end DATE NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_usage_team_period ON usage_records(team_id, period_start, period_end);
CREATE INDEX idx_usage_team_metric ON usage_records(team_id, metric, period_start);

-- ============================================================================
-- DATABASE-LEVEL SAFETY SETTINGS
-- Run these as superuser against your production database
-- ============================================================================
-- ALTER DATABASE paas SET statement_timeout = '30s';
-- ALTER DATABASE paas SET lock_timeout = '10s';
-- ALTER DATABASE paas SET idle_in_transaction_session_timeout = '60s';

-- ============================================================================
-- PARTITION MAINTENANCE
--
-- Run monthly via cron or pg_cron to create next month's partitions:
--
--   SELECT create_monthly_partitions('build_log_lines', '2027-01-01', '2027-02-01');
--   SELECT create_monthly_partitions('audit_log', '2027-01-01', '2027-02-01');
--
-- To archive old partitions:
--
--   ALTER TABLE build_log_lines DETACH PARTITION build_log_lines_2026_01;
--   -- pg_dump and ship to S3, then DROP TABLE build_log_lines_2026_01;
-- ============================================================================
