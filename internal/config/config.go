package config

import (
	"errors"
	"os"
)

type Config struct {
	Port               string
	DatabaseURL        string
	GoogleClientID     string
	GoogleClientSecret string
	GoogleRedirectURL  string
	SessionSecret      string
	FrontendURL        string
}

func Load() (*Config, error) {
	c := &Config{
		Port:               getenv("PORT", "8085"),
		DatabaseURL:        os.Getenv("DATABASE_URL"),
		GoogleClientID:     os.Getenv("GOOGLE_CLIENT_ID"),
		GoogleClientSecret: os.Getenv("GOOGLE_CLIENT_SECRET"),
		GoogleRedirectURL:  getenv("GOOGLE_REDIRECT_URL", "http://localhost:8085/api/v1/auth/google/callback"),
		SessionSecret:      os.Getenv("SESSION_SECRET"),
		FrontendURL:        getenv("FRONTEND_URL", "http://localhost:3005"),
	}
	if c.DatabaseURL == "" {
		return nil, errors.New("DATABASE_URL is required")
	}
	return c, nil
}

func getenv(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
