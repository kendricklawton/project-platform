-- ============================================================================
-- MIGRATION DOWN: Drop everything in reverse dependency order
-- ============================================================================

-- Partitioned tables first (no FKs pointing to them)
DROP TABLE IF EXISTS build_log_lines_2026_01;
DROP TABLE IF EXISTS build_log_lines_2026_02;
DROP TABLE IF EXISTS build_log_lines_2026_03;
DROP TABLE IF EXISTS build_log_lines_2026_04;
DROP TABLE IF EXISTS build_log_lines_2026_05;
DROP TABLE IF EXISTS build_log_lines_2026_06;
DROP TABLE IF EXISTS build_log_lines_2026_07;
DROP TABLE IF EXISTS build_log_lines_2026_08;
DROP TABLE IF EXISTS build_log_lines_2026_09;
DROP TABLE IF EXISTS build_log_lines_2026_10;
DROP TABLE IF EXISTS build_log_lines_2026_11;
DROP TABLE IF EXISTS build_log_lines_2026_12;
DROP TABLE IF EXISTS build_log_lines_default;
DROP TABLE IF EXISTS build_log_lines;

DROP TABLE IF EXISTS audit_log_2026_01;
DROP TABLE IF EXISTS audit_log_2026_02;
DROP TABLE IF EXISTS audit_log_2026_03;
DROP TABLE IF EXISTS audit_log_2026_04;
DROP TABLE IF EXISTS audit_log_2026_05;
DROP TABLE IF EXISTS audit_log_2026_06;
DROP TABLE IF EXISTS audit_log_2026_07;
DROP TABLE IF EXISTS audit_log_2026_08;
DROP TABLE IF EXISTS audit_log_2026_09;
DROP TABLE IF EXISTS audit_log_2026_10;
DROP TABLE IF EXISTS audit_log_2026_11;
DROP TABLE IF EXISTS audit_log_2026_12;
DROP TABLE IF EXISTS audit_log_default;
DROP TABLE IF EXISTS audit_log;

-- Leaf tables (reference others but nothing references them)
DROP TABLE IF EXISTS usage_records;
DROP TABLE IF EXISTS deployments;
DROP TABLE IF EXISTS project_env_vars;
DROP TABLE IF EXISTS webhooks;
DROP TABLE IF EXISTS domains;

-- Mid-level tables
DROP TABLE IF EXISTS projects;
DROP TABLE IF EXISTS team_members;

-- Root tables
DROP TABLE IF EXISTS teams;
DROP TABLE IF EXISTS users;

-- Functions
DROP FUNCTION IF EXISTS set_updated_at();

-- Extensions (optional — uncomment if you want a truly clean slate)
-- DROP EXTENSION IF EXISTS "pgcrypto";
