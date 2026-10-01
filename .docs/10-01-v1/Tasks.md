# Tasks：Ledger 工程骨架初始化与单二进制构建链路

**关联 Plan**：`Plan.md` —— Ledger 工程骨架初始化与单二进制构建链路 v1.0  
**总计 Task**：12 个

---

## Phase 1：后端骨架与 SQLite 数据层初始化

### TASK-001：初始化 Go 模块与基础目录结构

- **Status**：DONE
- **Executor**：主线
- **Description**：创建 Go 模块 `ledger`，建立 `cmd/server`、`internal/config`、`internal/db`、`internal/server` 等标准目录。
- **Details**：
  - 运行 `go mod init ledger` 初始化 Go 1.27 模块
  - 创建对应的源码目录结构
- **Acceptance Criteria**：
  - `go.mod` 成功生成
  - 目录结构规范完整

### TASK-002：实现配置模块与 SQLite 连接初始化

- **Status**：DONE
- **Executor**：主线
- **Description**：引入 `modernc.org/sqlite` 依赖，实现环境配置读取与带 WAL 模式的 SQLite 连接初始化。
- **Details**：
  - `internal/config/config.go`：支持读取环境变量 `LEDGER_PORT`（默认 8080）与 `LEDGER_DB_PATH`（默认 `data/ledger.db`）
  - `internal/db/db.go`：实现 `InitDB(path string) (*sql.DB, error)`，开启 WAL 模式、busy_timeout、连接池限制，并执行连接 Ping 验证
- **Acceptance Criteria**：
  - 执行测试可成功创建并连接测试数据库
  - WAL 模式生效且无报错

### TASK-003：实现基础 HTTP 服务框架与健康检查接口

- **Status**：DONE
- **Executor**：主线
- **Description**：实现 HTTP 路由与健康检查端点 `GET /api/health`，并编写单元测试。
- **Details**：
  - `internal/server/server.go`：定义 `Server` 结构体，支持路由注册、数据库状态检查
  - 提供 `GET /api/health`，返回 JSON `{ "status": "ok", "db": "connected", "version": "dev" }`
  - 编写 `internal/server/server_test.go` 验证健康检查接口返回 200 及预期 JSON
- **Acceptance Criteria**：
  - `go test ./internal/server` 单元测试通过

---

## Phase 2：前端工程脚手架搭建

### TASK-004：初始化 Vite + React + TypeScript 前端项目

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/` 目录初始化 React + TypeScript + Vite 项目骨架。
- **Details**：
  - 配置 `web/package.json`（依赖 react, react-dom, vite, typescript 等）
  - 配置 `web/vite.config.ts`、`web/tsconfig.json`、`web/index.html`
- **Acceptance Criteria**：
  - `web/` 下 `npm install` 成功，配置无语法错误

### TASK-005：配置 Tailwind CSS 与 Vite 反向代理

- **Status**：DONE
- **Executor**：主线
- **Description**：在前端项目中引入 Tailwind CSS 配置，并在 `vite.config.ts` 中配置 `/api` 代理到后端 `:8080`。
- **Details**：
  - 安装并配置 Tailwind CSS 样式管道
  - `vite.config.ts` 中添加 `server.proxy` 配置，指向 `http://localhost:8080`
- **Acceptance Criteria**：
  - Tailwind 样式指令正常解析
  - Vite 开发配置包含代理声明

### TASK-006：编写极简前端脚手架页面

- **Status**：DONE
- **Executor**：主线
- **Description**：编写 `web/src/App.tsx` 与入口文件，实现极简骨架展示与 API 连通性测试。
- **Details**：
  - 使用 Tailwind 基础类名渲染极简骨架指示卡片（显示应用名称 Ledger 与后端健康状态）
  - 请求 `/api/health` 并在界面反馈连通状态
  - 不包含任何记账业务、账本、表单或多余界面逻辑
- **Acceptance Criteria**：
  - `npm run build` 生成 `web/dist`
  - 产出产物包含静态 HTML、JS、CSS

---

## Phase 3：前后端 Embed 嵌入与单二进制构建链路打通

### TASK-007：实现前端静态资源 Go Embed 绑定

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/` 包中实现 `embed.go`，将 `dist` 目录嵌入 Go 二进制，并设置防空机制。
- **Details**：
  - 编写 `web/embed.go`，使用 `//go:embed all:dist` 暴露 `DistFS`
  - 保证在 `dist/` 为空时具备占位以防编译失败
- **Acceptance Criteria**：
  - Go 代码可通过 `web.DistFS` 读取打包静态文件

### TASK-008：实现 SPA 静态文件服务与路由回退

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/server` 中将 `web.DistFS` 挂载为 HTTP 静态文件服务，并支持 SPA 路由回退。
- **Details**：
  - 优先响应 `/api/` 路由
  - 对存在于 `web.DistFS` 的静态资源直接提供服务
  - 对不存在的客户端路由自动回退到 `index.html`
- **Acceptance Criteria**：
  - 访问 `/` 返回前端 `index.html`
  - 访问任意前端虚拟路由如 `/dashboard` 依然正确回退返回 `index.html`
  - 访问 `/api/health` 正常返回 JSON，不被回退拦截

### TASK-009：编写 Makefile 编排全流程单二进制构建

- **Status**：DONE
- **Executor**：主线
- **Description**：在项目根目录编写 `Makefile`，支持前端编译、单二进制打包、测试与清理指令。
- **Details**：
  - `make build-web`：编译前端产物至 `web/dist`
  - `make build`：先执行 `build-web`，再执行 `go build -o bin/ledger ./cmd/server`
  - `make test`：执行后端测试与前端类型检查
  - `make clean`：清理 `bin/`、`web/dist` 与临时构建产物
- **Acceptance Criteria**：
  - 执行 `make build` 产出单一二进制 `bin/ledger`
  - 执行 `make clean` 干净清理产物

---

## Phase 4：整体验证、文档建立与工程归档

### TASK-010：执行单二进制独立运行与集成验证

- **Status**：DONE
- **Executor**：主线
- **Description**：启动编译后的 `bin/ledger`，通过 curl/HTTP 请求验证静态页面与 API 接口。
- **Details**：
  - 验证根路径 `/` 渲染前端脚手架
  - 验证 `/api/health` 正常返回
  - 验证 SQLite 数据库文件自动创建在指定路径
  - 测试正常退出后清理
- **Acceptance Criteria**：
  - 单二进制独立启动无依赖
  - 前后端均能正常响应

### TASK-011：建立 Project.md 并完善 .gitignore

- **Status**：DONE
- **Executor**：主线
- **Description**：依据实际工程结构创建 `.docs/Project.md`，完善根目录与子目录 `.gitignore`。
- **Details**：
  - 按 `.docs/Project.example.md` 规范生成 `.docs/Project.md`
  - 忽略 `bin/`、`web/dist/`、`web/node_modules/`、`*.db`、`*.db-wal`、`*.db-shm`
- **Acceptance Criteria**：
  - `.docs/Project.md` 准确描述当前工程
  - `git status` 无多余临时文件或依赖残留

### TASK-012：阶段归档与 Git 提交

- **Status**：DONE
- **Executor**：主线
- **Description**：更新 Plan 与 Tasks 为 DONE，归档至 `.docs/10-01-v1/`，按 Conventional Commits 提交。
- **Details**：
  - 归档 `Plan.md` 与 `Tasks.md` 至 `.docs/10-01-v1/`
  - 验证根目录无残留
  - 执行 git commit
- **Acceptance Criteria**：
  - `.docs/10-01-v1/` 包含已完成的 `Plan.md` 与 `Tasks.md`
  - git log 包含规范的中文提交信息
