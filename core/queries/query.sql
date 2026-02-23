-- name: GetUser :one
SELECT * FROM users
WHERE id = $1 LIMIT 1;

-- name: GetUserByEmail :one
SELECT * FROM users
WHERE email = $1 LIMIT 1;

-- name: CreateUser :one
INSERT INTO users (id, email, name)
VALUES ($1, $2, $3)
RETURNING *;

-- name: CreateTeam :one
INSERT INTO teams (id, name, slug)
VALUES ($1, $2, $3)
RETURNING *;

-- name: AddTeamMember :exec
INSERT INTO team_members (team_id, user_id, role)
VALUES ($1, $2, $3);

-- name: OnboardUserWithTeam :one
-- This uses a CTE to perform 3 inserts in 1 transaction
WITH new_user AS (
    INSERT INTO users (id, email, name)
    VALUES ($1, $2, $3)
    RETURNING id
),
new_team AS (
    INSERT INTO teams (id, name, slug)
    VALUES ($4, $5, $6)
    RETURNING id, name, slug
)
INSERT INTO team_members (team_id, user_id, role)
SELECT new_team.id, new_user.id, 'owner'
FROM new_user, new_team
RETURNING team_id;
