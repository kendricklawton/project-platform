-- Drop tables in reverse order of creation to avoid Foreign Key violation errors
DROP TABLE IF EXISTS project_usage;
DROP TABLE IF EXISTS deployments;
DROP TABLE IF EXISTS project_members;
DROP TABLE IF EXISTS projects;
DROP TABLE IF EXISTS users;
