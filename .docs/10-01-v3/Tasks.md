# Tasks：复审问题修复与工程健壮性收敛

**关联 Plan**：`Plan.md` —— 复审问题修复与工程健壮性收敛 v1.0  
**总计 Task**：4 个

---

## Phase 1：SQLite 连接池 DSN 参数标准化与外键生效加固

### TASK-001：改造 SQLite 初始化为 DSN 参数注入并在单测中强制断言多连接外键生效

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/db/db.go` 中，将 `PRAGMA foreign_keys = ON;`、`PRAGMA busy_timeout = 5000;`、`PRAGMA synchronous = NORMAL;` 迁移至 `sql.Open("sqlite", dsn)` 的 DSN 查询参数中，并在 `internal/db/db_test.go` 中补充多连接外键与 busy_timeout 恒定生效的断言。
- **Details**：
  - DSN 构造：`fmt.Sprintf("file:%s?_pragma=foreign_keys(1)&_pragma=busy_timeout(5000)&_pragma=synchronous(NORMAL)", dbPath)`；
  - 保留 `PRAGMA journal_mode = WAL;` 在迁移逻辑或初次启动时执行（该参数为数据库文件级别持久化）；
  - 在 `internal/db/db_test.go` 中：占用连接 1，借出连接 2，分别验证两个独立连接上的 `PRAGMA foreign_keys` 均为 1，且在连接 2 上尝试插入孤儿账单记录严格触发外键约束报错。
- **Acceptance Criteria**：
  - 连接池中任意连接 `PRAGMA foreign_keys` 为 1；
  - `internal/db/db_test.go` 针对第二连接的测试用例绿色通过。

---

## Phase 2：统计接口错误透传阻断与 CRUD 错误码精确分流

### TASK-002：实现统计接口错误阻断与 CRUD 错误码分流（400 vs 500）

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/server/stats.go` 中消除所有吞错逻辑，数据库查询失败统一返回 500；在 `internal/server/settings.go` 与 `internal/server/transactions.go` 中准确区分 400（唯一约束违例）与 500（未预期数据库故障）。
- **Details**：
  - `stats.go`：对 `weekExpense`、`monthExpense`、`lastMonthExpense`、`monthIncome`、分类聚合 `catRows`、细分标签聚合 `tagRows`、渠道聚合 `pmRows` 以及 6 个月月度趋势查询全面做 `err != nil` 检查，任意一处失败即刻调用 `writeJSONError(w, http.StatusInternalServerError, ...)` 返回，杜绝假零数据；
  - `settings.go` 与 `transactions.go`：提供错误分类辅助判断，若底层错误属于唯一约束冲突（如包含 `UNIQUE constraint failed`），返回 400 及友好提示；若为其他数据库异常，返回 500 及系统异常提示；外键引用的前置存在性检查若查询报错直接向上抛出 500。
- **Acceptance Criteria**：
  - 模拟数据库故障或 closed DB 时请求 `/api/stats/summary` 明确返回 500 状态码；
  - 唯一名称冲突返回 400，其他未预期 DB 错误返回 500；
  - `server_test.go` 覆盖统计错误阻断与错误码分流测试。

---

## Phase 3：零星健壮性与前端跨年展示细节收敛

### TASK-003：清理配置死代码并在前端 StreamPage 补齐跨年日期格式

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/config/config.go` 中移除 `rand.Read` 的冗余 fallback secret 死代码；在 `web/src/pages/StreamPage.tsx` 中为非当年交易日期补齐年份显示。
- **Details**：
  - `internal/config/config.go`：简化 TokenSecret 生成分支，移除不可达的 fallback 逻辑；
  - `web/src/pages/StreamPage.tsx`：更新 `getDayLabel` 函数，当日期与当前年份不同时返回 `YYYY年M月D日`，避免跨年份同月同日产生视觉歧义。
- **Acceptance Criteria**：
  - `config.go` 代码更加精简，无多余防御死分支；
  - 前端类型检查 `npm run lint` 零警告；
  - 跨年份历史账单卡片分组标题明确包含年份。

---

## Phase 4：全量自动化回归测试与单二进制构建验证

### TASK-004：执行全量测试套件、单二进制构建与自动化冒烟验证及文档维护

- **Status**：DONE
- **Executor**：主线
- **Description**：执行 `make test` 与 `make build` 编译单二进制，并运行全链路自动化 curl 冒烟测试，同步更新 `.docs/Project.md`。
- **Details**：
  - 执行 `go test -v ./...` 确保所有新增与修改单元/集成测试通过；
  - 执行 `npm run lint` 确保前端类型严密；
  - 执行 `make build` 产出 `bin/ledger`；
  - 运行自动化 curl 冒烟验证测试独立二进制在干净环境下的运行；
  - 更新 `.docs/Project.md` 约束与说明。
- **Acceptance Criteria**：
  - `make test` 零报错；
  - `bin/ledger` 冒烟 5 项验证全绿；
  - `.docs/Project.md` 与实际代码保持绝对一致。

---

## 交付与回归结论

- **完成日期**：2026-10-01
- **状态**：DONE
- **回归测试结论**：
  1. `make test` 全面通过：后端单元与集成测试（涵盖多连接外键生效、统计异常阻断、错误码分流）全绿，前端 `tsc -b --noEmit` 零告警；
  2. `make build` 成功打包前端静态产物并生成 12MB 单二进制 `bin/ledger`；
  3. 独立干净环境自动化 curl 冒烟测试 7 项验证（健康检查、SPA 入口、鉴权防爆破、Token 鉴权、统计汇总、400 唯一冲突拦截、支付渠道列表）全部通过；
  4. `.docs/Project.md` 单一事实来源完成同步维护。
