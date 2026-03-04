## Environments

### Local (Docker)

`docker-compose.yml` runs `postgres:18-alpine`. Credentials come from `.env`.

```bash
# Start / stop
task db:up
task db:down

# Shell into local DB
task db:login
# or directly:
psql "postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost:5432/${POSTGRES_DB}"
```

### In-Cluster (CloudNativePG on K3s)

CNPG exposes two services per cluster: `-rw` (primary, read/write) and `-ro` (replicas, read-only).
Always write through `-rw`. Point read-heavy queries at `-ro`.

```bash
# Shell via kubectl plugin (no credentials needed, uses kubeconfig auth)
kubectl cnpg psql <cluster-name> -n <ns>

# Port-forward primary and connect locally
kubectl port-forward svc/<cluster-name>-rw 5432:5432 -n <ns> &
psql "postgresql://<user>:<password>@localhost:5432/<db>?sslmode=require"

# Cluster health
kubectl cnpg status <cluster-name> -n <ns>
kubectl get cluster -n <ns>
kubectl get pods -n <ns> -l cnpg.io/cluster=<cluster-name>

# Which pod is primary right now
kubectl get pods -n <ns> -l cnpg.io/instanceRole=primary
```

---

## Schema Overview

All PKs are UUIDv7 (application-generated, time-sortable). `updated_at` is maintained by the `set_updated_at()` trigger on all mutable tables — never set it manually.

```
users               — identity, tier (free/pro/enterprise), Stripe customer
teams               — workspace/org, Stripe subscription
team_members        — RBAC join: owner | member | viewer
projects            — repo config, build commands, framework
domains             — custom domains, TLS status, verification tokens
project_env_vars    — envelope-encrypted secrets (KMS), per environment
webhooks            — GitHub/GitLab/Bitbucket install hooks, encrypted secret
deployments         — build lifecycle, status, git metadata
build_log_lines     — partitioned by month (RANGE on created_at)
audit_log           — partitioned by month (RANGE on created_at)
usage_records       — build minutes, bandwidth, storage per billing period
```

Soft-delete pattern: `users`, `teams`, and `deployments` have a `deleted_at TIMESTAMPTZ` column. All queries filter `WHERE deleted_at IS NULL`. Hard deletes are not used for these tables.

RBAC is enforced inline via `WHERE EXISTS` subqueries in every mutating query — authorization happens in SQL, not the application layer.

Extensions enabled: `pgcrypto` (used for `gen_random_bytes()` on domain verification tokens).

---

## Migrations (golang-migrate)

Migration files live in `core/migrations/`. Naming: `NNNN_description.up.sql` / `NNNN_description.down.sql`.

```bash
task db:create-migration NAME=<description>   # scaffold new up/down pair
task db:migrate                                # apply all pending migrations
task db:migrate-down                           # roll back one step
```

Current migrations:
```
0001_init           — full schema (all tables, indexes, triggers, partitions)
0002_soft_delete    — adds deleted_at to users and teams + partial indexes
```

To apply manually:
```bash
migrate -path core/migrations -database "${DATABASE_URL}" up
migrate -path core/migrations -database "${DATABASE_URL}" down 1
migrate -path core/migrations -database "${DATABASE_URL}" version
migrate -path core/migrations -database "${DATABASE_URL}" force <version>
```

---

## sqlc Queries

Query definitions live in `core/queries/query.sql`. Generated Go code is in `core/internal/db/`.
Run `task db:generate` after editing any query.

### Key patterns

**Atomic onboarding** — creates user + team + owner membership in one CTE, no separate round-trips:
```sql
-- OnboardUserWithTeam
WITH new_user AS (INSERT INTO users ...),
     new_team AS (INSERT INTO teams ...)
INSERT INTO team_members ... SELECT new_team.id, new_user.id, 'owner' ...
```

**RBAC inline with mutations** — authorization is a `WHERE EXISTS` subquery, not application logic:
```sql
-- CreateProject requires caller to be owner or member of the team
INSERT INTO projects (...) SELECT ...
WHERE EXISTS (
    SELECT 1 FROM team_members tm
    WHERE tm.team_id = $2 AND tm.user_id = $11 AND tm.role IN ('owner', 'member')
)
```

**Upsert env vars** — `ON CONFLICT (project_id, environment, key_name) DO UPDATE`:
```sql
-- UpsertEnvVar handles create-or-rotate in one statement
INSERT INTO project_env_vars (...) ... ON CONFLICT (...) DO UPDATE SET ...
```

**Build queue queries**:
```sql
-- CountQueuedDeployments — global build queue depth
SELECT COUNT(*) FROM deployments WHERE status IN ('queued', 'building') AND deleted_at IS NULL;

-- GetStaleBuilds — builds stuck > 30 min (for the reaper job)
SELECT * FROM deployments
WHERE status = 'building' AND build_started_at < NOW() - INTERVAL '30 minutes'
AND deleted_at IS NULL ORDER BY build_started_at LIMIT 50;
```

**Deployment status transitions** — `UpdateDeploymentStatus` sets `build_started_at` / `build_finished_at` automatically via CASE:
```sql
build_started_at  = CASE WHEN $2 = 'building' AND build_started_at IS NULL THEN NOW() ... END
build_finished_at = CASE WHEN $2 IN ('ready', 'error', 'canceled') ...                    END
```

**Bulk log ingestion** — `InsertBuildLogBatch` uses sqlc `:copyfrom` for `COPY FROM STDIN` performance:
```sql
-- InsertBuildLogBatch :copyfrom
INSERT INTO build_log_lines (id, deployment_id, line_number, content, stream, created_at) VALUES (...)
```

---

## Partition Maintenance

`build_log_lines` and `audit_log` are range-partitioned by `created_at` (monthly). Partitions are pre-created through 2026. **Add new partitions before the month begins** or rows will land in the `_default` catch-all (which you then have to re-partition manually).

```sql
-- Add next year's partitions (run in December)
CREATE TABLE build_log_lines_2027_01 PARTITION OF build_log_lines
    FOR VALUES FROM ('2027-01-01') TO ('2027-02-01');
-- ... repeat for each month

CREATE TABLE audit_log_2027_01 PARTITION OF audit_log
    FOR VALUES FROM ('2027-01-01') TO ('2027-02-01');

-- Check what's in the default partition (should be empty)
SELECT COUNT(*) FROM build_log_lines_default;
SELECT COUNT(*) FROM audit_log_default;

-- List all partitions and their row counts
SELECT inhrelid::regclass AS partition, pg_size_pretty(pg_relation_size(inhrelid)) AS size
FROM pg_inherits WHERE inhparent = 'build_log_lines'::regclass ORDER BY inhrelid::regclass::text;

-- Archive an old partition (detach, dump, ship to GCS, drop)
ALTER TABLE build_log_lines DETACH PARTITION build_log_lines_2026_01;
-- pg_dump -Fc build_log_lines_2026_01 > build_log_lines_2026_01.pgc
-- (upload to GCS)
DROP TABLE build_log_lines_2026_01;
```

---

## Project-Specific Debugging Queries

```sql
-- Active deployments by status
SELECT status, COUNT(*) FROM deployments WHERE deleted_at IS NULL GROUP BY status;

-- Latest deployment per project
SELECT DISTINCT ON (project_id) project_id, id, status, commit_sha, created_at
FROM deployments WHERE deleted_at IS NULL ORDER BY project_id, created_at DESC;

-- Build duration stats (completed builds)
SELECT
    AVG(EXTRACT(EPOCH FROM (build_finished_at - build_started_at))) AS avg_seconds,
    MAX(EXTRACT(EPOCH FROM (build_finished_at - build_started_at))) AS max_seconds
FROM deployments WHERE build_finished_at IS NOT NULL AND build_started_at IS NOT NULL;

-- Teams by tier distribution
SELECT u.tier, COUNT(*) FROM users u WHERE deleted_at IS NULL GROUP BY tier;

-- Domains pending TLS provisioning
SELECT d.domain, d.tls_status, d.created_at FROM domains d WHERE tls_status != 'active';

-- Users with no team (orphaned)
SELECT u.id, u.email FROM users u
WHERE NOT EXISTS (SELECT 1 FROM team_members tm WHERE tm.user_id = u.id)
AND u.deleted_at IS NULL;

-- Env var count per project (key names only, values are encrypted)
SELECT project_id, environment, COUNT(*) FROM project_env_vars GROUP BY project_id, environment;

-- Audit log volume per action type (last 30 days)
SELECT action, resource_type, COUNT(*)
FROM audit_log WHERE created_at > NOW() - INTERVAL '30 days'
GROUP BY action, resource_type ORDER BY COUNT(*) DESC;

-- Usage this billing period per team
SELECT team_id, metric, SUM(quantity) AS total
FROM usage_records WHERE period_start >= date_trunc('month', NOW())
GROUP BY team_id, metric ORDER BY team_id, metric;
```

---

## Connect

```bash
# psql basics
psql -h <host> -p 5432 -U <user> -d <database>
psql "postgresql://<user>:<password>@<host>:5432/<database>"
psql "postgresql://<user>:<password>@<host>:5432/<database>?sslmode=require"

# Non-interactive one-liner
psql -h <host> -U <user> -d <db> -c "SELECT version();"
PGPASSWORD=<pw> psql -h <host> -U <user> -d <db> -c "SELECT 1;"
```

## psql Meta-Commands

```sql
\l                    -- list databases
\c <database>         -- connect to database
\dt                   -- list tables in current schema
\dt *.*               -- list all tables across schemas
\d <table>            -- describe table (columns, indexes, constraints)
\d+ <table>           -- verbose describe (includes storage, stats)
\di                   -- list indexes
\ds                   -- list sequences
\dv                   -- list views
\dm                   -- list materialized views
\df                   -- list functions
\dn                   -- list schemas
\du                   -- list roles/users
\dp <table>           -- show table permissions
\timing               -- toggle query execution time
\x                    -- toggle expanded output (great for wide rows)
\e                    -- open $EDITOR for query
\i <file.sql>         -- execute SQL from file
\o <file>             -- redirect output to file
\copy <table> TO 'file.csv' CSV HEADER   -- export to CSV
\copy <table> FROM 'file.csv' CSV HEADER -- import from CSV
\q                    -- quit
```

## Database & Schema Management

```sql
-- Database size
SELECT pg_size_pretty(pg_database_size(current_database()));

-- All table sizes
SELECT relname, pg_size_pretty(pg_total_relation_size(oid)) AS total_size
FROM pg_class WHERE relkind = 'r' ORDER BY pg_total_relation_size(oid) DESC;

-- Row count estimate (fast)
SELECT reltuples::bigint FROM pg_class WHERE relname = '<table>';

-- Column info
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = '<table>' ORDER BY ordinal_position;

-- Add / alter column
ALTER TABLE <table> ADD COLUMN <col> <type>;
ALTER TABLE <table> DROP COLUMN <col>;
ALTER TABLE <table> RENAME COLUMN <old> TO <new>;
ALTER TABLE <table> ALTER COLUMN <col> SET DEFAULT <value>;
ALTER TABLE <table> ALTER COLUMN <col> SET NOT NULL;
ALTER TABLE <table> ALTER COLUMN <col> TYPE <new_type> USING <col>::<new_type>;
```

## Indexes

```sql
-- List indexes on a table
SELECT indexname, indexdef FROM pg_indexes WHERE tablename = '<table>';

-- Create indexes
CREATE INDEX idx_name ON <table>(<col>);
CREATE INDEX idx_name ON <table>(<col>) WHERE <condition>;   -- partial index
CREATE UNIQUE INDEX idx_name ON <table>(<col>);
CREATE INDEX CONCURRENTLY idx_name ON <table>(<col>);        -- no table lock
DROP INDEX CONCURRENTLY idx_name;

-- Index usage stats
SELECT schemaname, tablename, indexname, idx_scan, idx_tup_read, idx_tup_fetch
FROM pg_stat_user_indexes ORDER BY idx_scan DESC;

-- Unused indexes (candidates for removal)
SELECT schemaname, tablename, indexname
FROM pg_stat_user_indexes WHERE idx_scan = 0 AND indexname NOT LIKE '%pkey%';
```

## Users, Roles & Permissions

```sql
CREATE USER <name> WITH PASSWORD '<password>';
GRANT CONNECT ON DATABASE <db> TO <user>;
GRANT USAGE ON SCHEMA public TO <user>;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO <user>;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO <user>;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO <user>;
ALTER USER <name> WITH PASSWORD '<new_password>';
DROP USER <name>;
```

## Active Connections & Sessions

```sql
-- All connections
SELECT pid, usename, application_name, state, wait_event, query_start, query
FROM pg_stat_activity ORDER BY query_start;

-- Long-running queries (> 5 minutes)
SELECT pid, now() - query_start AS duration, query, state
FROM pg_stat_activity
WHERE state != 'idle' AND query_start < now() - interval '5 minutes'
ORDER BY duration DESC;

-- Kill a backend
SELECT pg_terminate_backend(<pid>);

-- Kill all connections to a database
SELECT pg_terminate_backend(pid) FROM pg_stat_activity
WHERE datname = '<db>' AND pid <> pg_backend_pid();
```

## Locks

```sql
-- Current locks
SELECT pid, relation::regclass, mode, granted, query
FROM pg_locks l JOIN pg_stat_activity a USING (pid)
WHERE relation IS NOT NULL;

-- Blocking / blocked queries
SELECT blocked_locks.pid AS blocked_pid,
       blocked_activity.query AS blocked_query,
       blocking_locks.pid AS blocking_pid,
       blocking_activity.query AS blocking_query
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks
  ON blocking_locks.locktype = blocked_locks.locktype
  AND blocking_locks.pid != blocked_locks.pid AND blocking_locks.granted
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;
```

## Performance & Query Analysis

```sql
\timing

EXPLAIN SELECT * FROM <table> WHERE <condition>;
EXPLAIN ANALYZE SELECT * FROM <table> WHERE <condition>;
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) SELECT ...;

-- pg_stat_statements (requires extension)
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
SELECT query, calls, total_exec_time, mean_exec_time, rows
FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 20;
SELECT pg_stat_statements_reset();

-- Seq scan stats (high seq_scan = missing index)
SELECT relname, seq_scan, seq_tup_read, idx_scan
FROM pg_stat_user_tables ORDER BY seq_scan DESC;

-- Cache hit ratio (target > 99%)
SELECT sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) AS cache_hit_ratio
FROM pg_statio_user_tables;
```

## VACUUM & AUTOVACUUM

```sql
VACUUM ANALYZE <table>;
VACUUM FULL <table>;     -- rewrites table, exclusive lock — avoid during business hours

-- Tables with most dead tuples
SELECT relname, n_dead_tup, n_live_tup,
       round(n_dead_tup::numeric / nullif(n_live_tup + n_dead_tup, 0) * 100, 2) AS dead_pct
FROM pg_stat_user_tables WHERE n_live_tup > 0 ORDER BY n_dead_tup DESC LIMIT 20;

-- Autovacuum status
SELECT relname, last_autovacuum, last_autoanalyze, n_dead_tup
FROM pg_stat_user_tables ORDER BY n_dead_tup DESC;
```

## Replication (CNPG / Streaming)

```sql
-- Replication lag (run on primary)
SELECT client_addr, state, write_lag, flush_lag, replay_lag FROM pg_stat_replication;

-- Is this node primary or replica?
SELECT pg_is_in_recovery();   -- true = replica

-- Current LSN
SELECT pg_current_wal_lsn();         -- primary
SELECT pg_last_wal_replay_lsn();     -- replica

-- Replication slots
SELECT slot_name, active, restart_lsn FROM pg_replication_slots;

-- Drop stale slot (blocks WAL cleanup if inactive)
SELECT pg_drop_replication_slot('<slot_name>');
```

## Backup & Restore

```bash
# pg_dump / pg_restore
pg_dump -h <host> -U <user> -d <db> -F c -f dump.pgc
pg_restore -h <host> -U <user> -d <db> -j 4 dump.pgc   # 4 parallel jobs

# CNPG backup
kubectl cnpg backup <cluster-name> -n <ns>
kubectl get backups -n <ns>
kubectl get scheduledbackups -n <ns>
```

## Transactions & Savepoints

```sql
BEGIN;
  INSERT INTO <table> ...;
  SAVEPOINT sp1;
    DELETE FROM <table> WHERE ...;
  ROLLBACK TO SAVEPOINT sp1;
COMMIT;

-- Idle-in-transaction connections (hold locks)
SELECT pid, now() - xact_start AS duration, state, query
FROM pg_stat_activity WHERE state = 'idle in transaction' ORDER BY duration DESC;
```

## Configuration

```sql
SHOW max_connections;
SHOW shared_buffers;
SHOW work_mem;
SHOW wal_level;

-- Session-level (non-persistent)
SET work_mem = '256MB';

-- Database/role level (persistent, no restart)
ALTER DATABASE <db> SET work_mem = '128MB';
ALTER DATABASE <db> SET statement_timeout = '30s';
ALTER DATABASE <db> SET lock_timeout = '10s';
ALTER DATABASE <db> SET idle_in_transaction_session_timeout = '60s';

-- Reload config
SELECT pg_reload_conf();
SHOW config_file;
```

---

**Pro tips:** Use `EXPLAIN (ANALYZE, BUFFERS)` to understand query cost. All mutating queries in this project include inline RBAC via `WHERE EXISTS` — if a write returns 0 rows, check the caller's team membership and role. For CNPG, use `-rw` for writes and `-ro` for read replicas. Never run `VACUUM FULL` during business hours.
