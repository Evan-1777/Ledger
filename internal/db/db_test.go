package db

import (
	"database/sql"
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

	// Verify payment methods seeded (4 asset + 1 liability)
	var pmCount int
	if err := database.QueryRow("SELECT COUNT(*) FROM payment_methods").Scan(&pmCount); err != nil {
		t.Fatalf("failed to query payment_methods count: %v", err)
	}
	if pmCount != 5 {
		t.Errorf("expected 5 payment methods, got %d", pmCount)
	}

	// Verify credit card seeded correctly
	var ccType string
	var ccInitBal, ccLimit int64
	err = database.QueryRow("SELECT type, initial_balance_cents, credit_limit_cents FROM payment_methods WHERE name = '招商信用卡'").
		Scan(&ccType, &ccInitBal, &ccLimit)
	if err != nil {
		t.Fatalf("failed to query credit card: %v", err)
	}
	if ccType != "liability" || ccInitBal != 0 || ccLimit != 2000000 {
		t.Errorf("unexpected credit card config: type=%s, initBal=%d, limit=%d", ccType, ccInitBal, ccLimit)
	}

	// Verify categories seeded (5 defaults + 1 system repayment + 1 system transfer category)
	var catCount int
	if err := database.QueryRow("SELECT COUNT(*) FROM categories").Scan(&catCount); err != nil {
		t.Fatalf("failed to query categories count: %v", err)
	}
	if catCount != 7 {
		t.Errorf("expected 7 categories (5 default + 1 repayment + 1 transfer), got %d", catCount)
	}

	// Verify categories default to included in stats
	var statsIncluded int
	if err := database.QueryRow("SELECT COUNT(*) FROM categories WHERE exclude_from_stats = 0").Scan(&statsIncluded); err != nil {
		t.Fatalf("failed to query exclude_from_stats: %v", err)
	}
	if statsIncluded != catCount {
		t.Errorf("expected all %d categories included in stats, got %d", catCount, statsIncluded)
	}

	// Verify tags seeded (16 defaults + 1 system repayment tag + 1 system transfer tag)
	var tagCount int
	if err := database.QueryRow("SELECT COUNT(*) FROM tags").Scan(&tagCount); err != nil {
		t.Fatalf("failed to query tags count: %v", err)
	}
	if tagCount != 18 {
		t.Errorf("expected 18 tags (16 default + 1 repayment + 1 transfer), got %d", tagCount)
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
	if pmCount != 4 {
		t.Errorf("anti-resurrection check failed: expected 4 payment methods after delete, got %d", pmCount)
	}

	if err := database3.QueryRow("SELECT COUNT(*) FROM categories").Scan(&catCount); err != nil {
		t.Fatalf("failed to query categories count after re-init: %v", err)
	}
	if catCount != 6 {
		t.Errorf("anti-resurrection check failed: expected 6 categories after delete (7 - 1), got %d", catCount)
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
	// 1 custom user category + 1 system repayment category ('债务偿还') + 1 system transfer category ('账户转账') = 3
	if catCount != 3 {
		t.Errorf("expected 3 categories (1 custom + 1 repayment + 1 transfer), got %d", catCount)
	}
	var defaultCatCount int
	if err := upgradedDB.QueryRow("SELECT COUNT(*) FROM categories WHERE name IN ('餐饮美食', '交通出行', '居家生活', '休闲娱乐', '职业收入')").Scan(&defaultCatCount); err != nil {
		t.Fatalf("failed to count default categories: %v", err)
	}
	if defaultCatCount != 0 {
		t.Errorf("expected 0 default categories reinjected, got %d", defaultCatCount)
	}
}

func TestPaymentMethodsMigration(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "ledger-migration-test-*")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	dbPath := filepath.Join(tempDir, "migration.db")

	// Construct an old database manually with old payment_methods schema (no type, initial_balance_cents, credit_limit_cents)
	rawDB, err := sql.Open("sqlite", dbPath)
	if err != nil {
		t.Fatalf("failed to open raw sqlite: %v", err)
	}

	oldSchema := `
	CREATE TABLE payment_methods (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		name TEXT UNIQUE NOT NULL,
		sort_order INTEGER DEFAULT 0,
		created_at TEXT DEFAULT CURRENT_TIMESTAMP
	);
	CREATE TABLE categories (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		name TEXT UNIQUE NOT NULL,
		sort_order INTEGER DEFAULT 0,
		created_at TEXT DEFAULT CURRENT_TIMESTAMP
	);
	CREATE TABLE system_meta (
		key TEXT PRIMARY KEY,
		value TEXT NOT NULL
	);
	INSERT INTO system_meta (key, value) VALUES ('seed_initialized', 'true');
	INSERT INTO payment_methods (name, sort_order) VALUES ('历史存量银行卡', 1);
	`
	if _, err := rawDB.Exec(oldSchema); err != nil {
		rawDB.Close()
		t.Fatalf("failed to create old schema: %v", err)
	}
	rawDB.Close()

	// Call InitDB to trigger hot migration on the old DB which already has seed_initialized = 'true'
	upgradedDB, err := InitDB(dbPath)
	if err != nil {
		t.Fatalf("InitDB failed on migration test: %v", err)
	}
	defer upgradedDB.Close()

	// Inspect table_info to confirm columns added
	rows, err := upgradedDB.Query("PRAGMA table_info(payment_methods)")
	if err != nil {
		t.Fatalf("failed to query table_info: %v", err)
	}
	defer rows.Close()

	hasType := false
	hasInitialBalance := false
	hasCreditLimit := false

	for rows.Next() {
		var cid int
		var name, colType string
		var notNull, pk int
		var dfltValue sql.NullString
		if err := rows.Scan(&cid, &name, &colType, &notNull, &dfltValue, &pk); err != nil {
			t.Fatalf("failed to scan table_info row: %v", err)
		}
		switch name {
		case "type":
			hasType = true
		case "initial_balance_cents":
			hasInitialBalance = true
		case "credit_limit_cents":
			hasCreditLimit = true
		}
	}

	if !hasType || !hasInitialBalance || !hasCreditLimit {
		t.Errorf("migration failed to add all columns: hasType=%v, hasInitBal=%v, hasCreditLimit=%v",
			hasType, hasInitialBalance, hasCreditLimit)
	}

	// Verify old row values
	var colType string
	var initBal, limit int64
	err = upgradedDB.QueryRow("SELECT type, initial_balance_cents, credit_limit_cents FROM payment_methods WHERE name = '历史存量银行卡'").
		Scan(&colType, &initBal, &limit)
	if err != nil {
		t.Fatalf("failed to query migrated row: %v", err)
	}

	if colType != "asset" {
		t.Errorf("expected default type 'asset', got '%s'", colType)
	}
	if initBal != 0 {
		t.Errorf("expected default initial_balance_cents 0, got %d", initBal)
	}
	if limit != 0 {
		t.Errorf("expected default credit_limit_cents 0, got %d", limit)
	}

	// Verify anti-resurrection: seed defaults not reinjected
	var pmCount int
	if err := upgradedDB.QueryRow("SELECT COUNT(*) FROM payment_methods").Scan(&pmCount); err != nil {
		t.Fatalf("failed to count payment_methods: %v", err)
	}
	if pmCount != 1 {
		t.Errorf("expected only 1 payment method, got %d (seeds were wrongly reinjected)", pmCount)
	}
}

func TestTransactionsMigration(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "ledger-tx-migration-test-*")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	dbPath := filepath.Join(tempDir, "migration.db")

	// Construct an old database manually with transactions schema without type and source_payment_method_id
	rawDB, err := sql.Open("sqlite", dbPath)
	if err != nil {
		t.Fatalf("failed to open raw db: %v", err)
	}

	oldSchema := `
	CREATE TABLE categories (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		name TEXT UNIQUE NOT NULL,
		sort_order INTEGER DEFAULT 0,
		created_at TEXT DEFAULT CURRENT_TIMESTAMP
	);
	CREATE TABLE tags (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
		name TEXT NOT NULL,
		sort_order INTEGER DEFAULT 0,
		created_at TEXT DEFAULT CURRENT_TIMESTAMP
	);
	CREATE TABLE payment_methods (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		name TEXT UNIQUE NOT NULL,
		sort_order INTEGER DEFAULT 0,
		type TEXT NOT NULL DEFAULT 'asset',
		initial_balance_cents INTEGER NOT NULL DEFAULT 0,
		credit_limit_cents INTEGER NOT NULL DEFAULT 0,
		created_at TEXT DEFAULT CURRENT_TIMESTAMP
	);
	CREATE TABLE transactions (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		amount_cents INTEGER NOT NULL,
		description TEXT NOT NULL,
		payment_method_id INTEGER NOT NULL REFERENCES payment_methods(id),
		category_id INTEGER NOT NULL REFERENCES categories(id),
		tag_id INTEGER NOT NULL REFERENCES tags(id),
		transacted_at TEXT NOT NULL,
		created_at TEXT DEFAULT CURRENT_TIMESTAMP
	);
	INSERT INTO categories (name, sort_order) VALUES ('餐饮', 1);
	INSERT INTO tags (category_id, name, sort_order) VALUES (1, '午餐', 1);
	INSERT INTO payment_methods (name, sort_order) VALUES ('招商银行', 1);
	INSERT INTO transactions (amount_cents, description, payment_method_id, category_id, tag_id, transacted_at)
	VALUES (-5000, '旧支出', 1, 1, 1, '2026-09-01T12:00:00Z');
	INSERT INTO transactions (amount_cents, description, payment_method_id, category_id, tag_id, transacted_at)
	VALUES (8000, '旧收入', 1, 1, 1, '2026-09-02T12:00:00Z');
	`
	if _, err := rawDB.Exec(oldSchema); err != nil {
		t.Fatalf("failed to create old schema: %v", err)
	}
	rawDB.Close()

	// Upgrade via InitDB
	upgradedDB, err := InitDB(dbPath)
	if err != nil {
		t.Fatalf("InitDB failed to upgrade: %v", err)
	}
	defer upgradedDB.Close()

	// Verify columns exist
	rows, err := upgradedDB.Query("PRAGMA table_info(transactions)")
	if err != nil {
		t.Fatalf("failed to query table_info: %v", err)
	}
	defer rows.Close()

	hasType := false
	hasSourcePM := false
	for rows.Next() {
		var cid int
		var name, colType string
		var notNull, pk int
		var dfltValue sql.NullString
		if err := rows.Scan(&cid, &name, &colType, &notNull, &dfltValue, &pk); err != nil {
			t.Fatalf("failed to scan table_info: %v", err)
		}
		if name == "type" {
			hasType = true
		}
		if name == "source_payment_method_id" {
			hasSourcePM = true
		}
	}
	if !hasType || !hasSourcePM {
		t.Fatalf("transactions columns missing: hasType=%v, hasSourcePM=%v", hasType, hasSourcePM)
	}

	// Verify backfilled type values
	var expType, incType string
	if err := upgradedDB.QueryRow("SELECT type FROM transactions WHERE description = '旧支出'").Scan(&expType); err != nil {
		t.Fatalf("failed to query old expense: %v", err)
	}
	if expType != "expense" {
		t.Errorf("expected 'expense' for negative amount, got '%s'", expType)
	}
	if err := upgradedDB.QueryRow("SELECT type FROM transactions WHERE description = '旧收入'").Scan(&incType); err != nil {
		t.Fatalf("failed to query old income: %v", err)
	}
	if incType != "income" {
		t.Errorf("expected 'income' for positive amount, got '%s'", incType)
	}

	// Verify system repayment category and tag injected
	var sysCatID, sysTagID string
	if err := upgradedDB.QueryRow("SELECT value FROM system_meta WHERE key = 'system_category_repayment_id'").Scan(&sysCatID); err != nil {
		t.Fatalf("failed to query system_category_repayment_id: %v", err)
	}
	if err := upgradedDB.QueryRow("SELECT value FROM system_meta WHERE key = 'system_tag_repayment_id'").Scan(&sysTagID); err != nil {
		t.Fatalf("failed to query system_tag_repayment_id: %v", err)
	}
	if sysCatID == "" || sysTagID == "" {
		t.Errorf("system IDs empty: catID=%s, tagID=%s", sysCatID, sysTagID)
	}
}

func TestCategoriesMigration(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "ledger-cat-migration-test-*")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	dbPath := filepath.Join(tempDir, "cat_migration.db")

	// Construct an old database manually with old categories schema (no type)
	rawDB, err := sql.Open("sqlite", dbPath)
	if err != nil {
		t.Fatalf("failed to open raw db: %v", err)
	}

	oldSchema := `
	CREATE TABLE categories (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		name TEXT UNIQUE NOT NULL,
		sort_order INTEGER DEFAULT 0,
		created_at TEXT DEFAULT CURRENT_TIMESTAMP
	);
	CREATE TABLE tags (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
		name TEXT NOT NULL,
		sort_order INTEGER DEFAULT 0,
		created_at TEXT DEFAULT CURRENT_TIMESTAMP
	);
	CREATE TABLE payment_methods (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		name TEXT UNIQUE NOT NULL,
		sort_order INTEGER DEFAULT 0,
		created_at TEXT DEFAULT CURRENT_TIMESTAMP
	);
	CREATE TABLE system_meta (
		key TEXT PRIMARY KEY,
		value TEXT NOT NULL
	);
	INSERT INTO system_meta (key, value) VALUES ('seed_initialized', 'true');
	INSERT INTO categories (name, sort_order) VALUES ('餐饮美食', 1);
	INSERT INTO categories (name, sort_order) VALUES ('职业收入', 5);
	INSERT INTO categories (name, sort_order) VALUES ('债务偿还', 999);
	`
	if _, err := rawDB.Exec(oldSchema); err != nil {
		rawDB.Close()
		t.Fatalf("failed to create old schema: %v", err)
	}
	rawDB.Close()

	// Upgrade via InitDB
	upgradedDB, err := InitDB(dbPath)
	if err != nil {
		t.Fatalf("InitDB failed to upgrade: %v", err)
	}
	defer upgradedDB.Close()

	// Verify columns exist
	rows, err := upgradedDB.Query("PRAGMA table_info(categories)")
	if err != nil {
		t.Fatalf("failed to query table_info: %v", err)
	}
	defer rows.Close()

	hasType := false
	hasExcludeFromStats := false
	for rows.Next() {
		var cid int
		var name, colType string
		var notNull, pk int
		var dfltValue sql.NullString
		if err := rows.Scan(&cid, &name, &colType, &notNull, &dfltValue, &pk); err != nil {
			t.Fatalf("failed to scan table_info: %v", err)
		}
		switch name {
		case "type":
			hasType = true
		case "exclude_from_stats":
			hasExcludeFromStats = true
		}
	}
	if !hasType {
		t.Fatalf("categories table missing type column")
	}
	if !hasExcludeFromStats {
		t.Fatalf("categories table missing exclude_from_stats column")
	}

	var upgradedCatCount, upgradedIncluded int
	if err := upgradedDB.QueryRow("SELECT COUNT(*) FROM categories").Scan(&upgradedCatCount); err != nil {
		t.Fatalf("failed to count categories: %v", err)
	}
	if err := upgradedDB.QueryRow("SELECT COUNT(*) FROM categories WHERE exclude_from_stats = 0").Scan(&upgradedIncluded); err != nil {
		t.Fatalf("failed to query exclude_from_stats: %v", err)
	}
	if upgradedIncluded != upgradedCatCount {
		t.Errorf("expected all %d upgraded categories included in stats, got %d", upgradedCatCount, upgradedIncluded)
	}

	// Verify backfilled type values
	var foodType, incType, repType, transType string
	if err := upgradedDB.QueryRow("SELECT type FROM categories WHERE name = '餐饮美食'").Scan(&foodType); err != nil {
		t.Fatalf("failed to query 餐饮美食: %v", err)
	}
	if foodType != "expense" {
		t.Errorf("expected default 'expense' for 餐饮美食, got '%s'", foodType)
	}

	if err := upgradedDB.QueryRow("SELECT type FROM categories WHERE name = '职业收入'").Scan(&incType); err != nil {
		t.Fatalf("failed to query 职业收入: %v", err)
	}
	if incType != "income" {
		t.Errorf("expected 'income' for 职业收入, got '%s'", incType)
	}

	if err := upgradedDB.QueryRow("SELECT type FROM categories WHERE name = '债务偿还'").Scan(&repType); err != nil {
		t.Fatalf("failed to query 债务偿还: %v", err)
	}
	if repType != "system" {
		t.Errorf("expected 'system' for 债务偿还, got '%s'", repType)
	}

	if err := upgradedDB.QueryRow("SELECT type FROM categories WHERE name = '账户转账'").Scan(&transType); err != nil {
		t.Fatalf("failed to query 账户转账: %v", err)
	}
	if transType != "system" {
		t.Errorf("expected 'system' for 账户转账, got '%s'", transType)
	}

	// Verify system transfer category and tag injected into system_meta
	var sysCatID, sysTagID string
	if err := upgradedDB.QueryRow("SELECT value FROM system_meta WHERE key = 'system_category_transfer_id'").Scan(&sysCatID); err != nil {
		t.Fatalf("failed to query system_category_transfer_id: %v", err)
	}
	if err := upgradedDB.QueryRow("SELECT value FROM system_meta WHERE key = 'system_tag_transfer_id'").Scan(&sysTagID); err != nil {
		t.Fatalf("failed to query system_tag_transfer_id: %v", err)
	}
	if sysCatID == "" || sysTagID == "" {
		t.Errorf("transfer system IDs empty: catID=%s, tagID=%s", sysCatID, sysTagID)
	}

	// User corrects 职业收入 to 'expense'
	if _, err := upgradedDB.Exec("UPDATE categories SET type = 'expense' WHERE name = '职业收入'"); err != nil {
		t.Fatalf("failed to update 职业收入 to expense: %v", err)
	}
	upgradedDB.Close()

	// Simulate subsequent reboot: verify user correction is preserved and NOT overwritten
	rebootDB, err := InitDB(dbPath)
	if err != nil {
		t.Fatalf("InitDB failed on reboot: %v", err)
	}
	defer rebootDB.Close()

	var afterRebootIncType string
	if err := rebootDB.QueryRow("SELECT type FROM categories WHERE name = '职业收入'").Scan(&afterRebootIncType); err != nil {
		t.Fatalf("failed to query 职业收入 after reboot: %v", err)
	}
	if afterRebootIncType != "expense" {
		t.Errorf("expected 'expense' after reboot (user correction preserved), got '%s'", afterRebootIncType)
	}
}

func TestOldDatabaseWithCustomTransferCategoryUpgrade(t *testing.T) {
	tempDir, err := os.MkdirTemp("", "ledger-custom-transfer-test-*")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}
	defer os.RemoveAll(tempDir)

	dbPath := filepath.Join(tempDir, "old_custom_transfer.db")

	rawDB, err := sql.Open("sqlite", dbPath)
	if err != nil {
		t.Fatalf("failed to open raw sqlite: %v", err)
	}

	oldSchema := `
	CREATE TABLE categories (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		name TEXT UNIQUE NOT NULL,
		sort_order INTEGER DEFAULT 0,
		created_at TEXT DEFAULT CURRENT_TIMESTAMP
	);
	CREATE TABLE tags (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
		name TEXT NOT NULL,
		sort_order INTEGER DEFAULT 0,
		created_at TEXT DEFAULT CURRENT_TIMESTAMP
	);
	CREATE TABLE payment_methods (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		name TEXT UNIQUE NOT NULL,
		sort_order INTEGER DEFAULT 0,
		created_at TEXT DEFAULT CURRENT_TIMESTAMP
	);
	CREATE TABLE system_meta (
		key TEXT PRIMARY KEY,
		value TEXT NOT NULL
	);
	INSERT INTO system_meta (key, value) VALUES ('seed_initialized', 'true');
	-- Old user had created their own '账户转账' category before the feature existed
	INSERT INTO categories (name, sort_order) VALUES ('账户转账', 10);
	`
	if _, err := rawDB.Exec(oldSchema); err != nil {
		rawDB.Close()
		t.Fatalf("failed to create old schema: %v", err)
	}
	rawDB.Close()

	upgradedDB, err := InitDB(dbPath)
	if err != nil {
		t.Fatalf("InitDB failed to upgrade: %v", err)
	}
	defer upgradedDB.Close()

	var transType string
	if err := upgradedDB.QueryRow("SELECT type FROM categories WHERE name = '账户转账'").Scan(&transType); err != nil {
		t.Fatalf("failed to query 账户转账: %v", err)
	}
	if transType != "system" {
		t.Errorf("expected 'system' for pre-existing 账户转账, got '%s'", transType)
	}

	var sysCatID string
	if err := upgradedDB.QueryRow("SELECT value FROM system_meta WHERE key = 'system_category_transfer_id'").Scan(&sysCatID); err != nil {
		t.Fatalf("failed to query system_category_transfer_id: %v", err)
	}
	if sysCatID != "1" {
		t.Errorf("expected system_category_transfer_id to match user's category (1), got %s", sysCatID)
	}
}
