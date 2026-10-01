# Project

> 项目的单一事实来源，供 Agent 动手前建立全局认知。定位与设计原则见 `SCOPE.md`，工作流规则见 `AGENTS.md`。

## 概述

- **定位**：轻量高颜值个性化记账 Web 应用，基于 Go + React + Vite + Tailwind + SQLite，单二进制交付。
- **阶段**：基础脚手架已就绪，等待个性化业务与界面开发
- **非目标**：预设记账业务模式、复杂云服务集成、重型商业账务流转

## 环境与运行

- **平台**：Linux x86_64（本地编译与测试），云端 CI 负责发布构建
- **运行时**：
  - 后端：Go 1.27
  - 前端：Node.js 24 + npm 11
  - 存储：SQLite（纯 Go 驱动 `modernc.org/sqlite`，无 CGO 依赖）
- **版本管理**：Git；Conventional Commits（英文类型前缀 + 中文详细描述）
- **运行**：
  - 全流程构建：`make build`（生成 `bin/ledger`）
  - 单独运行后端：`make dev-server` 或 `go run ./cmd/server`
  - 单独运行前端开发服务：`make dev-web` 或 `cd web && npm run dev`
  - 启动二进制：`bin/ledger`（默认监听 `http://localhost:8080`）
- **测试**：
  - 全量测试：`make test`（涵盖后端 `go test ./...` 与前端 `tsc -b --noEmit`）
- ★ 数据库默认位于 `data/ledger.db`，可通过环境变量 `LEDGER_DB_PATH` 覆盖；测试通过临时目录进行，不污染真实数据
- ★ 前端开发服务器通过 Vite 代理将 `/api` 请求转发至后端口 `8080`

## 结构

```
Ledger/
├─ cmd/
│  └─ server/
│     └─ main.go         # 应用程序唯一入口，加载配置、初始化 DB、注册路由并处理优雅退出
├─ internal/
│  ├─ config/
│  │  └─ config.go       # 环境变量配置加载（LEDGER_PORT, LEDGER_DB_PATH）
│  ├─ db/
│  │  ├─ db.go           # SQLite 连接初始化（WAL 模式、忙超时设置、连接池）
│  │  └─ db_test.go      # 数据层初始化与 WAL 模式测试
│  └─ server/
│     ├─ server.go       # HTTP 路由、健康检查（/api/health）与 SPA 静态文件回退服务
│     └─ server_test.go  # API 与 SPA 静态文件服务测试
├─ web/                  # 前端 React + Vite + Tailwind + TypeScript 工程
│  ├─ src/
│  │  ├─ App.tsx         # 极简脚手架状态展示组件（连通性检测，无业务逻辑）
│  │  ├─ index.css       # Tailwind CSS 根样式引入
│  │  └─ main.tsx        # React 挂载入口
│  ├─ embed.go           # Go embed 静态资源绑定（暴露 DistFS）
│  ├─ embed_test.go      # embed 资源可读性验证
│  ├─ vite.config.ts     # Vite 配置（Tailwind 插件、/api 反向代理）
│  ├─ package.json       # 前端依赖配置
│  └─ tsconfig.json      # TypeScript 配置
├─ Makefile              # 统一构建编排（build, test, dev, clean）
└─ .docs/                # 项目文档与阶段归档
```

- **数据流**：浏览器请求 → HTTP 路由分流：
  - `/api/*` → 后端 Handler（读取/写入 SQLite） → JSON 响应
  - 非 API 请求 → `web.DistFS`（优先匹配静态文件；未匹配则回退至 `index.html` 交付客户端路由）
- **依赖方向**：`cmd/server` 组合 `internal/config`、`internal/db`、`internal/server` 与 `web`；各 `internal/*` 模块间解耦，不反向依赖 `cmd`。

## 约定

- **命名**：Go 包与文件 snake_case，导出的类型与函数 PascalCase；TypeScript 组件 PascalCase，工具函数 camelCase
- **语言**：用户可见文本用中文；代码注释、提交前缀遵循英文约定
- **错误处理**：后端内部错误统一包装，对外返回对应 HTTP 状态码与结构化 JSON；前端通过标准化 fetch 统一捕获
- **日志**：Go 标准库 `log`，输出清晰的时间戳与结构化上下文信息

## 约束与决策

- 2026-10-01 采用纯 Go SQLite 驱动 `modernc.org/sqlite` 代替 `go-sqlite3`——消除 CGO 依赖，极大简化跨平台编译与轻量级 Docker 镜像构建
- 2026-10-01 采用 Go `embed.FS` 嵌入前端 `dist` 产物——实现单个独立可执行文件的零外部依赖交付
- 2026-10-01 纯粹脚手架交付，不内置预设记账模型——完全保留个性化业务设计的空白与灵活性

## 术语

- **单二进制 (Single Binary)** = 包含 Go 后端编译产物与内嵌前端静态资源的独立单一可执行程序
- **SPA 回退 (SPA Fallback)** = 当浏览器请求非 API 且非静态资源的路径时，服务端返回 `index.html`，交由客户端 React 处理路由

## 维护

| 变更 | 同步章节 |
|---|---|
| 运行、测试方式或环境前提变化 | 环境与运行 |
| 依赖增删或升级 | 环境与运行；属关键选型时同步「约束与决策」 |
| 模块增删、重构，依赖方向变化 | 结构 |
| 命名、语言、日志规范调整 | 约定 |
| 新坑、新约束、选型定型 | 约束与决策 |
| 外部服务接入或下线 | 外部集成 |
| 新增项目特有名词 | 术语 |
