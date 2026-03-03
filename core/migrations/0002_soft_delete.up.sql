-- ============================================================================
-- MIGRATION 0002: Add soft-delete columns to users and teams
-- ============================================================================

ALTER TABLE users ADD COLUMN deleted_at TIMESTAMPTZ;
ALTER TABLE teams ADD COLUMN deleted_at TIMESTAMPTZ;

-- Partial indexes to efficiently filter out soft-deleted rows
CREATE INDEX idx_users_active ON users(email) WHERE deleted_at IS NULL;
CREATE INDEX idx_teams_active ON teams(slug) WHERE deleted_at IS NULL;
