package db

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"

	_ "modernc.org/sqlite"
)

// InitDB initializes SQLite database connection with WAL mode and pragmas.
func InitDB(dbPath string) (*sql.DB, error) {
	dir := filepath.Dir(dbPath)
	if dir != "" && dir != "." {
		if err := os.MkdirAll(dir, 0755); err != nil {
			return nil, fmt.Errorf("failed to create db directory: %w", err)
		}
	}

	database, err := sql.Open("sqlite", dbPath)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	// ponytail: 10 connections with WAL mode and 5s busy timeout balances concurrency and safety
	database.SetMaxOpenConns(10)
	database.SetMaxIdleConns(5)

	pragmas := []string{
		"PRAGMA journal_mode = WAL;",
		"PRAGMA busy_timeout = 5000;",
		"PRAGMA synchronous = NORMAL;",
		"PRAGMA foreign_keys = ON;",
	}

	for _, pragma := range pragmas {
		if _, err := database.Exec(pragma); err != nil {
			_ = database.Close()
			return nil, fmt.Errorf("failed to execute pragma (%s): %w", pragma, err)
		}
	}

	if err := database.Ping(); err != nil {
		_ = database.Close()
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	return database, nil
}
