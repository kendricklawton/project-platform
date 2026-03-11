package config

import (
	"fmt"
	"os"
	"strconv"
)

type ServerConfig struct {
	Port           int
	Debug          bool
	DatabaseURL    string
	InternalSecret string
}

func LoadServer() (*ServerConfig, error) {
	cfg := &ServerConfig{}
	var err error

	if cfg.Port, err = getEnvInt("PLATFORM_PORT", 8080); err != nil {
		return nil, err
	}

	if cfg.Debug, err = getEnvBool("PLATFORM_DEBUG", false); err != nil {
		return nil, err
	}

	if cfg.DatabaseURL, err = getEnvRequired("PLATFORM_DATABASE_URL"); err != nil {
		return nil, err
	}
	if cfg.InternalSecret, err = getEnvRequired("PLATFORM_INTERNAL_SECRET"); err != nil {
		return nil, err
	}

	return cfg, nil
}

// WEB BFF CONFIGURATION (For platform-web)
type WebConfig struct {
	Port              int
	Debug             bool
	APIURL            string
	WebBaseURL        string
	InternalSecret    string
	AdminPasswordHash string
}

func LoadWeb() (*WebConfig, error) {
	cfg := &WebConfig{}
	var err error

	if cfg.Port, err = getEnvInt("PLATFORM_WEB_PORT", 3000); err != nil {
		return nil, err
	}
	if cfg.Debug, err = getEnvBool("PLATFORM_DEBUG", false); err != nil {
		return nil, err
	}

	cfg.APIURL = getEnv("PLATFORM_API_URL", "http://localhost:8080")
	cfg.WebBaseURL = getEnv("PLATFORM_WEB_BASE_URL", "http://localhost:3000")

	if cfg.InternalSecret, err = getEnvRequired("PLATFORM_INTERNAL_SECRET"); err != nil {
		return nil, err
	}
	if cfg.AdminPasswordHash, err = getEnvRequired("PLATFORM_ADMIN_PASSWORD_HASH"); err != nil {
		return nil, err
	}

	return cfg, nil
}

// HELPER FUNCTIONS
func getEnv(key, fallback string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return fallback
}

func getEnvRequired(key string) (string, error) {
	value, exists := os.LookupEnv(key)
	if !exists || value == "" {
		return "", fmt.Errorf("missing required environment variable: %s", key)
	}
	return value, nil
}

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
