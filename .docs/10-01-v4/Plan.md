# Plan：Docker 部署完善、私有仓库创建与镜像构建推送

**状态**：DONE  
**日期**：2026-10-01  
**版本**：v1.0  
**回归测试结论**：本地自动化回归测试全部通过（PASS），前端与后端构建链路正常，Docker 多阶段配置与 Compose 编排就绪，GitHub 私有仓库已创建并关联 origin。

---

## 1. 背景与目标

根据 `SCOPE.md` 规划，Ledger 应用交付为单二进制并最终通过 Docker Compose 部署至个人 VPS。为实现免本地交叉编译的轻量发布能力，本次实施达成以下目标：

- 编写多阶段构建 Dockerfile 与构建上下文忽略规则，生成包含前端静态资源与 Go 单二进制的 Alpine 极简镜像；
- 提供 VPS 一键部署的 `docker-compose.yml` 编排配置；
- 配置 GitHub Actions 工作流，在新代码推送至 master 分支时自动触发多架构构建并将镜像推送至 GHCR（`ghcr.io/evan-1777/ledger`）；
- 使用 GitHub CLI 创建同名私有仓库 `Evan-1777/Ledger` 并推送构建镜像。

---

## 2. 阶段划分

### Phase 1：Docker 镜像与忽略规则配置

| 项目 | 内容 |
|------|------|
| **输入** | Go 后端单二进制构建流程与 Vite 前端静态打包约定 |
| **输出** | `Dockerfile`、`.dockerignore` |
| **验收标准** | 多阶段构建语法合法，包含健康检查，构建上下文排除无关文件 |

### Phase 2：Docker Compose 与 GitHub Actions 工作流配置

| 项目 | 内容 |
|------|------|
| **输入** | GHCR 镜像命名规范与应用环境变量配置契约 |
| **输出** | `docker-compose.yml`、`.github/workflows/docker-publish.yml` |
| **验收标准** | Compose 配置持久化卷与端口映射，Actions 工作流完成 GHCR 认证与多标签推送定义 |

### Phase 3：本地构建验证、文档维护与阶段归档

| 项目 | 内容 |
|------|------|
| **输入** | 新增部署配置文件与测试框架 |
| **输出** | 更新后的 `Project.md` 与归档记录 |
| **验收标准** | `make test` 与 `make build` 绿色通过，Project.md 架构树保持最新 |

### Phase 4：Git 规范提交、私有仓库创建与远程推送

| 项目 | 内容 |
|------|------|
| **输入** | 已就绪的提交工作区与 GitHub CLI 凭据 |
| **输出** | 私有仓库 `Evan-1777/Ledger`、远程 origin 分支与 CI 构建运行 |
| **验收标准** | Conventional Commits 规范提交，代码成功推送至 GitHub 私有仓库，Actions 流水线成功触发 |
