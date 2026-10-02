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

	// Check if seed has already been initialized
	var seedInit string
	err = tx.QueryRow("SELECT value FROM system_meta WHERE key = 'seed_initialized'").Scan(&seedInit)
	if err == nil && seedInit == "true" {
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

	// Existing database upgrade: already has data, do not inject seeds, just mark initialized
	if pmCount > 0 || catCount > 0 || txCount > 0 {
		if _, err := tx.Exec("INSERT OR REPLACE INTO system_meta (key, value) VALUES ('seed_initialized', 'true')"); err != nil {
			return fmt.Errorf("failed to mark seed_initialized on existing db: %w", err)
		}
		return tx.Commit()
	}

	// Fresh installation: Seed default payment methods
	defaultMethods := []struct {
		name      string
		sortOrder int
	}{
		{"微信支付", 1},
		{"支付宝", 2},
		{"招商银行卡", 3},
		{"现金钞票", 4},
	}

	for _, pm := range defaultMethods {
		_, err := tx.Exec("INSERT OR IGNORE INTO payment_methods (name, sort_order) VALUES (?, ?)", pm.name, pm.sortOrder)
		if err != nil {
			return fmt.Errorf("failed to seed payment method %s: %w", pm.name, err)
		}
	}

	// Seed categories and tags
	defaultCategories := []struct {
		name      string
		sortOrder int
		tags      []string
	}{
		{"餐饮美食", 1, []string{"午餐", "晚餐", "咖啡奶茶", "超市买菜"}},
		{"交通出行", 2, []string{"地铁", "打车出租", "公交"}},
		{"居家生活", 3, []string{"房租月供", "物业水暖", "日用百货"}},
		{"休闲娱乐", 4, []string{"电影演出", "数字游戏", "运动健身"}},
		{"职业收入", 5, []string{"主业工资", "年终奖金", "兼职报酬"}},
	}

	for _, cat := range defaultCategories {
		_, err := tx.Exec("INSERT OR IGNORE INTO categories (name, sort_order) VALUES (?, ?)", cat.name, cat.sortOrder)
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

	if _, err := tx.Exec("INSERT OR REPLACE INTO system_meta (key, value) VALUES ('seed_initialized', 'true')"); err != nil {
		return fmt.Errorf("failed to mark seed_initialized: %w", err)
	}

	return tx.Commit()
}
