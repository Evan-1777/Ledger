package config

import (
	"os"
)

// Config holds application configuration.
type Config struct {
	Port   string
	DBPath string
}

// Load loads configuration from environment variables or falls back to defaults.
func Load() *Config {
	port := os.Getenv("LEDGER_PORT")
	if port == "" {
		port = os.Getenv("PORT")
	}
	if port == "" {
		port = "8080"
	}

	dbPath := os.Getenv("LEDGER_DB_PATH")
	if dbPath == "" {
		dbPath = "data/ledger.db"
	}

	return &Config{
		Port:   port,
		DBPath: dbPath,
	}
}
