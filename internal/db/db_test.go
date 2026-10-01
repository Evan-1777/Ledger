package db

import (
	"os"
	"path/filepath"
	"testing"
)

func TestInitDB(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "ledger-db-test-*")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	dbPath := filepath.Join(tempDir, "test.db")
	database, err := InitDB(dbPath)
	if err != nil {
		t.Fatalf("InitDB failed: %v", err)
	}
	defer database.Close()

	var journalMode string
	err = database.QueryRow("PRAGMA journal_mode;").Scan(&journalMode)
	if err != nil {
		t.Fatalf("failed to query journal_mode: %v", err)
	}

	if journalMode != "wal" {
		t.Errorf("expected journal_mode 'wal', got '%s'", journalMode)
	}

	// Verify payment methods seeded
	var pmCount int
	if err := database.QueryRow("SELECT COUNT(*) FROM payment_methods").Scan(&pmCount); err != nil {
		t.Fatalf("failed to query payment_methods count: %v", err)
	}
	if pmCount != 4 {
		t.Errorf("expected 4 payment methods, got %d", pmCount)
	}

	// Verify categories seeded
	var catCount int
	if err := database.QueryRow("SELECT COUNT(*) FROM categories").Scan(&catCount); err != nil {
		t.Fatalf("failed to query categories count: %v", err)
	}
	if catCount != 5 {
		t.Errorf("expected 5 categories, got %d", catCount)
	}

	// Verify tags seeded
	var tagCount int
	if err := database.QueryRow("SELECT COUNT(*) FROM tags").Scan(&tagCount); err != nil {
		t.Fatalf("failed to query tags count: %v", err)
	}
	if tagCount != 16 {
		t.Errorf("expected 16 tags, got %d", tagCount)
	}

	// Verify idempotency on second InitDB call
	database2, err := InitDB(dbPath)
	if err != nil {
		t.Fatalf("second InitDB failed: %v", err)
	}
	defer database2.Close()

	if err := database2.QueryRow("SELECT COUNT(*) FROM payment_methods").Scan(&pmCount); err != nil {
		t.Fatalf("failed to query payment_methods count after re-init: %v", err)
	}
	if pmCount != 4 {
		t.Errorf("idempotency check failed: expected 4 payment methods, got %d", pmCount)
	}

	// Verify foreign key restriction on transactions
	_, err = database2.Exec("INSERT INTO transactions (amount_cents, description, payment_method_id, category_id, tag_id, transacted_at) VALUES (100, 'test', 9999, 9999, 9999, '2026-10-01T12:00:00Z')")
	if err == nil {
		t.Errorf("expected foreign key constraint violation error, got nil")
	}
}
