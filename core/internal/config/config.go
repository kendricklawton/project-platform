package config

import (
	"fmt"
	"os"
	"strconv"
)

// Config holds all the runtime configuration for the Platform.
type Config struct {
	// Server Settings
	Port  int
	Debug bool

	// Database (Postgres) - Required
	DatabaseURL string

	// WorkOS Settings
	WorkOSAPIKey   string
	WorkOSClientID string

	// Kubernetes (In-Cluster or Kubeconfig path)
	KubeConfigPath string

	// Object Storage (For storing user build logs/artifacts)
	S3Bucket    string
	S3Region    string
	S3AccessKey string
	S3SecretKey string
}

// Load reads env vars, validates them, and populates the struct.
func Load() (*Config, error) {
	cfg := &Config{}
	var err error

	// Server Settings
	if cfg.Port, err = getEnvInt("PLATFORM_PORT", 8080); err != nil {
		return nil, err
	}
	if cfg.Debug, err = getEnvBool("PLATFORM_DEBUG", false); err != nil {
		return nil, err
	}

	// Required Variables
	if cfg.DatabaseURL, err = getEnvRequired("PLATFORM_DATABASE_URL"); err != nil {
		return nil, err
	}
	if cfg.WorkOSAPIKey, err = getEnvRequired("PLATFORM_WORKOS_API_KEY"); err != nil {
		return nil, err
	}
	if cfg.WorkOSClientID, err = getEnvRequired("PLATFORM_WORKOS_CLIENT_ID"); err != nil {
		return nil, err
	}
	if cfg.S3Bucket, err = getEnvRequired("PLATFORM_S3_BUCKET"); err != nil {
		return nil, err
	}
	if cfg.S3AccessKey, err = getEnvRequired("PLATFORM_S3_ACCESS_KEY"); err != nil {
		return nil, err
	}
	if cfg.S3SecretKey, err = getEnvRequired("PLATFORM_S3_SECRET_KEY"); err != nil {
		return nil, err
	}

	// Optional Variables with defaults
	cfg.KubeConfigPath = getEnv("PLATFORM_KUBECONFIG", "")
	cfg.S3Region = getEnv("PLATFORM_S3_REGION", "us-east-1")

	return cfg, nil
}

// --- Helper Functions ---

// getEnv retrieves a string environment variable or returns the fallback.
func getEnv(key, fallback string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return fallback
}

// getEnvRequired retrieves an environment variable and returns an error if it is missing or empty.
func getEnvRequired(key string) (string, error) {
	value, exists := os.LookupEnv(key)
	if !exists || value == "" {
		return "", fmt.Errorf("missing required environment variable: %s", key)
	}
	return value, nil
}

// getEnvInt retrieves an environment variable, parses it as an int, or returns the fallback.
func getEnvInt(key string, fallback int) (int, error) {
	if value, exists := os.LookupEnv(key); exists && value != "" {
		parsed, err := strconv.Atoi(value)
		if err != nil {
			return 0, fmt.Errorf("invalid integer for %s: %s", key, value)
		}
		return parsed, nil
	}
	return fallback, nil
}

// getEnvBool retrieves an environment variable, parses it as a boolean, or returns the fallback.
func getEnvBool(key string, fallback bool) (bool, error) {
	if value, exists := os.LookupEnv(key); exists && value != "" {
		parsed, err := strconv.ParseBool(value)
		if err != nil {
			return false, fmt.Errorf("invalid boolean for %s: %s", key, value)
		}
		return parsed, nil
	}
	return fallback, nil
}
