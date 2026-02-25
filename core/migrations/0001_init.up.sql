CREATE TABLE users (
    id UUID PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    stripe_customer_id TEXT UNIQUE,
    tier TEXT NOT NULL DEFAULT 'free',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE teams (
    id UUID PRIMARY KEY,
    name TEXT NOT NULL,
    slug TEXT UNIQUE NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- TEAM RBAC: Vercel standard (owner, member, viewer)
CREATE TABLE team_members (
    team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('owner', 'member', 'viewer')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (team_id, user_id)
);

CREATE INDEX idx_team_members_user_id ON team_members(user_id);

CREATE TABLE projects (
    id UUID PRIMARY KEY,
    team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    framework TEXT NOT NULL DEFAULT 'other', -- e.g., nextjs, go, docker
    repo_url TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(team_id, name)
);

-- --- SECRETS MANAGEMENT (ENVELOPE ENCRYPTION) ---
CREATE TABLE project_env_vars (
    id UUID PRIMARY KEY,
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    environment TEXT NOT NULL CHECK (environment IN ('production', 'preview', 'development')),
    key_name TEXT NOT NULL,

    -- Envelope Encryption Payload
    encrypted_value BYTEA NOT NULL,      -- The actual secret, encrypted by the Data Key
    encrypted_data_key BYTEA NOT NULL,   -- The Data Key, encrypted by the KMS Master Key
    encryption_iv BYTEA NOT NULL,        -- Initialization Vector for AES-GCM
    kms_key_id TEXT NOT NULL,            -- The AWS/GCP KMS Key ID used (for key rotation)

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(project_id, environment, key_name)
);

-- --- DEPLOYMENTS ---
CREATE TABLE deployments (
    id UUID PRIMARY KEY,
    project_id UUID NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
    environment TEXT NOT NULL CHECK (environment IN ('production', 'preview')),
    status TEXT NOT NULL DEFAULT 'queued', CHECK (status IN ('queued', 'building', 'ready', 'error', 'canceled')),

    -- Git Metadata
    branch TEXT NOT NULL,
    commit_sha TEXT NOT NULL,
    commit_message TEXT NOT NULL,

    -- Infrastructure Links
    deployment_url TEXT, -- The generated preview/prod URL
    build_logs_uri TEXT, -- S3 URI to the logs

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_deployments_project_env ON deployments(project_id, environment);
