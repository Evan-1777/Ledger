.PHONY: all build build-web build-server test dev-server dev-web clean app-format app-analyze app-test app-web app-dev

FLUTTER ?= flutter
DART ?= dart
PUB_CACHE ?= $(CURDIR)/.pub-cache
export PUB_CACHE

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

# Run backend unit tests and frontend type checking & tests
test:
	@echo "Running tests..."
	@go test -v ./...
	@cd web && npm run lint && npm run test

# Run Go backend for local development
dev-server:
	@go run ./cmd/server

# Run Vite frontend dev server with HMR
dev-web:
	@cd web && npm run dev

# Flutter client checks and web build
app-format:
	@cd app && $(DART) --suppress-analytics format --output=none --set-exit-if-changed lib test

app-analyze:
	@cd app && $(FLUTTER) pub get && $(FLUTTER) analyze

app-test:
	@cd app && $(FLUTTER) test

app-web:
	@cd app && $(FLUTTER) build web

app-dev:
	@cd app && $(FLUTTER) run -d web-server --web-port 5174

# Clean generated build artifacts and restore fallback index
clean:
	@rm -rf bin
	@rm -rf web/dist/*
	@echo '<!doctype html><html lang="zh-CN"><head><meta charset="UTF-8" /><title>Ledger</title></head><body><div id="root"></div></body></html>' > web/dist/index.html
