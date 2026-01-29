package config

import (
	"fmt"

	"github.com/kelseyhightower/envconfig"
)

// Config holds all the runtime configuration for the Platform.
// We use struct tags to map environment variables to fields.
type Config struct {
	// Server Settings
	Port  int  `envconfig:"PORT" default:"8080"`
	Debug bool `envconfig:"DEBUG" default:"false"`

	// Database (Postgres) - Required
	// If DB_URL is missing, the app will crash with a helpful error.
	DatabaseURL string `envconfig:"DATABASE_URL" required:"true"`

	// Kubernetes (In-Cluster or Kubeconfig path)
	KubeConfigPath string `envconfig:"KUBECONFIG"`

	// Object Storage (For storing user build logs/artifacts)
	S3Bucket    string `envconfig:"S3_BUCKET" required:"true"`
	S3Region    string `envconfig:"S3_REGION" default:"us-east-1"`
	S3AccessKey string `envconfig:"S3_ACCESS_KEY" required:"true"`
	S3SecretKey string `envconfig:"S3_SECRET_KEY" required:"true"`
}

// Load reads env vars and populates the struct.
func Load() (*Config, error) {
	var cfg Config
	// "PLATFORM" is the prefix. It looks for PLATFORM_PORT, PLATFORM_DATABASE_URL, etc.
	err := envconfig.Process("PLATFORM", &cfg)
	if err != nil {
		return nil, fmt.Errorf("failed to load config: %w", err)
	}
	return &cfg, nil
}
