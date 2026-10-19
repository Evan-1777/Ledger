package config

import (
	"crypto/rand"
	"encoding/hex"
	"log"
	"os"
	"strings"
)

// Config holds application configuration.
type Config struct {
	Port          string
	DBPath        string
	AdminPassword string
	TokenSecret   string
	CORSOrigin    string
}

// Load loads configuration from environment variables or falls back to defaults.
func Load() *Config {
	port := os.Getenv("LEDGER_PORT")
	if port == "" {
		port = "8080"
	}

	dbPath := os.Getenv("LEDGER_DB_PATH")
	if dbPath == "" {
		dbPath = "data/ledger.db"
	}

	adminPassword := os.Getenv("LEDGER_ADMIN_PASSWORD")
	if adminPassword == "" {
		adminPassword = "admin123"
		log.Println("[SECURITY WARNING] LEDGER_ADMIN_PASSWORD not set, using default password 'admin123'. Please set LEDGER_ADMIN_PASSWORD in production!")
	}

	tokenSecret := os.Getenv("LEDGER_TOKEN_SECRET")
	if tokenSecret == "" {
		b := make([]byte, 32)
		_, _ = rand.Read(b)
		tokenSecret = hex.EncodeToString(b)
	}

	return &Config{
		Port:          port,
		DBPath:        dbPath,
		AdminPassword: adminPassword,
		TokenSecret:   tokenSecret,
		CORSOrigin:    strings.TrimSpace(os.Getenv("LEDGER_CORS_ORIGIN")),
	}
}
