-- ==========================================
-- 1. USERS & IDENTITY
-- ==========================================
CREATE TABLE users (
    id UUID PRIMARY KEY,                          -- Generated in Go (UUIDv7)
    email TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    stripe_customer_id TEXT UNIQUE,
    tier TEXT NOT NULL DEFAULT 'free',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ==========================================
-- 2. PROJECTS (The "Spaces")
-- ==========================================
CREATE TABLE projects (
    id UUID PRIMARY KEY,                          -- Generated in Go (UUIDv7)
    name TEXT UNIQUE NOT NULL,
    region TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ==========================================
-- 3. RBAC (Project Members)
-- ==========================================
CREATE TABLE project_members (
    id UUID PRIMARY KEY,                          -- Generated in Go (UUIDv7)
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'viewer',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(project_id, user_id)
);

-- ==========================================
-- 4. DEPLOYMENTS (The "Workloads")
-- ==========================================
CREATE TABLE deployments (
    id UUID PRIMARY KEY,                          -- Generated in Go (UUIDv7)
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    image TEXT NOT NULL,
    replicas INT NOT NULL DEFAULT 1,
    status TEXT NOT NULL DEFAULT 'queued',
    url TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ==========================================
-- 5. USAGE METERING (For Stripe Billing)
-- ==========================================
CREATE TABLE project_usage (
    id UUID PRIMARY KEY,                          -- Generated in Go (UUIDv7)
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    billing_period TEXT NOT NULL,
    compute_seconds BIGINT NOT NULL DEFAULT 0,
    bandwidth_bytes BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(project_id, billing_period)
);

-- ==========================================
-- 6. PRODUCTION INDEXES (Optimized for UUIDv7)
-- ==========================================

CREATE INDEX idx_project_members_user_id ON project_members(user_id);

-- UUIDv7 OPTIMIZATION:
-- Because UUIDv7 is naturally sorted by time, we index `id DESC` instead of `created_at DESC`.
-- This allows you to fetch a project's latest deployments instantly without touching the timestamp column.
CREATE INDEX idx_deployments_project_id_id ON deployments(project_id, id DESC);

CREATE INDEX idx_deployments_status ON deployments(status) WHERE status = 'queued';
