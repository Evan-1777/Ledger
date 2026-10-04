package server

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
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

func TestErrorHandlingAndStatsFailFast(t *testing.T) {
	s, token, cleanup := setupTestServer(t)
	defer cleanup()

	authHeader := "Bearer " + token

	// 1. Duplicate payment method returns 400
	pmBody := strings.NewReader(`{"name":"微信支付","sort_order":1}`) // "微信支付" already exists from seed
	req := httptest.NewRequest("POST", "/api/payment-methods", pmBody)
	req.Header.Set("Authorization", authHeader)
	rec := httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for duplicate payment method, got %d", rec.Code)
	}

	// 2. Duplicate category returns 400
	catBody := strings.NewReader(`{"name":"餐饮美食","sort_order":1}`) // "餐饮美食" already exists from seed
	req = httptest.NewRequest("POST", "/api/categories", catBody)
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for duplicate category, got %d", rec.Code)
	}

	// 3. Now simulate DB failure: close underlying DB connection
	_ = s.db.Close()

	// 3a. Stats summary on broken DB MUST return 500 (not fake 200 with 0s)
	reqStats := httptest.NewRequest("GET", "/api/stats/summary", nil)
	reqStats.Header.Set("Authorization", authHeader)
	recStats := httptest.NewRecorder()
	s.ServeHTTP(recStats, reqStats)
	if recStats.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500 for stats summary with closed DB, got %d", recStats.Code)
	}

	// 3b. Create payment method on broken DB MUST return 500 (not 400 "already exists")
	pmNew := strings.NewReader(`{"name":"全新渠道","sort_order":99}`)
	reqBrokenPM := httptest.NewRequest("POST", "/api/payment-methods", pmNew)
	reqBrokenPM.Header.Set("Authorization", authHeader)
	recBrokenPM := httptest.NewRecorder()
	s.ServeHTTP(recBrokenPM, reqBrokenPM)
	if recBrokenPM.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500 for payment method creation on broken DB, got %d", recBrokenPM.Code)
	}

	// 3c. Create transaction on broken DB MUST return 500 (not 400 "payment method does not exist")
	txJSON, _ := json.Marshal(map[string]any{
		"amount":            -10.0,
		"description":       "测试",
		"payment_method_id": 1,
		"category_id":       1,
		"tag_id":            1,
	})
	reqBrokenTx := httptest.NewRequest("POST", "/api/transactions", strings.NewReader(string(txJSON)))
	reqBrokenTx.Header.Set("Authorization", authHeader)
	recBrokenTx := httptest.NewRecorder()
	s.ServeHTTP(recBrokenTx, reqBrokenTx)
	if recBrokenTx.Code != http.StatusInternalServerError {
		t.Fatalf("expected 500 for transaction validation on broken DB, got %d", recBrokenTx.Code)
	}
}

func TestPaymentMethodsAssetAndLiability(t *testing.T) {
	s, token, cleanup := setupTestServer(t)
	defer cleanup()

	authHeader := "Bearer " + token

	// 1. Create asset channel with initial balance
	assetBody := strings.NewReader(`{"name":"招商储蓄卡","sort_order":10,"type":"asset","initial_balance":5000.0,"credit_limit":0}`)
	req := httptest.NewRequest("POST", "/api/payment-methods", assetBody)
	req.Header.Set("Authorization", authHeader)
	rec := httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 for asset channel creation, got %d: %s", rec.Code, rec.Body.String())
	}
	var assetPM PaymentMethod
	if err := json.NewDecoder(rec.Body).Decode(&assetPM); err != nil {
		t.Fatalf("decode assetPM failed: %v", err)
	}
	if assetPM.Type != "asset" || assetPM.InitialBalance != 5000.0 || assetPM.CreditLimit != 0 {
		t.Errorf("unexpected assetPM: %+v", assetPM)
	}

	// 2. Create liability channel with credit limit and initial debt
	liabBody := strings.NewReader(`{"name":"京东白条","sort_order":11,"type":"liability","initial_balance":200.0,"credit_limit":6000.0}`)
	req = httptest.NewRequest("POST", "/api/payment-methods", liabBody)
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected 201 for liability channel creation, got %d: %s", rec.Code, rec.Body.String())
	}
	var liabPM PaymentMethod
	if err := json.NewDecoder(rec.Body).Decode(&liabPM); err != nil {
		t.Fatalf("decode liabPM failed: %v", err)
	}
	if liabPM.Type != "liability" || liabPM.InitialBalance != 200.0 || liabPM.CreditLimit != 6000.0 {
		t.Errorf("unexpected liabPM: %+v", liabPM)
	}

	// 3. Test invalid channel type returns 400
	invalidBody := strings.NewReader(`{"name":"非法渠道","sort_order":12,"type":"invalid_type"}`)
	req = httptest.NewRequest("POST", "/api/payment-methods", invalidBody)
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for invalid channel type, got %d", rec.Code)
	}

	// 3b. Test rejection of negative balance or negative credit limit
	negBalBody := strings.NewReader(`{"name":"负余额渠道","sort_order":13,"type":"asset","initial_balance":-100.0}`)
	req = httptest.NewRequest("POST", "/api/payment-methods", negBalBody)
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for negative initial balance, got %d", rec.Code)
	}

	negLimitBody := strings.NewReader(`{"name":"负额度渠道","sort_order":14,"type":"liability","initial_balance":0.0,"credit_limit":-5000.0}`)
	req = httptest.NewRequest("POST", "/api/payment-methods", negLimitBody)
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for negative credit limit, got %d", rec.Code)
	}

	negUpdateBody := strings.NewReader(`{"name":"京东白条金卡","sort_order":11,"type":"liability","credit_limit":-10.0}`)
	req = httptest.NewRequest("PUT", "/api/payment-methods/"+strconv.FormatInt(liabPM.ID, 10), negUpdateBody)
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for updating negative credit limit, got %d", rec.Code)
	}

	// 4. Update liability channel credit limit and initial balance
	updateBody := strings.NewReader(`{"name":"京东白条金卡","sort_order":11,"type":"liability","initial_balance":0.0,"credit_limit":10000.0}`)
	req = httptest.NewRequest("PUT", "/api/payment-methods/"+strconv.FormatInt(liabPM.ID, 10), updateBody)
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 for update liability channel, got %d: %s", rec.Code, rec.Body.String())
	}
	var updatedPM PaymentMethod
	if err := json.NewDecoder(rec.Body).Decode(&updatedPM); err != nil {
		t.Fatalf("decode updatedPM failed: %v", err)
	}
	if updatedPM.Name != "京东白条金卡" || updatedPM.CreditLimit != 10000.0 || updatedPM.InitialBalance != 0.0 {
		t.Errorf("unexpected updatedPM: %+v", updatedPM)
	}

	// 5. List payment methods and check presence
	reqList := httptest.NewRequest("GET", "/api/payment-methods", nil)
	reqList.Header.Set("Authorization", authHeader)
	recList := httptest.NewRecorder()
	s.ServeHTTP(recList, reqList)
	if recList.Code != http.StatusOK {
		t.Fatalf("expected 200 for list payment methods, got %d", recList.Code)
	}
	var list []PaymentMethod
	if err := json.NewDecoder(recList.Body).Decode(&list); err != nil {
		t.Fatalf("decode list failed: %v", err)
	}
	foundAsset := false
	foundLiab := false
	for _, it := range list {
		if it.ID == assetPM.ID && it.Type == "asset" && it.InitialBalance == 5000.0 {
			foundAsset = true
		}
		if it.ID == liabPM.ID && it.Type == "liability" && it.CreditLimit == 10000.0 {
			foundLiab = true
		}
	}
	if !foundAsset || !foundLiab {
		t.Errorf("expected to find both created channels in list, foundAsset=%v, foundLiab=%v", foundAsset, foundLiab)
	}
}

func TestStatsSummaryWithAssetsAndLiabilities(t *testing.T) {
	s, token, cleanup := setupTestServer(t)
	defer cleanup()

	authHeader := "Bearer " + token

	// Clear pre-seeded payment methods to have clean deterministic totals
	if _, err := s.db.Exec("DELETE FROM payment_methods;"); err != nil {
		t.Fatalf("failed to clear payment methods: %v", err)
	}

	// Create Bank Card: Asset with initial balance 5000.00
	pmAssetRes, err := s.db.Exec("INSERT INTO payment_methods (name, sort_order, type, initial_balance_cents, credit_limit_cents) VALUES ('招行储蓄卡', 1, 'asset', 500000, 0)")
	if err != nil {
		t.Fatalf("failed to insert asset pm: %v", err)
	}
	assetPMID, _ := pmAssetRes.LastInsertId()

	// Create Credit Card: Liability with initial debt 0.00, credit limit 20000.00
	pmLiabRes, err := s.db.Exec("INSERT INTO payment_methods (name, sort_order, type, initial_balance_cents, credit_limit_cents) VALUES ('招行信用卡', 2, 'liability', 0, 2000000)")
	if err != nil {
		t.Fatalf("failed to insert liability pm: %v", err)
	}
	liabPMID, _ := pmLiabRes.LastInsertId()

	// Get existing category and tag
	var catID, tagID int64
	err = s.db.QueryRow("SELECT id FROM categories LIMIT 1").Scan(&catID)
	if err != nil {
		t.Fatalf("failed to get category: %v", err)
	}
	err = s.db.QueryRow("SELECT id FROM tags WHERE category_id = ? LIMIT 1", catID).Scan(&tagID)
	if err != nil {
		t.Fatalf("failed to get tag: %v", err)
	}

	nowISO := time.Now().UTC().Format(time.RFC3339)

	// 1. Bank card income: +10,000.00 (1,000,000 cents)
	_, err = s.db.Exec("INSERT INTO transactions (amount_cents, description, payment_method_id, category_id, tag_id, transacted_at) VALUES (1000000, '主业薪资', ?, ?, ?, ?)", assetPMID, catID, tagID, nowISO)
	if err != nil {
		t.Fatalf("failed to insert income: %v", err)
	}

	// 2. Bank card expense: -2,000.00 (-200,000 cents)
	_, err = s.db.Exec("INSERT INTO transactions (amount_cents, description, payment_method_id, category_id, tag_id, transacted_at) VALUES (-200000, '数码采购', ?, ?, ?, ?)", assetPMID, catID, tagID, nowISO)
	if err != nil {
		t.Fatalf("failed to insert bank expense: %v", err)
	}

	// 3. Credit card expense: -3,000.00 (-300,000 cents)
	_, err = s.db.Exec("INSERT INTO transactions (amount_cents, description, payment_method_id, category_id, tag_id, transacted_at) VALUES (-300000, '机票预订', ?, ?, ?, ?)", liabPMID, catID, tagID, nowISO)
	if err != nil {
		t.Fatalf("failed to insert cc expense: %v", err)
	}

	// Request stats summary
	req := httptest.NewRequest("GET", "/api/stats/summary", nil)
	req.Header.Set("Authorization", authHeader)
	rec := httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 for stats summary, got %d: %s", rec.Code, rec.Body.String())
	}

	var stats StatsSummaryResponse
	if err := json.NewDecoder(rec.Body).Decode(&stats); err != nil {
		t.Fatalf("failed to decode stats: %v", err)
	}

	// Assert asset summary
	// Bank Card balance: 5000 + 10000 - 2000 = 13000.00
	if stats.AssetSummary.TotalAssets != 13000.00 {
		t.Errorf("expected TotalAssets 13000.00, got %v", stats.AssetSummary.TotalAssets)
	}

	// Credit Card debt: 0 - (-3000) = 3000.00
	if stats.AssetSummary.TotalLiabilities != 3000.00 {
		t.Errorf("expected TotalLiabilities 3000.00, got %v", stats.AssetSummary.TotalLiabilities)
	}

	// Net Assets: 13000 - 3000 = 10000.00
	if stats.AssetSummary.NetAssets != 10000.00 {
		t.Errorf("expected NetAssets 10000.00, got %v", stats.AssetSummary.NetAssets)
	}

	if len(stats.AssetSummary.AssetChannels) != 1 {
		t.Fatalf("expected 1 asset channel, got %d", len(stats.AssetSummary.AssetChannels))
	}
	ac := stats.AssetSummary.AssetChannels[0]
	if ac.RemainingBalance != 13000.00 || ac.Percentage != 100.0 {
		t.Errorf("unexpected asset channel stat: %+v", ac)
	}

	if len(stats.AssetSummary.LiabilityChannels) != 1 {
		t.Fatalf("expected 1 liability channel, got %d", len(stats.AssetSummary.LiabilityChannels))
	}
	lc := stats.AssetSummary.LiabilityChannels[0]
	if lc.CurrentDebt != 3000.00 || lc.RemainingCredit != 17000.00 || lc.CreditLimit != 20000.00 || lc.UsageRate != 15.0 {
		t.Errorf("unexpected liability channel stat: %+v", lc)
	}

	// Overpayment test: Add 4000.00 repayment/income to the liability channel so current debt becomes -1000.00
	_, err = s.db.Exec("INSERT INTO transactions (amount_cents, description, payment_method_id, category_id, tag_id, transacted_at) VALUES (400000, '多还款', ?, ?, ?, ?)", liabPMID, catID, tagID, nowISO)
	if err != nil {
		t.Fatalf("failed to insert overpayment: %v", err)
	}

	reqOver := httptest.NewRequest("GET", "/api/stats/summary", nil)
	reqOver.Header.Set("Authorization", authHeader)
	recOver := httptest.NewRecorder()
	s.ServeHTTP(recOver, reqOver)
	if recOver.Code != http.StatusOK {
		t.Fatalf("expected 200 for stats summary with overpayment, got %d", recOver.Code)
	}
	var statsOver StatsSummaryResponse
	_ = json.NewDecoder(recOver.Body).Decode(&statsOver)
	if len(statsOver.AssetSummary.LiabilityChannels) > 0 {
		overLC := statsOver.AssetSummary.LiabilityChannels[0]
		// Debt should be 3000 - 4000 = -1000
		if overLC.CurrentDebt != -1000.00 {
			t.Errorf("expected CurrentDebt -1000.00, got %v", overLC.CurrentDebt)
		}
		// Remaining credit must clamp to credit limit (20000.00), NOT 21000.00
		if overLC.RemainingCredit != 20000.00 {
			t.Errorf("expected clamped RemainingCredit 20000.00, got %v", overLC.RemainingCredit)
		}
		if overLC.UsageRate != 0.0 {
			t.Errorf("expected clamped UsageRate 0.0, got %v", overLC.UsageRate)
		}
	}

	// Verify 409 guard on deleting channel with transaction reference
	reqDel := httptest.NewRequest("DELETE", "/api/payment-methods/"+strconv.FormatInt(liabPMID, 10), nil)
	reqDel.Header.Set("Authorization", authHeader)
	recDel := httptest.NewRecorder()
	s.ServeHTTP(recDel, reqDel)
	if recDel.Code != http.StatusConflict {
		t.Errorf("expected 409 Conflict when deleting referenced channel, got %d", recDel.Code)
	}
}

func TestRepaymentFullFlowAndInvariants(t *testing.T) {
	s, token, cleanup := setupTestServer(t)
	defer cleanup()

	authHeader := "Bearer " + token

	// 1. Check system repayment category and tag mutation guards
	var sysCatID, sysTagID string
	err := s.db.QueryRow("SELECT value FROM system_meta WHERE key = 'system_category_repayment_id'").Scan(&sysCatID)
	if err != nil {
		t.Fatalf("failed to query system repayment category id: %v", err)
	}
	err = s.db.QueryRow("SELECT value FROM system_meta WHERE key = 'system_tag_repayment_id'").Scan(&sysTagID)
	if err != nil {
		t.Fatalf("failed to query system repayment tag id: %v", err)
	}

	// Try to update system category -> 400
	req := httptest.NewRequest("PUT", "/api/categories/"+sysCatID, strings.NewReader(`{"name":"试图重命名"}`))
	req.Header.Set("Authorization", authHeader)
	rec := httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 when updating system category, got %d", rec.Code)
	}

	// Try to delete system category -> 400
	req = httptest.NewRequest("DELETE", "/api/categories/"+sysCatID, nil)
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 when deleting system category, got %d", rec.Code)
	}

	// Try to update system tag -> 400
	req = httptest.NewRequest("PUT", "/api/tags/"+sysTagID, strings.NewReader(`{"name":"试图重命名标签"}`))
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 when updating system tag, got %d", rec.Code)
	}

	// Try to delete system tag -> 400
	req = httptest.NewRequest("DELETE", "/api/tags/"+sysTagID, nil)
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 when deleting system tag, got %d", rec.Code)
	}

	// 2. Query payment methods for asset and liability channels
	var assetPMID, liabPMID int64
	err = s.db.QueryRow("SELECT id FROM payment_methods WHERE type = 'asset' AND name = '招商银行卡'").Scan(&assetPMID)
	if err != nil {
		t.Fatalf("failed to query asset channel: %v", err)
	}
	err = s.db.QueryRow("SELECT id FROM payment_methods WHERE type = 'liability' AND name = '招商信用卡'").Scan(&liabPMID)
	if err != nil {
		t.Fatalf("failed to query liability channel: %v", err)
	}

	// 3. Validation checks for repayment
	// Repayment with negative amount -> 400
	repayNeg, _ := json.Marshal(map[string]any{
		"type":              "repayment",
		"amount":            -100.0,
		"payment_method_id": liabPMID,
	})
	req = httptest.NewRequest("POST", "/api/transactions", strings.NewReader(string(repayNeg)))
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for negative repayment amount, got %d", rec.Code)
	}

	// Repayment with target payment method being asset -> 400
	repayWrongTarget, _ := json.Marshal(map[string]any{
		"type":              "repayment",
		"amount":            100.0,
		"payment_method_id": assetPMID,
	})
	req = httptest.NewRequest("POST", "/api/transactions", strings.NewReader(string(repayWrongTarget)))
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for non-liability target channel, got %d", rec.Code)
	}

	// Repayment with source payment method being liability -> 400
	repayWrongSource, _ := json.Marshal(map[string]any{
		"type":                      "repayment",
		"amount":                    100.0,
		"payment_method_id":         liabPMID,
		"source_payment_method_id": liabPMID,
	})
	req = httptest.NewRequest("POST", "/api/transactions", strings.NewReader(string(repayWrongSource)))
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for non-asset source channel, got %d", rec.Code)
	}

	// 4. Initial state: add an income to asset channel and expense to credit card
	nowISO := time.Now().UTC().Format(time.RFC3339)
	var normalCatID, normalTagID int64
	err = s.db.QueryRow("SELECT id FROM categories WHERE name = '餐饮美食'").Scan(&normalCatID)
	if err != nil {
		t.Fatalf("failed to query category 餐饮美食: %v", err)
	}
	err = s.db.QueryRow("SELECT id FROM tags WHERE category_id = ? LIMIT 1", normalCatID).Scan(&normalTagID)
	if err != nil {
		t.Fatalf("failed to query tag: %v", err)
	}

	// Income 10,000.00 to asset channel (招商银行卡)
	incJSON, _ := json.Marshal(map[string]any{
		"type":              "income",
		"amount":            10000.0,
		"description":       "工资收入",
		"payment_method_id": assetPMID,
		"category_id":       normalCatID,
		"tag_id":            normalTagID,
		"transacted_at":     nowISO,
	})
	req = httptest.NewRequest("POST", "/api/transactions", strings.NewReader(string(incJSON)))
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("failed to insert initial income: %d", rec.Code)
	}

	// Expense 2,000.00 on credit card
	expJSON, _ := json.Marshal(map[string]any{
		"type":              "expense",
		"amount":            -2000.0,
		"description":       "数码消费",
		"payment_method_id": liabPMID,
		"category_id":       normalCatID,
		"tag_id":            normalTagID,
		"transacted_at":     nowISO,
	})
	req = httptest.NewRequest("POST", "/api/transactions", strings.NewReader(string(expJSON)))
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("failed to insert initial expense: %d", rec.Code)
	}

	// 5. Create a valid repayment of 500.00 (from 招商银行卡 to 招商信用卡)
	repayJSON, _ := json.Marshal(map[string]any{
		"type":                      "repayment",
		"amount":                    500.0,
		"description":               "偿还信用卡",
		"payment_method_id":         liabPMID,
		"source_payment_method_id": assetPMID,
		"transacted_at":             nowISO,
	})
	req = httptest.NewRequest("POST", "/api/transactions", strings.NewReader(string(repayJSON)))
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("failed to create repayment: %d, body: %s", rec.Code, rec.Body.String())
	}
	var createdRepay Transaction
	if err := json.NewDecoder(rec.Body).Decode(&createdRepay); err != nil {
		t.Fatalf("failed to decode created repayment: %v", err)
	}

	if createdRepay.Type != "repayment" {
		t.Errorf("expected type 'repayment', got '%s'", createdRepay.Type)
	}
	if createdRepay.Amount != 500.0 {
		t.Errorf("expected amount 500.0, got %v", createdRepay.Amount)
	}
	if createdRepay.SourcePaymentMethodID == nil || *createdRepay.SourcePaymentMethodID != assetPMID {
		t.Errorf("expected source_payment_method_id %d, got %v", assetPMID, createdRepay.SourcePaymentMethodID)
	}
	if createdRepay.SourcePaymentMethodName != "招商银行卡" {
		t.Errorf("expected source_payment_method_name '招商银行卡', got %v", createdRepay.SourcePaymentMethodName)
	}

	// 6. Test PUT update on the repayment transaction
	updateRepayJSON, _ := json.Marshal(map[string]any{
		"type":                      "repayment",
		"amount":                    600.0,
		"description":               "偿还信用卡(更新为600)",
		"payment_method_id":         liabPMID,
		"source_payment_method_id": assetPMID,
		"category_id":               createdRepay.CategoryID,
		"tag_id":                    createdRepay.TagID,
		"transacted_at":             nowISO,
	})
	req = httptest.NewRequest("PUT", "/api/transactions/"+strconv.FormatInt(createdRepay.ID, 10), strings.NewReader(string(updateRepayJSON)))
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("failed to update repayment: %d, body: %s", rec.Code, rec.Body.String())
	}
	var updatedRepay Transaction
	if err := json.NewDecoder(rec.Body).Decode(&updatedRepay); err != nil {
		t.Fatalf("failed to decode updated repayment: %v", err)
	}
	if updatedRepay.Amount != 600.0 || updatedRepay.Description != "偿还信用卡(更新为600)" {
		t.Errorf("unexpected updated repayment: %+v", updatedRepay)
	}

	// 7. Verify filtering & list isolation
	// GET /api/transactions?type=income
	req = httptest.NewRequest("GET", "/api/transactions?type=income", nil)
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	var incList []Transaction
	_ = json.NewDecoder(rec.Body).Decode(&incList)
	for _, item := range incList {
		if item.Type == "repayment" {
			t.Errorf("repayment transaction leaked into ?type=income: %+v", item)
		}
	}

	// GET /api/transactions?type=repayment
	req = httptest.NewRequest("GET", "/api/transactions?type=repayment", nil)
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	var repayList []Transaction
	_ = json.NewDecoder(rec.Body).Decode(&repayList)
	if len(repayList) != 1 || repayList[0].ID != createdRepay.ID {
		t.Errorf("expected exactly 1 repayment in ?type=repayment, got %d", len(repayList))
	}

	// 8. Verify macro assets, liabilities, and net asset conservation
	req = httptest.NewRequest("GET", "/api/stats/summary", nil)
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("failed to query stats summary: %d", rec.Code)
	}
	var stats StatsSummaryResponse
	_ = json.NewDecoder(rec.Body).Decode(&stats)

	// Stat isolation check:
	// MonthExpense must be exactly 2000.00
	if stats.MonthExpense != 2000.00 {
		t.Errorf("expected MonthExpense 2000.00, got %v", stats.MonthExpense)
	}
	// MonthIncome must be exactly 10000.00 (NOT 10600.00)
	if stats.MonthIncome != 10000.00 {
		t.Errorf("expected MonthIncome 10000.00, got %v", stats.MonthIncome)
	}

	// Category distribution must NOT contain the repayment category
	for _, catDist := range stats.CategoryDistribution {
		if catDist.Name == "债务偿还" {
			t.Errorf("repayment category leaked into category distribution: %+v", catDist)
		}
	}

	// Asset balance check:
	// 招商银行卡: init(0) + income(10000) - source_repayment(600) = 9400.00
	// 招商信用卡 debt: init(0) - [expense(-2000) + repayment(600)] = 0 - (-1400) = 1400.00
	// Total Assets: 9400.00
	// Total Liabilities: 1400.00
	// Net Assets: 9400.00 - 1400.00 = 8000.00 (Prior to repayment: Assets 10000, Liabilities 2000, Net Assets 8000)
	var actualAssetBal, actualLiabDebt float64
	for _, a := range stats.AssetSummary.AssetChannels {
		if a.Name == "招商银行卡" {
			actualAssetBal = a.RemainingBalance
		}
	}
	for _, l := range stats.AssetSummary.LiabilityChannels {
		if l.Name == "招商信用卡" {
			actualLiabDebt = l.CurrentDebt
		}
	}

	if actualAssetBal != 9400.00 {
		t.Errorf("expected 招商银行卡 balance 9400.00, got %v", actualAssetBal)
	}
	if actualLiabDebt != 1400.00 {
		t.Errorf("expected 招商信用卡 debt 1400.00, got %v", actualLiabDebt)
	}
	if stats.AssetSummary.TotalAssets != 9400.00 {
		t.Errorf("expected TotalAssets 9400.00, got %v", stats.AssetSummary.TotalAssets)
	}
	if stats.AssetSummary.TotalLiabilities != 1400.00 {
		t.Errorf("expected TotalLiabilities 1400.00, got %v", stats.AssetSummary.TotalLiabilities)
	}
	if stats.AssetSummary.NetAssets != 8000.00 {
		t.Errorf("expected NetAssets 8000.00, got %v", stats.AssetSummary.NetAssets)
	}

	// 9. Test External Source Repayment (source_payment_method_id = nil / external)
	repayExtJSON, _ := json.Marshal(map[string]any{
		"type":              "repayment",
		"amount":            400.0,
		"description":       "外部资金偿还信用卡",
		"payment_method_id": liabPMID,
		"transacted_at":     nowISO,
	})
	req = httptest.NewRequest("POST", "/api/transactions", strings.NewReader(string(repayExtJSON)))
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("failed to create external repayment: %d, body: %s", rec.Code, rec.Body.String())
	}

	// Verify stats after external repayment:
	// Debt reduces by another 400.00 -> 1000.00
	// 招商银行卡 balance stays at 9400.00
	// Total assets stays at 9400.00, Total liabilities becomes 1000.00, Net Assets becomes 8400.00
	req = httptest.NewRequest("GET", "/api/stats/summary", nil)
	req.Header.Set("Authorization", authHeader)
	rec = httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("failed to query stats summary after external repayment: %d", rec.Code)
	}
	var statsExt StatsSummaryResponse
	_ = json.NewDecoder(rec.Body).Decode(&statsExt)

	actualLiabDebt = 0
	for _, l := range statsExt.AssetSummary.LiabilityChannels {
		if l.Name == "招商信用卡" {
			actualLiabDebt = l.CurrentDebt
		}
	}
	if actualLiabDebt != 1000.00 {
		t.Errorf("expected 招商信用卡 debt 1000.00 after external repayment, got %v", actualLiabDebt)
	}
	if statsExt.AssetSummary.TotalAssets != 9400.00 {
		t.Errorf("expected TotalAssets 9400.00, got %v", statsExt.AssetSummary.TotalAssets)
	}
	if statsExt.AssetSummary.TotalLiabilities != 1000.00 {
		t.Errorf("expected TotalLiabilities 1000.00, got %v", statsExt.AssetSummary.TotalLiabilities)
	}
	if statsExt.AssetSummary.NetAssets != 8400.00 {
		t.Errorf("expected NetAssets 8400.00, got %v", statsExt.AssetSummary.NetAssets)
	}

	// 10. Verify 409 guard when channel is ONLY referenced as source_payment_method_id
	createPMBody := strings.NewReader(`{"name":"专属转出卡","type":"asset","initial_balance":0,"sort_order":99}`)
	reqNewPM := httptest.NewRequest("POST", "/api/payment-methods", createPMBody)
	reqNewPM.Header.Set("Authorization", authHeader)
	recNewPM := httptest.NewRecorder()
	s.ServeHTTP(recNewPM, reqNewPM)
	if recNewPM.Code != http.StatusCreated {
		t.Fatalf("failed to create test asset channel: %d", recNewPM.Code)
	}
	var testPM PaymentMethod
	_ = json.NewDecoder(recNewPM.Body).Decode(&testPM)

	// Create repayment solely referencing testPM as source_payment_method_id
	repaySrcOnlyJSON, _ := json.Marshal(map[string]any{
		"type":                     "repayment",
		"amount":                   100.0,
		"description":              "测试仅转出删除守卫",
		"payment_method_id":        liabPMID,
		"source_payment_method_id": testPM.ID,
		"transacted_at":            nowISO,
	})
	reqSrcRepay := httptest.NewRequest("POST", "/api/transactions", strings.NewReader(string(repaySrcOnlyJSON)))
	reqSrcRepay.Header.Set("Authorization", authHeader)
	recSrcRepay := httptest.NewRecorder()
	s.ServeHTTP(recSrcRepay, reqSrcRepay)
	if recSrcRepay.Code != http.StatusCreated {
		t.Fatalf("failed to create repayment referencing testPM as source: %d", recSrcRepay.Code)
	}

	// Attempt to delete testPM - must return 409 Conflict, NOT 500 FK error
	reqDelSrcPM := httptest.NewRequest("DELETE", "/api/payment-methods/"+strconv.FormatInt(testPM.ID, 10), nil)
	reqDelSrcPM.Header.Set("Authorization", authHeader)
	recDelSrcPM := httptest.NewRecorder()
	s.ServeHTTP(recDelSrcPM, reqDelSrcPM)
	if recDelSrcPM.Code != http.StatusConflict {
		t.Errorf("expected 409 Conflict when deleting channel referenced as source_payment_method_id, got %d (body: %s)", recDelSrcPM.Code, recDelSrcPM.Body.String())
	}
}

func TestTransferFullFlowAndInvariants(t *testing.T) {
	s, token, cleanup := setupTestServer(t)
	defer cleanup()

	authHeader := "Bearer " + token

	// 1. Verify Category API type support and system transfer protection
	reqCats := httptest.NewRequest("GET", "/api/categories", nil)
	reqCats.Header.Set("Authorization", authHeader)
	recCats := httptest.NewRecorder()
	s.ServeHTTP(recCats, reqCats)
	if recCats.Code != http.StatusOK {
		t.Fatalf("expected 200 for list categories, got %d", recCats.Code)
	}

	var catList []Category
	if err := json.NewDecoder(recCats.Body).Decode(&catList); err != nil {
		t.Fatalf("failed to decode categories: %v", err)
	}

	var transferCatID, transferTagID int64
	for _, c := range catList {
		if c.Type == "" {
			t.Errorf("category %s has empty type", c.Name)
		}
		if c.Name == "职业收入" && c.Type != "income" {
			t.Errorf("expected 职业收入 to be 'income', got '%s'", c.Type)
		}
		if c.Name == "餐饮美食" && c.Type != "expense" {
			t.Errorf("expected 餐饮美食 to be 'expense', got '%s'", c.Type)
		}
		if c.Name == "账户转账" {
			if c.Type != "system" {
				t.Errorf("expected 账户转账 to be 'system', got '%s'", c.Type)
			}
			transferCatID = c.ID
			if len(c.Tags) > 0 {
				transferTagID = c.Tags[0].ID
			}
		}
	}

	if transferCatID == 0 || transferTagID == 0 {
		t.Fatalf("expected system transfer category and tag to exist, got catID=%d, tagID=%d", transferCatID, transferTagID)
	}

	// 1.1 Verify immutable guard on system transfer category
	reqUpdateSysCat := httptest.NewRequest("PUT", "/api/categories/"+strconv.FormatInt(transferCatID, 10), strings.NewReader(`{"name":"改名转账"}`))
	reqUpdateSysCat.Header.Set("Authorization", authHeader)
	recUpdateSysCat := httptest.NewRecorder()
	s.ServeHTTP(recUpdateSysCat, reqUpdateSysCat)
	if recUpdateSysCat.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for updating system transfer category, got %d", recUpdateSysCat.Code)
	}

	reqDelSysCat := httptest.NewRequest("DELETE", "/api/categories/"+strconv.FormatInt(transferCatID, 10), nil)
	reqDelSysCat.Header.Set("Authorization", authHeader)
	recDelSysCat := httptest.NewRecorder()
	s.ServeHTTP(recDelSysCat, reqDelSysCat)
	if recDelSysCat.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for deleting system transfer category, got %d", recDelSysCat.Code)
	}

	// 1.2 Verify immutable guard on system transfer tag
	reqUpdateSysTag := httptest.NewRequest("PUT", "/api/tags/"+strconv.FormatInt(transferTagID, 10), strings.NewReader(`{"name":"改名标签"}`))
	reqUpdateSysTag.Header.Set("Authorization", authHeader)
	recUpdateSysTag := httptest.NewRecorder()
	s.ServeHTTP(recUpdateSysTag, reqUpdateSysTag)
	if recUpdateSysTag.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for updating system transfer tag, got %d", recUpdateSysTag.Code)
	}

	reqDelSysTag := httptest.NewRequest("DELETE", "/api/tags/"+strconv.FormatInt(transferTagID, 10), nil)
	reqDelSysTag.Header.Set("Authorization", authHeader)
	recDelSysTag := httptest.NewRecorder()
	s.ServeHTTP(recDelSysTag, reqDelSysTag)
	if recDelSysTag.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for deleting system transfer tag, got %d", recDelSysTag.Code)
	}

	// 1.3 Verify creating categories with type
	reqCreateIncome := httptest.NewRequest("POST", "/api/categories", strings.NewReader(`{"name":"副业兼职","sort_order":10,"type":"income"}`))
	reqCreateIncome.Header.Set("Authorization", authHeader)
	recCreateIncome := httptest.NewRecorder()
	s.ServeHTTP(recCreateIncome, reqCreateIncome)
	if recCreateIncome.Code != http.StatusCreated {
		t.Fatalf("expected 201 for creating income category, got %d", recCreateIncome.Code)
	}
	var newIncomeCat Category
	_ = json.NewDecoder(recCreateIncome.Body).Decode(&newIncomeCat)
	if newIncomeCat.Type != "income" {
		t.Errorf("expected new category type to be 'income', got '%s'", newIncomeCat.Type)
	}

	// Update category without type - type must be preserved
	reqUpdateCatNoType := httptest.NewRequest("PUT", "/api/categories/"+strconv.FormatInt(newIncomeCat.ID, 10), strings.NewReader(`{"name":"副业兼职改名"}`))
	reqUpdateCatNoType.Header.Set("Authorization", authHeader)
	recUpdateCatNoType := httptest.NewRecorder()
	s.ServeHTTP(recUpdateCatNoType, reqUpdateCatNoType)
	if recUpdateCatNoType.Code != http.StatusOK {
		t.Fatalf("expected 200 for update category without type, got %d", recUpdateCatNoType.Code)
	}
	var updatedCat Category
	_ = json.NewDecoder(recUpdateCatNoType.Body).Decode(&updatedCat)
	if updatedCat.Type != "income" {
		t.Errorf("expected preserved category type 'income', got '%s'", updatedCat.Type)
	}

	// 2. Prepare Payment Methods for Transfer
	// Set initial balance: 招商银行卡 = 5000.00, 微信支付 = 500.00
	reqPMs := httptest.NewRequest("GET", "/api/payment-methods", nil)
	reqPMs.Header.Set("Authorization", authHeader)
	recPMs := httptest.NewRecorder()
	s.ServeHTTP(recPMs, reqPMs)
	var pmList []PaymentMethod
	_ = json.NewDecoder(recPMs.Body).Decode(&pmList)

	var bankPM, wechatPM, creditPM PaymentMethod
	for _, pm := range pmList {
		if pm.Name == "招商银行卡" {
			bankPM = pm
		} else if pm.Name == "微信支付" {
			wechatPM = pm
		} else if pm.Name == "招商信用卡" {
			creditPM = pm
		}
	}

	// Set initial balances via PUT
	initBalBank := 5000.00
	updBankReq := httptest.NewRequest("PUT", "/api/payment-methods/"+strconv.FormatInt(bankPM.ID, 10), strings.NewReader(`{"name":"招商银行卡","sort_order":3,"type":"asset","initial_balance":5000}`))
	updBankReq.Header.Set("Authorization", authHeader)
	recUpdBank := httptest.NewRecorder()
	s.ServeHTTP(recUpdBank, updBankReq)

	initBalWechat := 500.00
	updWechatReq := httptest.NewRequest("PUT", "/api/payment-methods/"+strconv.FormatInt(wechatPM.ID, 10), strings.NewReader(`{"name":"微信支付","sort_order":1,"type":"asset","initial_balance":500}`))
	updWechatReq.Header.Set("Authorization", authHeader)
	recUpdWechat := httptest.NewRecorder()
	s.ServeHTTP(recUpdWechat, updWechatReq)

	_ = initBalBank
	_ = initBalWechat

	// Initial Stats before any transaction
	reqStatsBefore := httptest.NewRequest("GET", "/api/stats/summary", nil)
	reqStatsBefore.Header.Set("Authorization", authHeader)
	recStatsBefore := httptest.NewRecorder()
	s.ServeHTTP(recStatsBefore, reqStatsBefore)
	var statsBefore StatsSummaryResponse
	_ = json.NewDecoder(recStatsBefore.Body).Decode(&statsBefore)

	initialTotalAssets := statsBefore.AssetSummary.TotalAssets
	initialNetAssets := statsBefore.AssetSummary.NetAssets

	// 3. Transfer Validation Errors
	nowISO := time.Now().UTC().Format(time.RFC3339)

	// 3.1 Negative amount
	badAmtJSON, _ := json.Marshal(map[string]any{
		"type":                     "transfer",
		"amount":                   -100.0,
		"description":              "非法负金额",
		"payment_method_id":        wechatPM.ID,
		"source_payment_method_id": bankPM.ID,
		"transacted_at":            nowISO,
	})
	reqBadAmt := httptest.NewRequest("POST", "/api/transactions", strings.NewReader(string(badAmtJSON)))
	reqBadAmt.Header.Set("Authorization", authHeader)
	recBadAmt := httptest.NewRecorder()
	s.ServeHTTP(recBadAmt, reqBadAmt)
	if recBadAmt.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for negative transfer amount, got %d", recBadAmt.Code)
	}

	// 3.2 Missing source channel
	noSrcJSON, _ := json.Marshal(map[string]any{
		"type":              "transfer",
		"amount":            100.0,
		"description":       "无来源渠道",
		"payment_method_id": wechatPM.ID,
		"transacted_at":     nowISO,
	})
	reqNoSrc := httptest.NewRequest("POST", "/api/transactions", strings.NewReader(string(noSrcJSON)))
	reqNoSrc.Header.Set("Authorization", authHeader)
	recNoSrc := httptest.NewRecorder()
	s.ServeHTTP(recNoSrc, reqNoSrc)
	if recNoSrc.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for transfer without source channel, got %d", recNoSrc.Code)
	}

	// 3.3 Source channel equals target channel
	sameChanJSON, _ := json.Marshal(map[string]any{
		"type":                     "transfer",
		"amount":                   100.0,
		"description":              "自转自",
		"payment_method_id":        wechatPM.ID,
		"source_payment_method_id": wechatPM.ID,
		"transacted_at":            nowISO,
	})
	reqSameChan := httptest.NewRequest("POST", "/api/transactions", strings.NewReader(string(sameChanJSON)))
	reqSameChan.Header.Set("Authorization", authHeader)
	recSameChan := httptest.NewRecorder()
	s.ServeHTTP(recSameChan, reqSameChan)
	if recSameChan.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for self-transfer, got %d", recSameChan.Code)
	}

	// 3.4 Target channel is liability channel
	targetLiabJSON, _ := json.Marshal(map[string]any{
		"type":                     "transfer",
		"amount":                   100.0,
		"description":              "目标为负债",
		"payment_method_id":        creditPM.ID,
		"source_payment_method_id": bankPM.ID,
		"transacted_at":            nowISO,
	})
	reqTargetLiab := httptest.NewRequest("POST", "/api/transactions", strings.NewReader(string(targetLiabJSON)))
	reqTargetLiab.Header.Set("Authorization", authHeader)
	recTargetLiab := httptest.NewRecorder()
	s.ServeHTTP(recTargetLiab, reqTargetLiab)
	if recTargetLiab.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for transfer to liability channel, got %d", recTargetLiab.Code)
	}

	// 3.5 Source channel is liability channel
	srcLiabJSON, _ := json.Marshal(map[string]any{
		"type":                     "transfer",
		"amount":                   100.0,
		"description":              "来源为负债",
		"payment_method_id":        wechatPM.ID,
		"source_payment_method_id": creditPM.ID,
		"transacted_at":            nowISO,
	})
	reqSrcLiab := httptest.NewRequest("POST", "/api/transactions", strings.NewReader(string(srcLiabJSON)))
	reqSrcLiab.Header.Set("Authorization", authHeader)
	recSrcLiab := httptest.NewRecorder()
	s.ServeHTTP(recSrcLiab, reqSrcLiab)
	if recSrcLiab.Code != http.StatusBadRequest {
		t.Errorf("expected 400 for transfer from liability channel, got %d", recSrcLiab.Code)
	}

	// 4. Successful Transfer Creation (1000.00 from bank to wechat)
	validTransferJSON, _ := json.Marshal(map[string]any{
		"type":                     "transfer",
		"amount":                   1000.00,
		"description":              "银行卡转微信零钱充值",
		"payment_method_id":        wechatPM.ID,
		"source_payment_method_id": bankPM.ID,
		"transacted_at":            nowISO,
	})
	reqValidTransfer := httptest.NewRequest("POST", "/api/transactions", strings.NewReader(string(validTransferJSON)))
	reqValidTransfer.Header.Set("Authorization", authHeader)
	recValidTransfer := httptest.NewRecorder()
	s.ServeHTTP(recValidTransfer, reqValidTransfer)
	if recValidTransfer.Code != http.StatusCreated {
		t.Fatalf("expected 201 for valid transfer, got %d (body: %s)", recValidTransfer.Code, recValidTransfer.Body.String())
	}

	var createdTx Transaction
	if err := json.NewDecoder(recValidTransfer.Body).Decode(&createdTx); err != nil {
		t.Fatalf("failed to decode created transfer: %v", err)
	}
	if createdTx.Type != "transfer" {
		t.Errorf("expected type 'transfer', got '%s'", createdTx.Type)
	}
	if createdTx.Amount != 1000.00 || createdTx.AmountCents != 100000 {
		t.Errorf("expected amount 1000.00 (cents 100000), got %v (cents %d)", createdTx.Amount, createdTx.AmountCents)
	}
	if createdTx.SourcePaymentMethodID == nil || *createdTx.SourcePaymentMethodID != bankPM.ID {
		t.Errorf("expected source_payment_method_id %d, got %v", bankPM.ID, createdTx.SourcePaymentMethodID)
	}
	if createdTx.SourcePaymentMethodName != "招商银行卡" {
		t.Errorf("expected source_payment_method_name '招商银行卡', got '%s'", createdTx.SourcePaymentMethodName)
	}
	if createdTx.PaymentMethodName != "微信支付" {
		t.Errorf("expected payment_method_name '微信支付', got '%s'", createdTx.PaymentMethodName)
	}
	if createdTx.CategoryName != "账户转账" || createdTx.TagName != "资金互转" {
		t.Errorf("expected auto-bound category '账户转账' and tag '资金互转', got cat '%s', tag '%s'", createdTx.CategoryName, createdTx.TagName)
	}

	// 5. Query Filter ?type=transfer
	reqFilterTransfer := httptest.NewRequest("GET", "/api/transactions?type=transfer", nil)
	reqFilterTransfer.Header.Set("Authorization", authHeader)
	recFilterTransfer := httptest.NewRecorder()
	s.ServeHTTP(recFilterTransfer, reqFilterTransfer)
	if recFilterTransfer.Code != http.StatusOK {
		t.Fatalf("expected 200 for ?type=transfer, got %d", recFilterTransfer.Code)
	}
	var transferList []Transaction
	_ = json.NewDecoder(recFilterTransfer.Body).Decode(&transferList)
	if len(transferList) != 1 || transferList[0].ID != createdTx.ID {
		t.Errorf("expected 1 transfer transaction in filter, got %d", len(transferList))
	}

	// 6. Macro Asset Portfolio & Invariants Verification
	reqStatsAfter := httptest.NewRequest("GET", "/api/stats/summary", nil)
	reqStatsAfter.Header.Set("Authorization", authHeader)
	recStatsAfter := httptest.NewRecorder()
	s.ServeHTTP(recStatsAfter, reqStatsAfter)
	var statsAfter StatsSummaryResponse
	_ = json.NewDecoder(recStatsAfter.Body).Decode(&statsAfter)

	var actualBankBal, actualWechatBal float64
	for _, a := range statsAfter.AssetSummary.AssetChannels {
		if a.Name == "招商银行卡" {
			actualBankBal = a.RemainingBalance
		} else if a.Name == "微信支付" {
			actualWechatBal = a.RemainingBalance
		}
	}

	// Bank balance: 5000 - 1000 = 4000
	if actualBankBal != 4000.00 {
		t.Errorf("expected 招商银行卡 balance 4000.00 after transfer, got %v", actualBankBal)
	}
	// Wechat balance: 500 + 1000 = 1500
	if actualWechatBal != 1500.00 {
		t.Errorf("expected 微信支付 balance 1500.00 after transfer, got %v", actualWechatBal)
	}

	// Invariant: TotalAssets and NetAssets must remain strictly constant!
	if statsAfter.AssetSummary.TotalAssets != initialTotalAssets {
		t.Errorf("invariance violated: TotalAssets changed from %v to %v", initialTotalAssets, statsAfter.AssetSummary.TotalAssets)
	}
	if statsAfter.AssetSummary.NetAssets != initialNetAssets {
		t.Errorf("invariance violated: NetAssets changed from %v to %v", initialNetAssets, statsAfter.AssetSummary.NetAssets)
	}

	// 7. P&L isolation: MonthExpense, MonthIncome, CategoryDistribution must be 0 (unaffected by transfer)
	if statsAfter.MonthExpense != 0 {
		t.Errorf("P&L polluted: expected MonthExpense 0, got %v", statsAfter.MonthExpense)
	}
	if statsAfter.MonthIncome != 0 {
		t.Errorf("P&L polluted: expected MonthIncome 0, got %v", statsAfter.MonthIncome)
	}
	if len(statsAfter.CategoryDistribution) != 0 {
		t.Errorf("P&L polluted: expected CategoryDistribution empty, got %d items", len(statsAfter.CategoryDistribution))
	}
}



