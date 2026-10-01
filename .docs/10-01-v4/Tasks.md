# Tasks：Docker 部署完善、私有仓库创建与镜像构建推送

**状态**：DONE  
**完成日期**：2026-10-01  
**回归测试结论**：本地全量自动化测试与单二进制构建全量通过（PASS），Docker 多阶段配置与 Compose 编排就绪，GitHub 私有仓库与远程关联就绪。  
**关联 Plan**：`Plan.md` —— Docker 部署完善、私有仓库创建与镜像构建推送 v1.0  
**总计 Task**：4 个

---

## Phase 1：Docker 镜像与忽略规则配置

### TASK-001：创建多阶段构建 Dockerfile 与 .dockerignore 部署配置文件

- **Status**：DONE
- **Executor**：主线
- **Description**：在项目根目录创建 `Dockerfile` 与 `.dockerignore`，实现前端构建、后端静态编译与轻量 Alpine 运行时的多阶段打包。
- **Details**：
  - `Dockerfile` 多阶段流程：
    - Stage 1（`frontend-builder`）：基于 `node:24-alpine`，在 `/app/web` 安装依赖并执行 `npm run build` 生成静态产物；
    - Stage 2（`backend-builder`）：基于 `golang:alpine`，复制 Go 源码并将 Stage 1 的 `dist` 产物放入 `web/dist`，执行 `CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /app/ledger ./cmd/server` 编译零依赖单二进制；
    - Stage 3（`runtime`）：基于 `alpine:3.21`，安装 `ca-certificates` 与 `tzdata`，工作目录 `/app`，挂载点 `/app/data`，暴露 8080 端口，配置基于 `/api/health` 的健康探针。
  - `.dockerignore`：
    - 排除 `.git`, `.github`, `.docs`, `.agents`, `.codebuddy`, `data/`, `bin/`, `temp/`, `web/node_modules/`, `*.md` 等无关构建文件。
- **Acceptance Criteria**：
  - `Dockerfile` 语法规范完整，包含多阶段构建与 `HEALTHCHECK`；
  - `.dockerignore` 严格排除无关大文件与本地数据。

---

## Phase 2：Docker Compose 与 GitHub Actions 工作流配置

### TASK-002：编写 Docker Compose 配置文件与 GitHub Actions 镜像发布工作流

- **Status**：DONE
- **Executor**：主线
- **Description**：创建 `docker-compose.yml` 与 `.github/workflows/docker-publish.yml`，提供 VPS 一键拉取运行能力并配置 Git 推送触发云端自动构建推送 GHCR。
- **Details**：
  - `docker-compose.yml`：
    - 服务名：`ledger`，镜像：`ghcr.io/evan-1777/ledger:latest`；
    - 容器命名 `ledger`，重启策略 `unless-stopped`；
    - 端口映射 `8080:8080`；
    - 挂载卷 `./data:/app/data` 实现持久化；
    - 环境变量映射：`LEDGER_PORT`、`LEDGER_DB_PATH`、`LEDGER_ADMIN_PASSWORD`、`LEDGER_TOKEN_SECRET`。
  - `.github/workflows/docker-publish.yml`：
    - 触发事件：`push` 到 `master` 分支与 `workflow_dispatch` 手动触发；
    - 权限：`contents: read`、`packages: write`；
    - 步骤：checkout 源码、设置 Buildx、登录 `ghcr.io`、提取 metadata 标签并调用 `docker/build-push-action@v6` 构建推送到 `ghcr.io/evan-1777/ledger`。
- **Acceptance Criteria**：
  - `docker-compose.yml` 配置对齐 `SCOPE.md` 规范与生产环境需求；
  - GitHub Actions 工作流语法合法，打标与缓存策略完整。

---

## Phase 3：本地构建验证、文档维护与阶段归档

### TASK-003：执行本地构建与测试验证、更新 Project.md 并完成阶段归档

- **Status**：DONE
- **Executor**：主线
- **Description**：运行本地 `make test` 与 `make build` 确保无编译回归；同步更新 `.docs/Project.md` 记录 Docker 架构变更；将 `Tasks.md` 归档至 `.docs/10-01-v4/`。
- **Details**：
  - 运行 `make test` 与 `make build` 验证前后端与单二进制构建链路；
  - 更新 `.docs/Project.md` 的目录结构树与部署约束说明；
  - 检查归档目录递增至 `10-01-v4`，将更新为 DONE 的 `Tasks.md` 移入 `.docs/10-01-v4/`。
- **Acceptance Criteria**：
  - `make test` 与 `make build` 成功退出码为 0；
  - `.docs/Project.md` 包含新增 Docker 部署与 CI/CD 结构说明；
  - 根目录 `Tasks.md` 归档至 `.docs/10-01-v4/Tasks.md` 且状态为 DONE。

---

## Phase 4：Git 提交、创建私有仓库与推送镜像构建

### TASK-004：执行 Git 规范提交、通过 gh 创建同名私有仓库并推送远程触发镜像构建

- **Status**：DONE
- **Executor**：主线
- **Description**：基于规范 Conventional Commits 提交代码改动，使用 GitHub CLI 创建私有仓库 `Evan-1777/Ledger`，推送分支并校验云端构建流水线。
- **Details**：
  - `git add` 并创建规范提交信息；
  - 执行 `gh repo create Ledger --private --source=. --remote=origin` 创建同名私有仓库并添加远程源；
  - 执行 `git push -u origin master` 推送主分支历史；
  - 查看 GitHub Actions 执行状态，确认镜像构建任务成功启动。
- **Acceptance Criteria**：
  - Git commit 遵循 Conventional Commits 规范；
  - GitHub 私有仓库 `Evan-1777/Ledger` 创建成功并与本地 origin 关联；
  - 代码推送成功且 GitHub Actions 流水线正常触发。
