package server

import (
	"database/sql"
	"encoding/json"
	"io"
	"io/fs"
	"net/http"
	"strings"
)

// Server coordinates HTTP handling and application dependencies.
type Server struct {
	db            *sql.DB
	staticFS      fs.FS
	mux           *http.ServeMux
	adminPassword string
	tokenSecret   string
}

// HealthResponse represents the payload returned by /api/health.
type HealthResponse struct {
	Status  string `json:"status"`
	DB      string `json:"db"`
	Version string `json:"version"`
}

// New creates a new Server instance.
func New(database *sql.DB, staticFS fs.FS, adminPassword, tokenSecret string) *Server {
	s := &Server{
		db:            database,
		staticFS:      staticFS,
		mux:           http.NewServeMux(),
		adminPassword: adminPassword,
		tokenSecret:   tokenSecret,
	}

	s.routes()
	return s
}

func (s *Server) routes() {
	// API routes
	s.mux.HandleFunc("GET /api/health", s.handleHealth)

	// Auth routes
	s.mux.HandleFunc("POST /api/auth/login", s.handleLogin)
	s.mux.HandleFunc("GET /api/auth/check", s.handleAuthCheck)

	// Payment Methods routes
	s.mux.HandleFunc("GET /api/payment-methods", s.requireAuth(s.handleListPaymentMethods))
	s.mux.HandleFunc("POST /api/payment-methods", s.requireAuth(s.handleCreatePaymentMethod))
	s.mux.HandleFunc("PUT /api/payment-methods/{id}", s.requireAuth(s.handleUpdatePaymentMethod))
	s.mux.HandleFunc("DELETE /api/payment-methods/{id}", s.requireAuth(s.handleDeletePaymentMethod))

	// Categories routes
	s.mux.HandleFunc("GET /api/categories", s.requireAuth(s.handleListCategories))
	s.mux.HandleFunc("POST /api/categories", s.requireAuth(s.handleCreateCategory))
	s.mux.HandleFunc("PUT /api/categories/{id}", s.requireAuth(s.handleUpdateCategory))
	s.mux.HandleFunc("DELETE /api/categories/{id}", s.requireAuth(s.handleDeleteCategory))

	// Tags routes
	s.mux.HandleFunc("GET /api/tags", s.requireAuth(s.handleListTags))
	s.mux.HandleFunc("POST /api/tags", s.requireAuth(s.handleCreateTag))
	s.mux.HandleFunc("PUT /api/tags/{id}", s.requireAuth(s.handleUpdateTag))
	s.mux.HandleFunc("DELETE /api/tags/{id}", s.requireAuth(s.handleDeleteTag))

	// Transactions routes
	s.mux.HandleFunc("GET /api/transactions", s.requireAuth(s.handleListTransactions))
	s.mux.HandleFunc("POST /api/transactions", s.requireAuth(s.handleCreateTransaction))
	s.mux.HandleFunc("PUT /api/transactions/{id}", s.requireAuth(s.handleUpdateTransaction))
	s.mux.HandleFunc("DELETE /api/transactions/{id}", s.requireAuth(s.handleDeleteTransaction))

	// Stats routes
	s.mux.HandleFunc("GET /api/stats/summary", s.requireAuth(s.handleStatsSummary))
	s.mux.HandleFunc("GET /api/stats/range", s.requireAuth(s.handleStatsRange))

	// Static & SPA fallback
	if s.staticFS != nil {
		s.mux.HandleFunc("/", s.handleSPA)
	}
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")

	status := "ok"
	dbStatus := "connected"
	statusCode := http.StatusOK

	if s.db != nil {
		if err := s.db.PingContext(r.Context()); err != nil {
			status = "degraded"
			dbStatus = "disconnected"
			statusCode = http.StatusServiceUnavailable
		}
	} else {
		dbStatus = "not_configured"
	}

	w.WriteHeader(statusCode)
	_ = json.NewEncoder(w).Encode(HealthResponse{
		Status:  status,
		DB:      dbStatus,
		Version: "dev",
	})
}

// handleSPA serves static files with SPA fallback to index.html.
func (s *Server) handleSPA(w http.ResponseWriter, r *http.Request) {
	if strings.HasPrefix(r.URL.Path, "/api/") {
		http.NotFound(w, r)
		return
	}

	path := strings.TrimPrefix(r.URL.Path, "/")
	if path == "" {
		path = "index.html"
	}

	f, err := s.staticFS.Open(path)
	if err != nil {
		s.serveIndexFallback(w, r)
		return
	}

	stat, err := f.Stat()
	if err != nil || stat.IsDir() {
		_ = f.Close()
		s.serveIndexFallback(w, r)
		return
	}

	s.serveFile(w, r, stat.Name(), f, stat)
}

func (s *Server) serveIndexFallback(w http.ResponseWriter, r *http.Request) {
	indexFile, err := s.staticFS.Open("index.html")
	if err != nil {
		http.NotFound(w, r)
		return
	}
	stat, err := indexFile.Stat()
	if err != nil {
		_ = indexFile.Close()
		http.NotFound(w, r)
		return
	}
	s.serveFile(w, r, "index.html", indexFile, stat)
}

func (s *Server) serveFile(w http.ResponseWriter, r *http.Request, name string, file fs.File, stat fs.FileInfo) {
	defer file.Close()
	http.ServeContent(w, r, name, stat.ModTime(), file.(io.ReadSeeker))
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	s.mux.ServeHTTP(w, r)
}
