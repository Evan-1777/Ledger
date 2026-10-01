package server

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"testing/fstest"
	"time"

	"ledger/internal/db"

	_ "modernc.org/sqlite"
)

func TestHandleHealth(t *testing.T) {
	s := New(nil, nil, "admin123", "secret123")

	req := httptest.NewRequest("GET", "/api/health", nil)
	rec := httptest.NewRecorder()

	s.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", rec.Code)
	}

	var resp HealthResponse
	if err := json.NewDecoder(rec.Body).Decode(&resp); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}

	if resp.Status != "ok" {
		t.Errorf("expected status 'ok', got '%s'", resp.Status)
	}

	// Test disconnected DB returns degraded status and 503
	closedDB, _ := sql.Open("sqlite", ":memory:")
	_ = closedDB.Close()
	sDegraded := New(closedDB, nil, "admin123", "secret123")

	reqDegraded := httptest.NewRequest("GET", "/api/health", nil)
	recDegraded := httptest.NewRecorder()
	sDegraded.ServeHTTP(recDegraded, reqDegraded)

	if recDegraded.Code != http.StatusServiceUnavailable {
		t.Errorf("expected status 503 for degraded health, got %d", recDegraded.Code)
	}

	var respDegraded HealthResponse
	if err := json.NewDecoder(recDegraded.Body).Decode(&respDegraded); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if respDegraded.Status != "degraded" || respDegraded.DB != "disconnected" {
		t.Errorf("expected status 'degraded' and db 'disconnected', got status '%s' and db '%s'", respDegraded.Status, respDegraded.DB)
	}
}

func TestHandleSPA(t *testing.T) {
	mockFS := fstest.MapFS{
		"index.html": &fstest.MapFile{
			Data: []byte("<html><body>Ledger App</body></html>"),
		},
		"assets/style.css": &fstest.MapFile{
			Data: []byte("body { margin: 0; }"),
		},
	}

	s := New(nil, mockFS, "admin123", "secret123")

	// Test root serves index.html
	reqRoot := httptest.NewRequest("GET", "/", nil)
	recRoot := httptest.NewRecorder()
	s.ServeHTTP(recRoot, reqRoot)
	if recRoot.Code != http.StatusOK {
		t.Errorf("expected 200 for /, got %d", recRoot.Code)
	}
	if recRoot.Body.String() != "<html><body>Ledger App</body></html>" {
		t.Errorf("unexpected body for /: %s", recRoot.Body.String())
	}

	// Test static asset
	reqAsset := httptest.NewRequest("GET", "/assets/style.css", nil)
	recAsset := httptest.NewRecorder()
	s.ServeHTTP(recAsset, reqAsset)
	if recAsset.Code != http.StatusOK {
		t.Errorf("expected 200 for /assets/style.css, got %d", recAsset.Code)
	}
	if recAsset.Body.String() != "body { margin: 0; }" {
		t.Errorf("unexpected body for asset: %s", recAsset.Body.String())
	}

	// Test SPA client-side route fallback to index.html
	reqRoute := httptest.NewRequest("GET", "/dashboard/transactions", nil)
	recRoute := httptest.NewRecorder()
	s.ServeHTTP(recRoute, reqRoute)
	if recRoute.Code != http.StatusOK {
		t.Errorf("expected 200 for SPA route, got %d", recRoute.Code)
	}
	if recRoute.Body.String() != "<html><body>Ledger App</body></html>" {
		t.Errorf("unexpected body for SPA route: %s", recRoute.Body.String())
	}

	// Test API 404 does NOT fallback to index.html
	reqAPI := httptest.NewRequest("GET", "/api/not-found", nil)
	recAPI := httptest.NewRecorder()
	s.ServeHTTP(recAPI, reqAPI)
	if recAPI.Code != http.StatusNotFound {
		t.Errorf("expected 404 for unknown /api/ route, got %d", recAPI.Code)
	}
}

func TestAuth(t *testing.T) {
	s := New(nil, nil, "supersecret", "testtokensecret")

	// Test login with wrong password
	start := time.Now()
	loginBody := strings.NewReader(`{"password":"wrongpassword"}`)
	reqWrong := httptest.NewRequest("POST", "/api/auth/login", loginBody)
	recWrong := httptest.NewRecorder()
	s.ServeHTTP(recWrong, reqWrong)

	duration := time.Since(start)
	if recWrong.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 for wrong password, got %d", recWrong.Code)
	}
	if duration < 450*time.Millisecond {
		t.Errorf("expected anti-bruteforce delay >= 450ms, got %v", duration)
	}

	// Test login with correct password
	loginCorrect := strings.NewReader(`{"password":"supersecret"}`)
	reqCorrect := httptest.NewRequest("POST", "/api/auth/login", loginCorrect)
	recCorrect := httptest.NewRecorder()
	s.ServeHTTP(recCorrect, reqCorrect)

	if recCorrect.Code != http.StatusOK {
		t.Fatalf("expected 200 for correct login, got %d", recCorrect.Code)
	}

	var loginResp LoginResponse
	if err := json.NewDecoder(recCorrect.Body).Decode(&loginResp); err != nil {
		t.Fatalf("failed to decode login response: %v", err)
	}
	if loginResp.Token == "" {
		t.Fatalf("expected non-empty token")
	}

	// Test auth check with valid token
	reqCheck := httptest.NewRequest("GET", "/api/auth/check", nil)
	reqCheck.Header.Set("Authorization", "Bearer "+loginResp.Token)
	recCheck := httptest.NewRecorder()
	s.ServeHTTP(recCheck, reqCheck)

	if recCheck.Code != http.StatusOK {
		t.Errorf("expected 200 for valid token auth check, got %d", recCheck.Code)
	}

	// Test auth check with invalid token
	reqInvalid := httptest.NewRequest("GET", "/api/auth/check", nil)
	reqInvalid.Header.Set("Authorization", "Bearer invalid.token.value")
	recInvalid := httptest.NewRecorder()
	s.ServeHTTP(recInvalid, reqInvalid)

	if recInvalid.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 for invalid token auth check, got %d", recInvalid.Code)
	}

	// Test auth check with no header
	reqNoAuth := httptest.NewRequest("GET", "/api/auth/check", nil)
	recNoAuth := httptest.NewRecorder()
	s.ServeHTTP(recNoAuth, reqNoAuth)

	if recNoAuth.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 for missing token, got %d", recNoAuth.Code)
	}
}

func setupTestServer(t *testing.T) (*Server, string, func()) {
	t.Helper()
	tempDir, err := os.MkdirTemp("", "ledger-server-test-*")
	if err != nil {
		t.Fatalf("failed to create temp dir: %v", err)
	}

	dbPath := filepath.Join(tempDir, "test.db")
	database, err := db.InitDB(dbPath)
	if err != nil {
		os.RemoveAll(tempDir)
		t.Fatalf("InitDB failed: %v", err)
	}

	s := New(database, nil, "admin123", "secret123")
	cleanup := func() {
		_ = database.Close()
		_ = os.RemoveAll(tempDir)
	}

	// Login to get token
	loginReq := httptest.NewRequest("POST", "/api/auth/login", strings.NewReader(`{"password":"admin123"}`))
	rec := httptest.NewRecorder()
	s.ServeHTTP(rec, loginReq)
	if rec.Code != http.StatusOK {
		cleanup()
		t.Fatalf("login failed: %d", rec.Code)
	}
	var loginResp LoginResponse
	_ = json.NewDecoder(rec.Body).Decode(&loginResp)

	return s, loginResp.Token, cleanup
}

func TestSettingsCRUDAndGuards(t *testing.T) {
	s, token, cleanup := setupTestServer(t)
	defer cleanup()

	authHeader := "Bearer " + token

	// 1. Create a custom payment method
	pmBody := strings.NewReader(`{"name":"测试信用卡","sort_order":10}`)
	req := httptest.NewRequest("POST", "/api/payment-methods", pmBody)
	req.Header.Set("Authorization", authHeader)
	rec := httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("failed to create payment method: %d", rec.Code)
	}
	var pm PaymentMethod
	_ = json.NewDecoder(rec.Body).Decode(&pm)

	// 2. Create a custom category
	catBody := strings.NewReader(`{"name":"投资理财","sort_order":10}`)
	req = httptest.NewRequest("POST", "/api/categories", catBody)
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("failed to create category: %d", rec.Code)
	}
	var cat Category
	_ = json.NewDecoder(rec.Body).Decode(&cat)

	// 3. Create a tag under this category
	tagJSON, _ := json.Marshal(map[string]any{"category_id": cat.ID, "name": "基金定投", "sort_order": 1})
	req = httptest.NewRequest("POST", "/api/tags", strings.NewReader(string(tagJSON)))
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("failed to create tag: %d", rec.Code)
	}
	var tag Tag
	_ = json.NewDecoder(rec.Body).Decode(&tag)

	// 4. Create a transaction referencing them
	txJSON, _ := json.Marshal(map[string]any{
		"amount":            -500.0,
		"description":       "定投买入",
		"payment_method_id": pm.ID,
		"category_id":       cat.ID,
		"tag_id":            tag.ID,
	})
	req = httptest.NewRequest("POST", "/api/transactions", strings.NewReader(string(txJSON)))
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("failed to create transaction: %d, body: %s", rec.Code, rec.Body.String())
	}
	var txItem Transaction
	_ = json.NewDecoder(rec.Body).Decode(&txItem)

	// 5. Test 409 guard: Delete payment method while referenced
	req = httptest.NewRequest("DELETE", "/api/payment-methods/"+strings.TrimSpace(string(rune(pm.ID+'0'))), nil)
	// format properly
	req = httptest.NewRequest("DELETE", strings.ReplaceAll("/api/payment-methods/ID", "ID", strings.TrimSpace(jsonNumber(pm.ID))), nil)
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusConflict {
		t.Errorf("expected 409 for referenced payment method deletion, got %d", rec.Code)
	}

	// 6. Test 409 guard: Delete tag while referenced
	req = httptest.NewRequest("DELETE", strings.ReplaceAll("/api/tags/ID", "ID", strings.TrimSpace(jsonNumber(tag.ID))), nil)
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusConflict {
		t.Errorf("expected 409 for referenced tag deletion, got %d", rec.Code)
	}

	// 7. Test 409 guard: Delete category while referenced
	req = httptest.NewRequest("DELETE", strings.ReplaceAll("/api/categories/ID", "ID", strings.TrimSpace(jsonNumber(cat.ID))), nil)
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusConflict {
		t.Errorf("expected 409 for referenced category deletion, got %d", rec.Code)
	}

	// 8. Delete transaction
	req = httptest.NewRequest("DELETE", strings.ReplaceAll("/api/transactions/ID", "ID", strings.TrimSpace(jsonNumber(txItem.ID))), nil)
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 for transaction deletion, got %d", rec.Code)
	}

	// 9. Now delete tag -> 200 OK
	req = httptest.NewRequest("DELETE", strings.ReplaceAll("/api/tags/ID", "ID", strings.TrimSpace(jsonNumber(tag.ID))), nil)
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Errorf("expected 200 for unreferenced tag deletion, got %d", rec.Code)
	}

	// 10. Delete category -> 200 OK
	req = httptest.NewRequest("DELETE", strings.ReplaceAll("/api/categories/ID", "ID", strings.TrimSpace(jsonNumber(cat.ID))), nil)
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Errorf("expected 200 for unreferenced category deletion, got %d", rec.Code)
	}

	// 11. Delete payment method -> 200 OK
	req = httptest.NewRequest("DELETE", strings.ReplaceAll("/api/payment-methods/ID", "ID", strings.TrimSpace(jsonNumber(pm.ID))), nil)
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Errorf("expected 200 for unreferenced payment method deletion, got %d", rec.Code)
	}
}

func TestTransactionsCRUD(t *testing.T) {
	s, token, cleanup := setupTestServer(t)
	defer cleanup()

	authHeader := "Bearer " + token

	// 1. Invalid input: tag does not belong to category
	invalidTx, _ := json.Marshal(map[string]any{
		"amount":            -25.5,
		"description":       "早餐",
		"payment_method_id": 1,
		"category_id":       1, // 餐饮美食
		"tag_id":            5, // 地铁 (belongs to 交通出行 cat 2)
	})
	req := httptest.NewRequest("POST", "/api/transactions", strings.NewReader(string(invalidTx)))
	req.Header.Set("Authorization", authHeader)
	rec := httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for mismatched tag and category, got %d", rec.Code)
	}

	// 2. Valid create: amount = -25.50 (expense)
	validTx, _ := json.Marshal(map[string]any{
		"amount":            -25.5,
		"description":       "午餐快餐",
		"payment_method_id": 1,
		"category_id":       1,
		"tag_id":            1,
		"transacted_at":     "2026-10-01T12:30:00Z",
	})
	req = httptest.NewRequest("POST", "/api/transactions", strings.NewReader(string(validTx)))
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 for valid transaction create, got %d", rec.Code)
	}

	var createdTx Transaction
	_ = json.NewDecoder(rec.Body).Decode(&createdTx)
	if createdTx.AmountCents != -2550 {
		t.Errorf("expected amount_cents -2550, got %d", createdTx.AmountCents)
	}
	if createdTx.Amount != -25.5 {
		t.Errorf("expected amount -25.5, got %v", createdTx.Amount)
	}

	// 3. Update transaction: change amount to -30.00
	updateTx, _ := json.Marshal(map[string]any{
		"amount":            -30.0,
		"description":       "午餐大份",
		"payment_method_id": 1,
		"category_id":       1,
		"tag_id":            1,
		"transacted_at":     "2026-10-01T12:30:00Z",
	})
	req = httptest.NewRequest("PUT", strings.ReplaceAll("/api/transactions/ID", "ID", strings.TrimSpace(jsonNumber(createdTx.ID))), strings.NewReader(string(updateTx)))
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 for transaction update, got %d", rec.Code)
	}

	var updatedTx Transaction
	_ = json.NewDecoder(rec.Body).Decode(&updatedTx)
	if updatedTx.AmountCents != -3000 {
		t.Errorf("expected updated amount_cents -3000, got %d", updatedTx.AmountCents)
	}
	if updatedTx.Description != "午餐大份" {
		t.Errorf("expected updated description '午餐大份', got %s", updatedTx.Description)
	}

	// 4. List transactions
	req = httptest.NewRequest("GET", "/api/transactions", nil)
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 for list transactions, got %d", rec.Code)
	}
	var list []Transaction
	_ = json.NewDecoder(rec.Body).Decode(&list)
	if len(list) != 1 {
		t.Fatalf("expected 1 transaction in list, got %d", len(list))
	}
	if list[0].CategoryName != "餐饮美食" {
		t.Errorf("expected CategoryName '餐饮美食', got '%s'", list[0].CategoryName)
	}
}

func TestStatsSummary(t *testing.T) {
	s, token, cleanup := setupTestServer(t)
	defer cleanup()

	authHeader := "Bearer " + token

	now := time.Now()
	// Create income transaction this month
	txIncome, _ := json.Marshal(map[string]any{
		"amount":            8000.0,
		"description":       "工资",
		"payment_method_id": 3,
		"category_id":       5,
		"tag_id":            14,
		"transacted_at":     now.Format(time.RFC3339),
	})
	req := httptest.NewRequest("POST", "/api/transactions", strings.NewReader(string(txIncome)))
	req.Header.Set("Authorization", authHeader)
	rec := httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("failed to create income: %d", rec.Code)
	}

	// Create expense transaction this week
	txExpense, _ := json.Marshal(map[string]any{
		"amount":            -150.0,
		"description":       "聚餐",
		"payment_method_id": 1,
		"category_id":       1,
		"tag_id":            2,
		"transacted_at":     now.Format(time.RFC3339),
	})
	req = httptest.NewRequest("POST", "/api/transactions", strings.NewReader(string(txExpense)))
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("failed to create expense: %d", rec.Code)
	}

	// Get stats summary
	req = httptest.NewRequest("GET", "/api/stats/summary", nil)
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 for stats summary, got %d", rec.Code)
	}

	var stats StatsSummaryResponse
	if err := json.NewDecoder(rec.Body).Decode(&stats); err != nil {
		t.Fatalf("failed to decode stats: %v", err)
	}

	if stats.WeekExpense != 150.0 {
		t.Errorf("expected week_expense 150.0, got %v", stats.WeekExpense)
	}
	if stats.MonthExpense != 150.0 {
		t.Errorf("expected month_expense 150.0, got %v", stats.MonthExpense)
	}
	if stats.MonthIncome != 8000.0 {
		t.Errorf("expected month_income 8000.0, got %v", stats.MonthIncome)
	}
	if stats.MonthBalance != 7850.0 {
		t.Errorf("expected month_balance 7850.0, got %v", stats.MonthBalance)
	}
	if stats.SavingsRate <= 0 {
		t.Errorf("expected positive savings_rate, got %v", stats.SavingsRate)
	}
	if len(stats.CategoryDistribution) != 1 {
		t.Errorf("expected 1 category in distribution, got %d", len(stats.CategoryDistribution))
	}
	if len(stats.MonthlyTrends) != 6 {
		t.Errorf("expected 6 monthly trend records, got %d", len(stats.MonthlyTrends))
	}
}

func jsonNumber(id int64) string {
	b, _ := json.Marshal(id)
	return string(b)
}
