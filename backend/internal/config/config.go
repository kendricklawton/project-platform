package config

import (
	"fmt"

	"github.com/spf13/viper"
	"github.com/workos/workos-go/v6/pkg/usermanagement"
)

type Config struct {
	WorkOSClient *usermanagement.Client
	ClientID     string `mapstructure:"WORKOS_CLIENT_ID"`
	RedirectURI  string `mapstructure:"WORKOS_REDIRECT_URI"`
	Port         string `mapstructure:"PORT"`
	Environment  string `mapstructure:"APP_ENV"`
	RedisURL     string `mapstructure:"REDIS_URL"`
}

func LoadConfig() (*Config, error) {
	// Set defaults
	viper.SetDefault("PORT", "8080")
	viper.SetDefault("APP_ENV", "development")

	// Tell Viper to look for a .env file if it exists
	viper.SetConfigFile(".env")
	viper.SetConfigType("env")
	_ = viper.ReadInConfig() // Ignore error if .env is missing (common in production)

	// Enable automatic environment variable overrides
	// This maps WORKOS_CLIENT_ID to the struct field via mapstructure tags
	viper.AutomaticEnv()

	var cfg Config
	if err := viper.Unmarshal(&cfg); err != nil {
		return nil, fmt.Errorf("failed to unmarshal config: %w", err)
	}

	// Manually initialize the WorkOS Client
	apiKey := viper.GetString("WORKOS_API_KEY")
	if apiKey == "" {
		return nil, fmt.Errorf("WORKOS_API_KEY is missing")
	}
	cfg.WorkOSClient = usermanagement.NewClient(apiKey)

	if err := cfg.Validate(); err != nil {
		return nil, err
	}

	return &cfg, nil
}

func (c *Config) Validate() error {
	if c.ClientID == "" {
		return fmt.Errorf("WORKOS_CLIENT_ID is required")
	}
	if c.Environment == "production" {
		if c.RedisURL == "" {
			return fmt.Errorf("REDIS_URL is required in production")
		}
	}
	return nil
}
