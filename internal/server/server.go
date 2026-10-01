package server

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"io"
	"io/fs"
	"net/http"
	"strings"
)

// Server coordinates HTTP handling and application dependencies.
type Server struct {
	db       *sql.DB
	staticFS fs.FS
	mux      *http.ServeMux
}

// HealthResponse represents the payload returned by /api/health.
type HealthResponse struct {
	Status  string `json:"status"`
	DB      string `json:"db"`
	Version string `json:"version"`
}

// New creates a new Server instance.
func New(database *sql.DB, staticFS fs.FS) *Server {
	s := &Server{
		db:       database,
		staticFS: staticFS,
		mux:      http.NewServeMux(),
	}

	s.routes()
	return s
}

func (s *Server) routes() {
	// API routes
	s.mux.HandleFunc("GET /api/health", s.handleHealth)

	// Static & SPA fallback
	if s.staticFS != nil {
		s.mux.HandleFunc("/", s.handleSPA)
	}
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")

	dbStatus := "connected"
	statusCode := http.StatusOK

	if s.db != nil {
		if err := s.db.PingContext(r.Context()); err != nil {
			dbStatus = "disconnected"
			statusCode = http.StatusServiceUnavailable
		}
	} else {
		dbStatus = "not_configured"
	}

	w.WriteHeader(statusCode)
	_ = json.NewEncoder(w).Encode(HealthResponse{
		Status:  "ok",
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

	if rs, ok := file.(io.ReadSeeker); ok {
		http.ServeContent(w, r, name, stat.ModTime(), rs)
		return
	}

	data, err := io.ReadAll(file)
	if err != nil {
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}
	http.ServeContent(w, r, name, stat.ModTime(), bytes.NewReader(data))
}

func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	s.mux.ServeHTTP(w, r)
}
