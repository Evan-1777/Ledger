package server

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"testing/fstest"
)

func TestHandleHealth(t *testing.T) {
	s := New(nil, nil)

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

	s := New(nil, mockFS)

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
