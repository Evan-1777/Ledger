> 关联 Plan：`Plan.md` —— 账单退款机制 v1.0
>
> 执行主体：Phase 1 / 2 / 4 归主线，Phase 3 移交 Subagent: executor。

---

# Tasks：账单退款机制

**关联 Plan**：`Plan.md` —— 账单退款机制 v1.0  
**总计 Task**：17 个（全部 DONE，2026-11-12）  
**回归测试结论**：见 `Plan.md` §9——`make test`、`make app-format`、`make app-analyze`、`make app-test` 退出码均为 0，Flutter 全量 220 项通过，浏览器 1280px 与 320px 手验退款全流程通过。

---

## Phase 1：退款字段与服务端契约

### TASK-001：为 transactions 增加退款时间戳列并热迁移

- **Status**：DONE
- **完成**：2026-11-12
- **Executor**：主线
- **优先级**：P0
- **依赖**：无
- **Description**：在 `internal/db/db.go` 的 transactions 建表语句新增可空列 `refunded_at TEXT DEFAULT NULL`，并在 `migrateTransactionsColumns` 中探针补列。
- **Details**：
  - 建表 schema 的 transactions 追加 `refunded_at TEXT DEFAULT NULL`。
  - `PRAGMA table_info(transactions)` 扫描新增 `refunded_at` 探测标志；缺列时执行 `ALTER TABLE transactions ADD COLUMN refunded_at TEXT DEFAULT NULL`。
  - 探针与既有 type / source_payment_method_id / fee_cents 探针并列，位于 `seed_initialized` 判断之前。
  - 不新增索引：退款条件与既有 transacted_at / type 组合，个人账本数据量下无必要。
- **Acceptance Criteria**：
  - 新库建表后 `PRAGMA table_info(transactions)` 含 `refunded_at`。
  - 以不含该列的老库执行 InitDB 后该列存在，既有数据行数不变。
  - `go test ./internal/db/...` 通过。

### TASK-002：交易模型与查询返回退款状态

- **Status**：DONE
- **完成**：2026-11-12
- **Executor**：主线
- **优先级**：P0
- **依赖**：TASK-001
- **Description**：在 `internal/server/transactions.go` 的 `Transaction` 结构体新增可空退款时间字段，并在列表与单条查询的 SELECT / Scan 中带回该列。
- **Details**：
  - 字段为 `*string`，JSON 键 `refunded_at`，标 `omitempty`。
  - `handleListTransactions` 与 `getTransactionByID` 的 SELECT 追加 `t.refunded_at`，用 `sql.NullString` 承接后按需转指针。
  - 退款为 NULL 时省略 JSON 键，未退款账单响应保持既有结构。
  - `handleUpdateTransaction` 的 UPDATE 语句不改动 `refunded_at`，编辑账单不会清除退款状态。
- **Acceptance Criteria**：
  - 未退款账单的列表与单条响应不含 `refunded_at`。
  - 标记退款后，列表与单条响应均返回非空 `refunded_at`。
  - 编辑已退款账单后 `refunded_at` 保持不变。

### TASK-003：退款与撤销退款端点

- **Status**：DONE
- **完成**：2026-11-12
- **Executor**：主线
- **优先级**：P0
- **依赖**：TASK-002
- **Description**：在 `internal/server/transactions.go` 新增退款与撤销退款处理器，并在 `internal/server/server.go` 注册路由。
- **Details**：
  - 路由：`POST /api/transactions/{id}/refund` 与 `DELETE /api/transactions/{id}/refund`，均经 `requireAuth` 守卫。
  - 共用实现：解析 id（非数字返回 400，与既有更新 / 删除端点一致）→ `getTransactionByID` 取当前账单 → 不存在返回 404；类型非 `expense` / `income` 返回 400，错误信息 `only expense or income transactions can be refunded`。
  - 退款执行 `UPDATE transactions SET refunded_at = COALESCE(refunded_at, ?) WHERE id = ?`（幂等，重复退款不刷新时间）；撤销执行 `UPDATE transactions SET refunded_at = NULL WHERE id = ?`。
  - 两者均以 200 返回更新后的完整账单。
  - 将 `getTransactionByID` 的未找到错误改为包裹 `sql.ErrNoRows`（`fmt.Errorf("transaction not found: %w", sql.ErrNoRows)`），供 handler 以 `errors.Is` 判定 404；既有调用方不触发该分支，行为不变。
- **Acceptance Criteria**：
  - POST 退款返回 200 且响应 `refunded_at` 非空。
  - 重复 POST 返回 200 且 `refunded_at` 与首次一致。
  - DELETE 撤销返回 200 且响应省略 `refunded_at`。
  - 对转账或还款行执行 POST / DELETE 均返回 400。
  - 对不存在的 id 返回 404；id 非数字返回 400；缺 Token 返回 401。

### TASK-004：统计聚合排除已退款账单

- **Status**：DONE
- **完成**：2026-11-12
- **Executor**：主线
- **优先级**：P0
- **依赖**：TASK-003
- **Description**：在 `internal/server/stats.go` 的全部金额聚合处加入 `t.refunded_at IS NULL` 条件。
- **Details**：
  - `sumByType`、`countByType`、`categoryDistribution` 的两段查询、`paymentDistribution` 的 WHERE 追加 `AND t.refunded_at IS NULL`。
  - `handleStatsSummary` 资产负债组合主查询的 `LEFT JOIN transactions t ON t.payment_method_id = pm.id` 追加 `AND t.refunded_at IS NULL`。
  - source_repayment_sum / source_transfer_sum 子查询限定 `type = 'repayment'` / `'transfer'`，而这两类不可退款，无需改动。
- **Acceptance Criteria**：
  - 退款一笔支出后，当月支出、分类分布、渠道分布与对应资产余额同步回落。
  - 撤销退款后上述数值恢复。
  - 收入退款与撤销对称成立。

### TASK-005：服务端退款集成测试

- **Status**：DONE
- **完成**：2026-11-12
- **Executor**：主线
- **优先级**：P0
- **依赖**：TASK-004
- **Description**：在 `internal/server/server_test.go` 新增 `TestTransactionRefundFlow`，并在 `internal/db/db_test.go` 的老库升级用例补列断言。
- **Details**：
  - 主链路：创建支出 ¥100 → 当月支出 100、资产余额 -100、分类与渠道分布含该笔；POST 退款 → 该行仍出现在默认列表响应（最近 100 条窗口）中且 `refunded_at` 非空、当月支出 0、余额 0、分布为空；重复退款时间戳不变；DELETE 撤销 → 当月支出与余额恢复 100。
  - 对称与守卫：收入退款与撤销；转账 / 还款退款 400；不存在 id 404；未鉴权 401。
  - `TestTransactionsMigration` 补断言老库升级后含 `refunded_at` 列。
- **Acceptance Criteria**：`go test ./...` 全部通过。

---

## Phase 2：Web 端退款交互

### TASK-006：Web API 客户端退款方法与字段

- **Status**：DONE
- **完成**：2026-11-12
- **Executor**：主线
- **优先级**：P1
- **依赖**：TASK-003
- **Description**：`web/src/lib/api.ts` 的 `Transaction` 接口增加 `refunded_at?: string | null`，并新增 `refundTransaction(id)` 与 `cancelRefundTransaction(id)`。
- **Details**：
  - `refundTransaction` → `POST /api/transactions/${id}/refund`；`cancelRefundTransaction` → `DELETE` 同路径。
  - 两者返回 `Promise<Transaction>`，走既有 `request` 封装（自动带 Token 与 401 拦截）。
- **Acceptance Criteria**：`cd web && npx tsc -b --noEmit` 通过；新增方法与后端端点、响应字段一致。

### TASK-007：Web 流水纯函数退款谓词与测试

- **Status**：DONE
- **完成**：2026-11-12
- **Executor**：主线
- **优先级**：P1
- **依赖**：TASK-006
- **Description**：`web/src/pages/streamUtils.ts` 新增导出谓词 `isRefunded`，`web/test/stream.test.ts` 补测试。
- **Details**：
  - `isRefunded(tx: { refunded_at?: string | null }): boolean`，非空字符串为 true。
  - 供月头条、日小计与行渲染统一消费，避免口径分散。
- **Acceptance Criteria**：`cd web && npm run test` 通过；用例覆盖 undefined / null / 空串为 false、有效时间戳为 true。

### TASK-008：Web 流水页退款入口、标识与聚合排除

- **Status**：DONE
- **完成**：2026-11-12
- **Executor**：主线
- **优先级**：P1
- **依赖**：TASK-007
- **Description**：`web/src/pages/StreamPage.tsx` 排除已退款账单的本地聚合，并在行内提供退款入口与已退款标识。
- **Details**：
  - `computeMonthHeadline` 与日小计累加跳过 `isRefunded(item)`。
  - 行内操作区对 `expense` / `income` 增加退款 IconButton：未退款 label「退款」，已退款 label「取消退款」；转账与还款不渲染。
  - 已退款行在标题旁渲染「已退款」Chip，金额加 `line-through` 并降低不透明度。
  - 新增 prop `onToggleRefund: (tx: Transaction) => void`，由 App 注入。
  - 若 320px 视口出现横向溢出，将 `<640px` 行内操作按钮收紧为 26px，不新增菜单层。
- **Acceptance Criteria**：
  - 已退款账单不计入月头条与日小计。
  - 退款入口仅对支出 / 收入渲染，且文案随退款状态切换。
  - 320px 视口下流水行无横向溢出。
  - `cd web && npx tsc -b --noEmit` 通过。

### TASK-009：App 层退款处理与退款图标

- **Status**：DONE
- **完成**：2026-11-12
- **Executor**：主线
- **优先级**：P1
- **依赖**：TASK-008
- **Description**：`web/src/App.tsx` 注入退款处理，`web/src/components/Icons.tsx` 新增 `RefundIcon`。
- **Details**：
  - `handleToggleRefund(tx)`：按 `tx.refunded_at` 选择退款或撤销退款；成功后 Toast「已标记退款」/「已撤销退款」并调用 `fetchTransactions()`；失败 Toast 错误信息。
  - 向 `StreamPage` 传入 `onToggleRefund`。
  - `RefundIcon` 采用与既有图标一致的 14px 线帽描边（回转箭头）并导出。
- **Acceptance Criteria**：
  - 退款与撤销后流水与月头条刷新，Toast 文案正确。
  - 失败路径展示错误 Toast，不静默。
  - `cd web && npm run build` 通过。

---

## Phase 3：Android 客户端退款交互（Subagent: executor）

### TASK-010：客户端模型与接口补退款字段 / 方法

- **Status**：DONE
- **完成**：2026-11-12
- **Executor**：Subagent: executor
- **优先级**：P1
- **依赖**：TASK-003
- **Description**：在 `app/lib/core/api/models.dart` 与 `app/lib/core/api/api_client.dart` 补齐退款状态与动作。
- **Details**：
  - `Transaction` 增加 `final DateTime? refundedAt;` 与 `bool get isRefunded => refundedAt != null;`；`fromJson` 对缺失 / null 容错为 null，`toJson` 写出 `refunded_at`。
  - `ApiClient` 新增 `refundTransaction(int id)`（POST）与 `cancelRefundTransaction(int id)`（DELETE），返回 `Transaction`。
  - `app/test/core/api_client_test.dart` 补请求方法与路径断言。
- **Acceptance Criteria**：`flutter analyze` 通过；`flutter test test/core/api_client_test.dart` 通过；旧缓存快照（无 refunded_at）反序列化不抛错。

### TASK-011：控制器退款动作与刷新

- **Status**：DONE
- **完成**：2026-11-12
- **Executor**：Subagent: executor
- **优先级**：P1
- **依赖**：TASK-010
- **Description**：在 `app/lib/core/state/ledger_controller.dart` 新增退款动作，成功后刷新流水与统计。
- **Details**：
  - `setTransactionRefund(int id, bool refunded)`：以 `_refundingTransactions` 集合防重，经 `_guard` 调用 API，成功 / 失败均在 `finally` 清理，成功后 `refreshAfterTransactionChange()`。
  - 提供 `isRefundingTransaction(int id)`，与既有 `deleteTransaction` / `isDeletingTransaction` 同构。
  - `app/test/core/ledger_controller_test.dart` 补用例。
- **Acceptance Criteria**：`flutter test test/core/ledger_controller_test.dart` 通过；用例断言一次请求、流水与统计各刷新一次、重复调用只发一次请求、401 走会话过期。

### TASK-012：日小计排除已退款账单

- **Status**：DONE
- **完成**：2026-11-12
- **Executor**：Subagent: executor
- **优先级**：P1
- **依赖**：TASK-010
- **Description**：`app/lib/features/stream/stream_utils.dart` 的日小计聚合排除已退款账单。
- **Details**：
  - `TransactionDayGroup.expenseExcluding` 与 `incomeExcluding` 增加 `!item.isRefunded` 条件，`daySubtotal` / `daySubtotalParts` 随之生效。
  - `app/test/features/stream_utils_test.dart` 补用例：已退款的支出与收入不计入日小计，分组仍保留该行。
- **Acceptance Criteria**：`flutter test test/features/stream_utils_test.dart` 通过。

### TASK-013：流水行退款入口与已退款标识

- **Status**：DONE
- **完成**：2026-11-12
- **Executor**：Subagent: executor
- **优先级**：P1
- **依赖**：TASK-011, TASK-012
- **Description**：`app/lib/features/stream/stream_screen.dart` 的行内增加退款入口与已退款标识，测试替身同步扩展。
- **Details**：
  - `_RowAction` 增加 `refund`；菜单项依据 `transaction.type`（expense / income）与 `isRefunded` 生成「退款」/「取消退款」，转账与还款不生成。
  - 动作处理调用 `context.read<LedgerController>().setTransactionRefund(...)`，成功 / 失败用 `showLedgerSnackBar` 提示。
  - 已退款标识渲染在行信息区（标题旁小徽标），不改变既有金额列与行矩形契约。
  - `app/test/support/fakes.dart` 的 `transactionModel` 增加 `DateTime? refundedAt` 参数；`app/test/features/stream_screen_test.dart` 补用例。
- **Acceptance Criteria**：
  - `flutter test` 全量通过。
  - 用例断言已退款行显示标识、菜单含退款项、转账 / 还款行不含退款项、退款成功后触发刷新。

---

## Phase 4：回归验证与文档维护

### TASK-014：全栈回归与浏览器手验

- **Status**：DONE
- **完成**：2026-11-12
- **Executor**：主线
- **优先级**：P0
- **依赖**：TASK-009, TASK-013
- **Description**：运行全栈检查命令，并在浏览器完成退款全流程手验。
- **Details**：
  - 命令：`make test`、`make app-analyze`、`make app-format`、`make app-test`。
  - 手验：登录 → 记一笔支出 → 流水行点退款 → 行显示已退款且月头条支出回落 → 统计页确认当月支出与余额回落 → 撤销退款 → 数值恢复；确认转账 / 还款行无退款入口。
  - 完成后关闭开发服务与浏览器，清理临时产物。
- **Acceptance Criteria**：上述命令退出码均为 0；手验结论回填 `Plan.md` 的「回归测试结论」。

### TASK-015：Project.md 维护

- **Status**：DONE
- **完成**：2026-11-12
- **Executor**：主线
- **优先级**：P2
- **依赖**：TASK-014
- **Description**：同步 `.docs/Project.md` 的概述、结构、约束与决策、已知限制。
- **Details**：
  - 概述阶段描述追加退款机制；结构条目更新数据层（refunded_at 探针）、交易服务（退款端点与模型字段）、统计服务（聚合排除）、Web 与 Flutter 对应文件职责。
  - 「约束与决策」新增 2026-11-12 条目：单字段状态、净额归零、可撤销、仅支出与收入。
  - 「已知限制」补：退款按作废处理，原账单月份统计随之回落；不支持部分退款与多次退款；并在既有「流水沿用最近 100 条窗口」条目内补「退款账单同样占用该窗口」，不新增冗余条目。
  - Flutter「测试」条目按本次新增用例更新累计项数与用例说明，沿用既有维护惯例。
- **Acceptance Criteria**：Project.md 描述与代码实际一致，无过期或缺失条目。

### TASK-016：归档 Plan 与 Tasks

- **Status**：DONE
- **完成**：2026-11-12
- **Executor**：主线
- **优先级**：P2
- **依赖**：TASK-015
- **Description**：将 `Plan.md`、`Tasks.md` 标注 `状态：DONE` 并移入 `.docs/11-12-v1/`。
- **Details**：
  - `.docs/` 下不存在 `11-12` 前缀目录，归档目录定为 `11-12-v1`。
  - 两文件补齐完成日期与回归测试结论后移动；校验目标目录同时含两文件且根目录无残留。
- **Acceptance Criteria**：`.docs/11-12-v1/` 同时存在 Plan.md 与 Tasks.md；根目录不再存在两者。

### TASK-017：Git 提交

- **Status**：DONE
- **完成**：2026-11-12
- **Executor**：主线
- **优先级**：P2
- **依赖**：TASK-016
- **Description**：仅暂存退款相关改动与归档文档，按 Conventional Commits（英文类型前缀 + 中文描述）提交。
- **Details**：
  - 提交信息示例：`feat(transactions): 支持账单退款与撤销退款`，正文说明净额归零语义与可退款范围。
  - 不使用 `git add -A`：工作区存在 skills、temp、AGENTS.md 等与本需求无关的既有改动，需保持原状。
- **Acceptance Criteria**：退款相关文件全部提交；提交信息符合规范；无关改动未被纳入本次提交。
