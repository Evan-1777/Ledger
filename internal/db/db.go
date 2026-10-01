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
	`

	if _, err := db.Exec(schema); err != nil {
		return fmt.Errorf("failed to create tables: %w", err)
	}

	// Seed payment methods
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
		_, err := db.Exec("INSERT OR IGNORE INTO payment_methods (name, sort_order) VALUES (?, ?)", pm.name, pm.sortOrder)
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
		_, err := db.Exec("INSERT OR IGNORE INTO categories (name, sort_order) VALUES (?, ?)", cat.name, cat.sortOrder)
		if err != nil {
			return fmt.Errorf("failed to seed category %s: %w", cat.name, err)
		}

		var categoryID int64
		err = db.QueryRow("SELECT id FROM categories WHERE name = ?", cat.name).Scan(&categoryID)
		if err != nil {
			return fmt.Errorf("failed to get category id for %s: %w", cat.name, err)
		}

		for tagOrder, tagName := range cat.tags {
			_, err := db.Exec("INSERT OR IGNORE INTO tags (category_id, name, sort_order) VALUES (?, ?, ?)", categoryID, tagName, tagOrder+1)
			if err != nil {
				return fmt.Errorf("failed to seed tag %s: %w", tagName, err)
			}
		}
	}

	return nil
}
