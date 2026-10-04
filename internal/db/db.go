package db

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"strconv"

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

	dsn := fmt.Sprintf("file:%s?_pragma=foreign_keys(1)&_pragma=busy_timeout(5000)&_pragma=synchronous(NORMAL)", dbPath)
	database, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	// ponytail: 10 connections with WAL mode and 5s busy timeout balances concurrency and safety
	database.SetMaxOpenConns(10)
	database.SetMaxIdleConns(5)

	// PRAGMA journal_mode is persistent in the database file header once set
	if _, err := database.Exec("PRAGMA journal_mode = WAL;"); err != nil {
		_ = database.Close()
		return nil, fmt.Errorf("failed to execute pragma journal_mode: %w", err)
	}

	if err := database.Ping(); err != nil {
		_ = database.Close()
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	if err := migrateAndSeed(database); err != nil {
		_ = database.Close()
		return nil, fmt.Errorf("failed to migrate and seed database: %w", err)
	}

	return database, nil
}

func migrateAndSeed(db *sql.DB) error {
	schema := `
	CREATE TABLE IF NOT EXISTS categories (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		name TEXT UNIQUE NOT NULL,
		sort_order INTEGER DEFAULT 0,
		type TEXT NOT NULL DEFAULT 'expense',
		created_at TEXT DEFAULT CURRENT_TIMESTAMP
	);

	CREATE TABLE IF NOT EXISTS tags (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
		name TEXT NOT NULL,
		sort_order INTEGER DEFAULT 0,
		created_at TEXT DEFAULT CURRENT_TIMESTAMP,
		UNIQUE(category_id, name)
	);

	CREATE TABLE IF NOT EXISTS payment_methods (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		name TEXT UNIQUE NOT NULL,
		sort_order INTEGER DEFAULT 0,
		type TEXT NOT NULL DEFAULT 'asset',
		initial_balance_cents INTEGER NOT NULL DEFAULT 0,
		credit_limit_cents INTEGER NOT NULL DEFAULT 0,
		created_at TEXT DEFAULT CURRENT_TIMESTAMP
	);

	CREATE TABLE IF NOT EXISTS transactions (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		amount_cents INTEGER NOT NULL,
		description TEXT NOT NULL,
		payment_method_id INTEGER NOT NULL REFERENCES payment_methods(id) ON DELETE RESTRICT,
		category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
		tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE RESTRICT,
		transacted_at TEXT NOT NULL,
		type TEXT NOT NULL DEFAULT 'expense',
		source_payment_method_id INTEGER DEFAULT NULL REFERENCES payment_methods(id) ON DELETE RESTRICT,
		created_at TEXT DEFAULT CURRENT_TIMESTAMP
	);

	CREATE INDEX IF NOT EXISTS idx_transactions_transacted_at ON transactions(transacted_at);
	CREATE INDEX IF NOT EXISTS idx_transactions_category_id ON transactions(category_id);
	CREATE INDEX IF NOT EXISTS idx_transactions_payment_method_id ON transactions(payment_method_id);

	CREATE TABLE IF NOT EXISTS system_meta (
		key TEXT PRIMARY KEY,
		value TEXT NOT NULL
	);
	`

	if _, err := db.Exec(schema); err != nil {
		return fmt.Errorf("failed to create tables: %w", err)
	}

	tx, err := db.Begin()
	if err != nil {
		return fmt.Errorf("failed to begin migration transaction: %w", err)
	}
	defer tx.Rollback()

	// Hot migration: probe and add columns if missing (always executed before seed check)
	if err := migrateCategoriesColumns(tx); err != nil {
		return fmt.Errorf("failed to migrate categories columns: %w", err)
	}
	if err := migratePaymentMethodsColumns(tx); err != nil {
		return fmt.Errorf("failed to migrate payment methods columns: %w", err)
	}
	if err := migrateTransactionsColumns(tx); err != nil {
		return fmt.Errorf("failed to migrate transactions columns: %w", err)
	}
	// Check if seed has already been initialized
	var seedInit string
	err = tx.QueryRow("SELECT value FROM system_meta WHERE key = 'seed_initialized'").Scan(&seedInit)
	if err == nil && seedInit == "true" {
		if err := ensureSystemRepaymentCategory(tx); err != nil {
			return fmt.Errorf("failed to ensure system repayment category: %w", err)
		}
		if err := ensureSystemTransferCategory(tx); err != nil {
			return fmt.Errorf("failed to ensure system transfer category: %w", err)
		}
		return tx.Commit()
	}

	// Check whether this is an existing database from before system_meta existed
	var pmCount, catCount, txCount int
	if err := tx.QueryRow("SELECT COUNT(*) FROM payment_methods").Scan(&pmCount); err != nil {
		return fmt.Errorf("failed to check payment_methods count: %w", err)
	}
	if err := tx.QueryRow("SELECT COUNT(*) FROM categories").Scan(&catCount); err != nil {
		return fmt.Errorf("failed to check categories count: %w", err)
	}
	if err := tx.QueryRow("SELECT COUNT(*) FROM transactions").Scan(&txCount); err != nil {
		return fmt.Errorf("failed to check transactions count: %w", err)
	}

	// Existing database upgrade: already has data, do not inject seeds, just mark initialized and ensure repayment & transfer categories
	if pmCount > 0 || catCount > 0 || txCount > 0 {
		if err := ensureSystemRepaymentCategory(tx); err != nil {
			return fmt.Errorf("failed to ensure system repayment category on existing db: %w", err)
		}
		if err := ensureSystemTransferCategory(tx); err != nil {
			return fmt.Errorf("failed to ensure system transfer category on existing db: %w", err)
		}
		if _, err := tx.Exec("INSERT OR REPLACE INTO system_meta (key, value) VALUES ('seed_initialized', 'true')"); err != nil {
			return fmt.Errorf("failed to mark seed_initialized on existing db: %w", err)
		}
		return tx.Commit()
	}

	// Fresh installation: Seed default payment methods
	defaultMethods := []struct {
		name                string
		sortOrder           int
		channelType         string
		initialBalanceCents int64
		creditLimitCents    int64
	}{
		{"微信支付", 1, "asset", 0, 0},
		{"支付宝", 2, "asset", 0, 0},
		{"招商银行卡", 3, "asset", 0, 0},
		{"现金钞票", 4, "asset", 0, 0},
		{"招商信用卡", 5, "liability", 0, 2000000},
	}

	for _, pm := range defaultMethods {
		_, err := tx.Exec("INSERT OR IGNORE INTO payment_methods (name, sort_order, type, initial_balance_cents, credit_limit_cents) VALUES (?, ?, ?, ?, ?)",
			pm.name, pm.sortOrder, pm.channelType, pm.initialBalanceCents, pm.creditLimitCents)
		if err != nil {
			return fmt.Errorf("failed to seed payment method %s: %w", pm.name, err)
		}
	}

	// Seed categories and tags
	defaultCategories := []struct {
		name      string
		sortOrder int
		catType   string
		tags      []string
	}{
		{"餐饮美食", 1, "expense", []string{"午餐", "晚餐", "咖啡奶茶", "超市买菜"}},
		{"交通出行", 2, "expense", []string{"地铁", "打车出租", "公交"}},
		{"居家生活", 3, "expense", []string{"房租月供", "物业水暖", "日用百货"}},
		{"休闲娱乐", 4, "expense", []string{"电影演出", "数字游戏", "运动健身"}},
		{"职业收入", 5, "income", []string{"主业工资", "年终奖金", "兼职报酬"}},
	}

	for _, cat := range defaultCategories {
		_, err := tx.Exec("INSERT OR IGNORE INTO categories (name, sort_order, type) VALUES (?, ?, ?)", cat.name, cat.sortOrder, cat.catType)
		if err != nil {
			return fmt.Errorf("failed to seed category %s: %w", cat.name, err)
		}

		var categoryID int64
		err = tx.QueryRow("SELECT id FROM categories WHERE name = ?", cat.name).Scan(&categoryID)
		if err != nil {
			return fmt.Errorf("failed to get category id for %s: %w", cat.name, err)
		}

		for tagOrder, tagName := range cat.tags {
			_, err := tx.Exec("INSERT OR IGNORE INTO tags (category_id, name, sort_order) VALUES (?, ?, ?)", categoryID, tagName, tagOrder+1)
			if err != nil {
				return fmt.Errorf("failed to seed tag %s: %w", tagName, err)
			}
		}
	}

	if err := ensureSystemRepaymentCategory(tx); err != nil {
		return fmt.Errorf("failed to ensure system repayment category: %w", err)
	}
	if err := ensureSystemTransferCategory(tx); err != nil {
		return fmt.Errorf("failed to ensure system transfer category: %w", err)
	}

	if _, err := tx.Exec("INSERT OR REPLACE INTO system_meta (key, value) VALUES ('seed_initialized', 'true')"); err != nil {
		return fmt.Errorf("failed to mark seed_initialized: %w", err)
	}

	return tx.Commit()
}

func migrateCategoriesColumns(tx *sql.Tx) error {
	rows, err := tx.Query("PRAGMA table_info(categories)")
	if err != nil {
		return fmt.Errorf("failed to inspect categories table info: %w", err)
	}
	defer rows.Close()

	hasType := false
	for rows.Next() {
		var cid int
		var name, colType string
		var notNull, pk int
		var dfltValue sql.NullString
		if err := rows.Scan(&cid, &name, &colType, &notNull, &dfltValue, &pk); err != nil {
			return fmt.Errorf("failed to scan table_info: %w", err)
		}
		if name == "type" {
			hasType = true
		}
	}
	if err := rows.Err(); err != nil {
		return fmt.Errorf("error iterating table_info: %w", err)
	}

	if !hasType {
		if _, err := tx.Exec("ALTER TABLE categories ADD COLUMN type TEXT NOT NULL DEFAULT 'expense'"); err != nil {
			return fmt.Errorf("failed to add column type to categories: %w", err)
		}
	}

	// Atomic backfill for known category types
	if _, err := tx.Exec("UPDATE categories SET type = 'income' WHERE name = '职业收入' AND type != 'income'"); err != nil {
		return fmt.Errorf("failed to backfill 职业收入 type: %w", err)
	}
	if _, err := tx.Exec("UPDATE categories SET type = 'system' WHERE name = '债务偿还' AND type != 'system'"); err != nil {
		return fmt.Errorf("failed to backfill 债务偿还 type: %w", err)
	}

	return nil
}

func migratePaymentMethodsColumns(tx *sql.Tx) error {
	rows, err := tx.Query("PRAGMA table_info(payment_methods)")
	if err != nil {
		return fmt.Errorf("failed to inspect payment_methods table info: %w", err)
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
			return fmt.Errorf("failed to scan table_info: %w", err)
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
	if err := rows.Err(); err != nil {
		return fmt.Errorf("error iterating table_info: %w", err)
	}

	if !hasType {
		if _, err := tx.Exec("ALTER TABLE payment_methods ADD COLUMN type TEXT NOT NULL DEFAULT 'asset'"); err != nil {
			return fmt.Errorf("failed to add column type: %w", err)
		}
	}
	if !hasInitialBalance {
		if _, err := tx.Exec("ALTER TABLE payment_methods ADD COLUMN initial_balance_cents INTEGER NOT NULL DEFAULT 0"); err != nil {
			return fmt.Errorf("failed to add column initial_balance_cents: %w", err)
		}
	}
	if !hasCreditLimit {
		if _, err := tx.Exec("ALTER TABLE payment_methods ADD COLUMN credit_limit_cents INTEGER NOT NULL DEFAULT 0"); err != nil {
			return fmt.Errorf("failed to add column credit_limit_cents: %w", err)
		}
	}

	return nil
}

func migrateTransactionsColumns(tx *sql.Tx) error {
	rows, err := tx.Query("PRAGMA table_info(transactions)")
	if err != nil {
		return fmt.Errorf("failed to inspect transactions table info: %w", err)
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
			return fmt.Errorf("failed to scan transactions table_info: %w", err)
		}
		switch name {
		case "type":
			hasType = true
		case "source_payment_method_id":
			hasSourcePM = true
		}
	}
	if err := rows.Err(); err != nil {
		return fmt.Errorf("error iterating transactions table_info: %w", err)
	}

	if !hasType {
		if _, err := tx.Exec("ALTER TABLE transactions ADD COLUMN type TEXT NOT NULL DEFAULT 'expense'"); err != nil {
			return fmt.Errorf("failed to add column type to transactions: %w", err)
		}
		if _, err := tx.Exec("UPDATE transactions SET type = CASE WHEN amount_cents < 0 THEN 'expense' ELSE 'income' END"); err != nil {
			return fmt.Errorf("failed to backfill transaction types: %w", err)
		}
	}
	if !hasSourcePM {
		if _, err := tx.Exec("ALTER TABLE transactions ADD COLUMN source_payment_method_id INTEGER DEFAULT NULL REFERENCES payment_methods(id) ON DELETE RESTRICT"); err != nil {
			return fmt.Errorf("failed to add column source_payment_method_id to transactions: %w", err)
		}
	}

	return nil
}

func ensureSystemRepaymentCategory(tx *sql.Tx) error {
	if _, err := tx.Exec("INSERT OR IGNORE INTO categories (name, sort_order, type) VALUES ('债务偿还', 999, 'system')"); err != nil {
		return fmt.Errorf("failed to ensure system repayment category: %w", err)
	}
	var catID int64
	if err := tx.QueryRow("SELECT id FROM categories WHERE name = '债务偿还'").Scan(&catID); err != nil {
		return fmt.Errorf("failed to get system repayment category id: %w", err)
	}

	if _, err := tx.Exec("INSERT OR IGNORE INTO tags (category_id, name, sort_order) VALUES (?, '负债还款', 1)", catID); err != nil {
		return fmt.Errorf("failed to ensure system repayment tag: %w", err)
	}
	var tagID int64
	if err := tx.QueryRow("SELECT id FROM tags WHERE category_id = ? AND name = '负债还款'", catID).Scan(&tagID); err != nil {
		return fmt.Errorf("failed to get system repayment tag id: %w", err)
	}

	if _, err := tx.Exec("INSERT OR REPLACE INTO system_meta (key, value) VALUES ('system_category_repayment_id', ?)", strconv.FormatInt(catID, 10)); err != nil {
		return fmt.Errorf("failed to persist system_category_repayment_id: %w", err)
	}
	if _, err := tx.Exec("INSERT OR REPLACE INTO system_meta (key, value) VALUES ('system_tag_repayment_id', ?)", strconv.FormatInt(tagID, 10)); err != nil {
		return fmt.Errorf("failed to persist system_tag_repayment_id: %w", err)
	}

	return nil
}

func ensureSystemTransferCategory(tx *sql.Tx) error {
	if _, err := tx.Exec("INSERT OR IGNORE INTO categories (name, sort_order, type) VALUES ('账户转账', 998, 'system')"); err != nil {
		return fmt.Errorf("failed to ensure system transfer category: %w", err)
	}
	var catID int64
	if err := tx.QueryRow("SELECT id FROM categories WHERE name = '账户转账'").Scan(&catID); err != nil {
		return fmt.Errorf("failed to get system transfer category id: %w", err)
	}

	if _, err := tx.Exec("INSERT OR IGNORE INTO tags (category_id, name, sort_order) VALUES (?, '资金互转', 1)", catID); err != nil {
		return fmt.Errorf("failed to ensure system transfer tag: %w", err)
	}
	var tagID int64
	if err := tx.QueryRow("SELECT id FROM tags WHERE category_id = ? AND name = '资金互转'", catID).Scan(&tagID); err != nil {
		return fmt.Errorf("failed to get system transfer tag id: %w", err)
	}

	if _, err := tx.Exec("INSERT OR REPLACE INTO system_meta (key, value) VALUES ('system_category_transfer_id', ?)", strconv.FormatInt(catID, 10)); err != nil {
		return fmt.Errorf("failed to persist system_category_transfer_id: %w", err)
	}
	if _, err := tx.Exec("INSERT OR REPLACE INTO system_meta (key, value) VALUES ('system_tag_transfer_id', ?)", strconv.FormatInt(tagID, 10)); err != nil {
		return fmt.Errorf("failed to persist system_tag_transfer_id: %w", err)
	}

	return nil
}

