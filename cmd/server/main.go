package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"ledger/internal/config"
	"ledger/internal/db"
	"ledger/internal/server"
	"ledger/web"
)

func main() {
	cfg := config.Load()

	database, err := db.InitDB(cfg.DBPath)
	if err != nil {
		log.Fatalf("failed to initialize database (%s): %v", cfg.DBPath, err)
	}
	defer database.Close()
	log.Printf("database initialized at: %s", cfg.DBPath)

	distFS, err := web.DistFS()
	if err != nil {
		log.Fatalf("failed to load embedded static assets: %v", err)
	}

	appServer := server.New(database, distFS, cfg.AdminPassword, cfg.TokenSecret)

	httpServer := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           appServer,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	shutdownChan := make(chan os.Signal, 1)
	signal.Notify(shutdownChan, os.Interrupt, syscall.SIGTERM)

	go func() {
		log.Printf("Ledger server listening on http://localhost:%s", cfg.Port)
		if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("server listen error: %v", err)
		}
	}()

	<-shutdownChan
	log.Println("shutting down server...")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := httpServer.Shutdown(ctx); err != nil {
		log.Printf("graceful shutdown failed: %v", err)
	} else {
		log.Println("server stopped gracefully")
	}
}
