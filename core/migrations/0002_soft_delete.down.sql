-- ============================================================================
-- MIGRATION 0002 (rollback): Remove soft-delete columns from users and teams
-- ============================================================================

DROP INDEX IF EXISTS idx_users_active;
DROP INDEX IF EXISTS idx_teams_active;

ALTER TABLE users DROP COLUMN deleted_at;
ALTER TABLE teams DROP COLUMN deleted_at;
