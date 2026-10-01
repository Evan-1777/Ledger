.PHONY: all build build-web build-server test dev-server dev-web clean

all: build

# Build web frontend static assets
build-web:
	@echo "Building frontend..."
	@cd web && npm run build

# Build Go backend single binary with embedded assets
build-server:
	@echo "Building single binary..."
	@mkdir -p bin
	@go build -ldflags="-s -w" -o bin/ledger ./cmd/server

# Complete pipeline: build frontend then compile single binary
build: build-web build-server

# Run backend unit tests and frontend type checking
test:
	@echo "Running tests..."
	@go test -v ./...
	@cd web && npm run lint

# Run Go backend for local development
dev-server:
	@go run ./cmd/server

# Run Vite frontend dev server with HMR
dev-web:
	@cd web && npm run dev

# Clean generated build artifacts and restore fallback index
clean:
	@rm -rf bin
	@rm -rf web/dist/*
	@echo '<!doctype html><html lang="zh-CN"><head><meta charset="UTF-8" /><title>Ledger</title></head><body><div id="root"></div></body></html>' > web/dist/index.html
