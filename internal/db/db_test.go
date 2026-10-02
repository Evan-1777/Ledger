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

	// Delete a seeded payment method and a seeded category
	if _, err := database2.Exec("DELETE FROM payment_methods WHERE name = '现金钞票'"); err != nil {
		t.Fatalf("failed to delete payment method: %v", err)
	}
	if _, err := database2.Exec("DELETE FROM tags WHERE category_id = (SELECT id FROM categories WHERE name = '休闲娱乐')"); err != nil {
		t.Fatalf("failed to delete category tags: %v", err)
	}
	if _, err := database2.Exec("DELETE FROM categories WHERE name = '休闲娱乐'"); err != nil {
		t.Fatalf("failed to delete category: %v", err)
	}

	database3, err := InitDB(dbPath)
	if err != nil {
		t.Fatalf("third InitDB failed: %v", err)
	}
	defer database3.Close()

	if err := database3.QueryRow("SELECT COUNT(*) FROM payment_methods").Scan(&pmCount); err != nil {
		t.Fatalf("failed to query payment_methods count after re-init: %v", err)
	}
	if pmCount != 3 {
		t.Errorf("anti-resurrection check failed: expected 3 payment methods after delete, got %d", pmCount)
	}

	if err := database3.QueryRow("SELECT COUNT(*) FROM categories").Scan(&catCount); err != nil {
		t.Fatalf("failed to query categories count after re-init: %v", err)
	}
	if catCount != 4 {
		t.Errorf("anti-resurrection check failed: expected 4 categories after delete, got %d", catCount)
	}

	// Verify foreign key restriction on transactions
	_, err = database3.Exec("INSERT INTO transactions (amount_cents, description, payment_method_id, category_id, tag_id, transacted_at) VALUES (100, 'test', 9999, 9999, 9999, '2026-10-01T12:00:00Z')")
	if err == nil {
		t.Errorf("expected foreign key constraint violation error, got nil")
	}

	// Verify multi-connection pool foreign_keys and busy_timeout inheritance
	conn1, err := database3.Conn(t.Context())
	if err != nil {
		t.Fatalf("failed to open conn1: %v", err)
	}
	defer conn1.Close()

	conn2, err := database3.Conn(t.Context())
	if err != nil {
		t.Fatalf("failed to open conn2: %v", err)
	}
	defer conn2.Close()

	var fk2 int
	if err := conn2.QueryRowContext(t.Context(), "PRAGMA foreign_keys;").Scan(&fk2); err != nil {
		t.Fatalf("failed to query foreign_keys on conn2: %v", err)
	}
	if fk2 != 1 {
		t.Errorf("expected foreign_keys=1 on conn2, got %d", fk2)
	}

	var bt2 int
	if err := conn2.QueryRowContext(t.Context(), "PRAGMA busy_timeout;").Scan(&bt2); err != nil {
		t.Fatalf("failed to query busy_timeout on conn2: %v", err)
	}
	if bt2 != 5000 {
		t.Errorf("expected busy_timeout=5000 on conn2, got %d", bt2)
	}

	_, err = conn2.ExecContext(t.Context(), "INSERT INTO transactions (amount_cents, description, payment_method_id, category_id, tag_id, transacted_at) VALUES (100, 'test', 9999, 9999, 9999, '2026-10-01T12:00:00Z')")
	if err == nil {
		t.Errorf("expected foreign key violation on conn2, got nil")
	}
}

func TestOldDatabaseUpgrade(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "ledger-old-db-test-*")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	dbPath := filepath.Join(tempDir, "old_ledger.db")

	// Simulate old database before system_meta existed
	rawDB, err := InitDB(dbPath)
	if err != nil {
		t.Fatalf("failed to create initial db: %v", err)
	}

	// Drop system_meta and clear default seeds to simulate a custom old database
	if _, err := rawDB.Exec("DROP TABLE IF EXISTS system_meta;"); err != nil {
		t.Fatalf("failed to drop system_meta: %v", err)
	}
	if _, err := rawDB.Exec("DELETE FROM tags;"); err != nil {
		t.Fatalf("failed to clear tags: %v", err)
	}
	if _, err := rawDB.Exec("DELETE FROM categories;"); err != nil {
		t.Fatalf("failed to clear categories: %v", err)
	}
	if _, err := rawDB.Exec("DELETE FROM payment_methods;"); err != nil {
		t.Fatalf("failed to clear payment_methods: %v", err)
	}

	// User had custom data
	if _, err := rawDB.Exec("INSERT INTO payment_methods (name, sort_order) VALUES ('老用户自定义渠道', 1);"); err != nil {
		t.Fatalf("failed to insert custom method: %v", err)
	}
	if _, err := rawDB.Exec("INSERT INTO categories (name, sort_order) VALUES ('老用户专属分类', 1);"); err != nil {
		t.Fatalf("failed to insert custom category: %v", err)
	}
	rawDB.Close()

	// Now upgrade image/container: InitDB runs on old database
	upgradedDB, err := InitDB(dbPath)
	if err != nil {
		t.Fatalf("InitDB on old database failed: %v", err)
	}
	defer upgradedDB.Close()

	// Verify system_meta created
	var metaVal string
	err = upgradedDB.QueryRow("SELECT value FROM system_meta WHERE key = 'seed_initialized'").Scan(&metaVal)
	if err != nil {
		t.Fatalf("failed to query system_meta after upgrade: %v", err)
	}
	if metaVal != "true" {
		t.Errorf("expected seed_initialized='true', got '%s'", metaVal)
	}

	// Verify defaults were NOT reinjected
	var pmCount int
	if err := upgradedDB.QueryRow("SELECT COUNT(*) FROM payment_methods").Scan(&pmCount); err != nil {
		t.Fatalf("failed to count payment_methods: %v", err)
	}
	if pmCount != 1 {
		t.Errorf("expected only 1 custom payment method, got %d (defaults were wrongly reinjected)", pmCount)
	}

	var catCount int
	if err := upgradedDB.QueryRow("SELECT COUNT(*) FROM categories").Scan(&catCount); err != nil {
		t.Fatalf("failed to count categories: %v", err)
	}
	if catCount != 1 {
		t.Errorf("expected only 1 custom category, got %d (defaults were wrongly reinjected)", catCount)
	}
}
