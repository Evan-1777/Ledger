# 多阶段构建：前端构建 + Go 零依赖静态编译 + Alpine 轻量运行时

# ---- 前端构建阶段 ----
FROM node:24-alpine AS frontend-builder
WORKDIR /app/web
COPY web/package.json web/package-lock.json ./
RUN npm ci
COPY web/ ./
RUN npm run build

# ---- Go 后端构建阶段 ----
FROM golang:1.27-alpine AS backend-builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY cmd/ ./cmd/
COPY internal/ ./internal/
COPY web/embed.go ./web/
COPY --from=frontend-builder /app/web/dist ./web/dist
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /app/ledger ./cmd/server

# ---- 生产运行阶段 ----
FROM alpine:3.21
RUN apk --no-cache add ca-certificates tzdata
WORKDIR /app

ENV LEDGER_PORT=8080
ENV LEDGER_DB_PATH=/app/data/ledger.db

COPY --from=backend-builder /app/ledger /app/ledger

RUN mkdir -p /app/data
VOLUME ["/app/data"]
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:${LEDGER_PORT:-8080}/api/health || exit 1

ENTRYPOINT ["/app/ledger"]
