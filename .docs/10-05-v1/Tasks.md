# Tasks：移动端通知修复与转账手续费可选闭环

**关联 Plan**：`Plan.md` —— 移动端通知修复与转账手续费可选闭环 v1.1  
**状态**：DONE  
**完成日期**：2026-10-05  
**总计 Task**：11 个（已完成 11 个）

---

## Phase 1：移动端变动通知 (Toast) 视口自适应修复

### TASK-001：修复 Toast.tsx 移动端绝对定位与横向视口安全内边距

- **Status**：DONE
- **Executor**：主线
- **Description**：修改 `web/src/components/Toast.tsx` 中 Toast 容器的外层定位类名，消除单侧固定偏移 `right-8 w-full` 在窄屏下引发的负坐标向左越界，实现移动端绝对居中与桌面端右上锚定。
- **Details**：
  - 将 `Toast.tsx:18` 外层容器类名调整为：
    `fixed top-20 left-1/2 -translate-x-1/2 sm:translate-x-0 sm:left-auto sm:right-8 z-[2000] flex flex-col gap-2 w-[calc(100vw-32px)] sm:w-full max-w-sm pointer-events-none`。
  - 在移动端（<640px）：利用 `left-1/2 -translate-x-1/2` 结合 `w-[calc(100vw-32px)]` 保证水平居中，且屏幕左右两侧各有 16px 安全留白。
  - 维持 `top-20`（80px）高度，与 60px 顶栏保持 20px 安全间隙，避免遮挡导航。
  - 在桌面端（≥640px）：`sm:left-auto sm:right-8 sm:translate-x-0 sm:w-full` 恢复右上角锚定。
- **Acceptance Criteria**：
  - 在 320px、360px、375px、414px 窄屏移动视口下，Toast 完整居中展示，左右边框完整，首字（如「记账成功」的「记」字）不再被截断。
  - 桌面端视口下 Toast 仍保持在右上角，关闭按钮交互正常。

---

## Phase 2：转账手续费数据模型与服务端核算闭环

### TASK-002：在 internal/db/db.go 中通过探针热迁移追加 transactions.fee_cents

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/db/db.go` 中维护 DDL 与探针热迁移函数，使 `transactions` 支持 `fee_cents` 列。
- **Details**：
  - 在 `migrateAndSeed` 函数（`db.go:51` 起）内的 `transactions` 表 DDL 块（`db.go:80-91`）中同步追加 `fee_cents INTEGER NOT NULL DEFAULT 0`。
  - 在 `migrateTransactionsColumns` 探针函数（`db.go:325-369`）中检测 `fee_cents` 列是否存在；若不存在，执行 `ALTER TABLE transactions ADD COLUMN fee_cents INTEGER NOT NULL DEFAULT 0`。
- **Acceptance Criteria**：
  - 全新数据库与存量老数据库均能正常启动。
  - 探针热迁移具备幂等性，重复启动不报错。

### TASK-003：在 internal/server/transactions.go 中扩展请求校验、入库与更新逻辑

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/server/transactions.go` 中扩充 `Transaction` 与 `TransactionRequest` 结构体，调整 `validateTransactionInput` 签名及调用点，持久化 `fee_cents`。
- **Details**：
  - `Transaction` 结构体增加 `FeeCents int64` 与 `Fee float64` JSON 字段；`TransactionRequest` 增加 `Fee float64` JSON 字段。
  - 将 `validateTransactionInput` 签名由 `(int64, string, string, error)` 调整为返回 5 值元组：`(int64, int64, string, string, error)`，分别对应 `(amountCents, feeCents, txType, transactedAt, err)`。
  - 在 `handleCreateTransaction`（:139）与 `handleUpdateTransaction`（:185）两处调用点同步解构 `feeCents`。
  - 在 `validateTransactionInput` 中校验：当 `txType == "transfer"` 时，若传入 `req.Fee`，要求 `req.Fee >= 0`（小于 0 返回 400 Bad Request），计算 `feeCents = int64(math.Round(req.Fee * 100))`；非转账类型强制 `feeCents = 0`。
  - `handleCreateTransaction` 与 `handleUpdateTransaction` 的 INSERT/UPDATE 语句写入 `fee_cents`。
  - `handleListTransactions` 与 `getTransactionByID` 的 SELECT 语句中加入 `t.fee_cents`，派生 `item.Fee = float64(item.FeeCents) / 100.0`。
- **Acceptance Criteria**：
  - 创建转账时传入 `fee: 2.00`，接口返回该笔交易且包含 `fee: 2.00`，数据库持久化为 `200`。
  - 传入负数手续费时返回 400 Bad Request。
  - 普通支出、收入、还款账单不受影响，`fee_cents` 默认为 0。

### TASK-004：在 internal/server/stats.go 中将转账手续费纳入纯资产核算并维持 P&L 隔离

- **Status**：DONE
- **Executor**：主线
- **Description**：修改 `internal/server/stats.go` 中的资产组合聚合查询，将转出资产渠道结余纳管转账手续费扣减，严格维持周/月/上月/趋势/分类分布对转账的隔离不变式。
- **Details**：
  - 在 `portfolioRows` 的聚合查询（`stats.go:318-327`）中，将 `source_transfer_sum` 表达式调整为：
    `COALESCE((SELECT SUM(amount_cents + fee_cents) FROM transactions WHERE source_payment_method_id = pm.id AND type = 'transfer'), 0) AS source_transfer_sum`。
  - 转出资产账户扣减 `本金 + 手续费`，转入资产账户增加 `本金`，`totalAssets` 自然减少 `fee`，`netAssets` 守恒减少 `fee`。
  - 周支出、月支出、上月支出、月度趋势及分类分布查询完全不变更（保持 `type = 'expense'` 隔离），杜绝符号反转与分类占比失真问题。
- **Acceptance Criteria**：
  - 转账 1000 元且手续费 2 元时：转入资产 +1000，转出资产 -1002，总资产与净资产变动 -2 元。
  - 月度收支 `monthExpense` 保持为 0，分类分布保持为空，守恒对账完全一致。

### TASK-005：在 internal/server/server_test.go 中补充转账手续费端到端集成测试用例

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/server/server_test.go` 中编写转账手续费端到端集成测试用例。
- **Details**：
  - 测试创建带手续费转账成功（返回 `fee: 2.00`）。
  - 测试负数手续费返回 400 校验拦截。
  - 测试更新已有转账手续费成功。
  - 测试统计看板接口：转出账户余额扣减 `amount + fee`，净资产减少 `fee`，且 `monthExpense == 0` 的隔离不变式保持 PASS。
- **Acceptance Criteria**：
  - 运行 `go test -v ./internal/server/...` 全部通过。

---

## Phase 3：前端记账模态窗转账手续费交互与流水展示

### TASK-006：在 api.ts、RecordModal.tsx 与 App.tsx 中统一对齐载荷类型定义

- **Status**：DONE
- **Executor**：主线
- **Description**：在前端三处声明载荷签名的地方统一追加 `fee?: number` 属性，保证 TypeScript 严格类型检查无遗漏。
- **Details**：
  - `web/src/lib/api.ts`：`Transaction` 接口增加 `fee?: number; fee_cents?: number;`；`createTransaction` / `updateTransaction` 载荷增加 `fee?: number;`。
  - `web/src/components/RecordModal.tsx:13-22`：`RecordModalProps.onSubmit` 载荷增加 `fee?: number;`。
  - `web/src/App.tsx:170-178`：`handleSaveTransaction` 载荷（第 169 行定义）增加 `fee?: number;`。
- **Acceptance Criteria**：
  - 前端代码中所有涉及 Transaction 提交的签名一致，无编译类型分歧。

### TASK-007：在 web/src/components/RecordModal.tsx 中实现方案 A 金额卡片内敛手续费交互

- **Status**：DONE
- **Executor**：主线
- **Description**：重构「账单金额」卡片标题栏并集成方案 A 手续费内联展开交互。
- **Details**：
  - 将 `RecordModal.tsx:414` 的标题栏容器 `<div className="mb-1.5">` 重构为 `<div className="mb-1.5 flex items-center justify-between">`。
  - 新增状态 `const [showFee, setShowFee] = useState(false)` 与 `const [feeStr, setFeeStr] = useState('')`。
  - 编辑态初始化：若 `initialTransaction` 存在且 `(initialTransaction.fee ?? 0) > 0`，自动初始化 `showFee = true` 与 `feeStr = String(initialTransaction.fee)`。
  - 当 `recordType === 'transfer' && !showFee` 时，在标题栏右侧渲染微型文本按钮 `+ 手续费`（`text-[11px] text-[var(--color-neutral-fg-3)] hover:text-[var(--color-brand)]`），不带任何提示引导。
  - 点击后展开内联手续费行，包含手续费文本标签、货币符号 `¥`、定宽输入框与清除关闭按钮 `✕`。点击 `✕` 时清空 `feeStr` 并将 `showFee` 置为 `false`。
  - 表单提交时：若 `recordType === 'transfer'` 且 `showFee`，当 `feeStr` 存在非空值时校验其数值（若为负数或 NaN 则 setError 拦截）；若未开启手续费、未填写或为空串则传 `fee: 0`。
  - 切换到非转账类型或模态窗关闭时重置 `showFee = false` 与 `feeStr = ''`。
- **Acceptance Criteria**：
  - 默认转账界面极度纯净，无常驻手续费输入框；点击 `+ 手续费` 平滑内联展开。
  - 支持录入有效手续费并随转账一同保存；输入负数或非法字符串时前置报错拦截。
  - 编辑带手续费账单时，手续费自动展开回显。

### TASK-008：在 web/src/pages/streamUtils.ts 中格式化转账手续费元信息

- **Status**：DONE
- **Executor**：主线
- **Description**：在流水列表元信息构建工具中纳管手续费展示，保持 `StreamPage.tsx` 零冗余修改。
- **Details**：
  - 在 `web/src/pages/streamUtils.ts` 的 `MetaItemInput` 接口中追加 `fee?: number | null;`。
  - 在 `buildMetaParts` 函数中（`streamUtils.ts:77-101`），在末尾推入时间之前（第 95 行之前），若 `item.type === 'transfer' && item.fee && item.fee > 0`，向元信息数组追加 `手续费 ¥${item.fee.toFixed(2)}`，保证最终输出顺序为：分类 · 标签 · 账户流向 · 手续费 · 时间。
  - `StreamPage.tsx:150` 保持现状（其已整体传递 `item`，自然携带 `fee`）。
- **Acceptance Criteria**：
  - 带手续费转账在流水中按指定顺序显示为 `账户转账 · 资金互转 · 招商银行 → 微信零钱 · 手续费 ¥2.00 · 15:30`。
  - 无手续费记录不显示多余文本。

### TASK-009：在 web/test/stream.test.ts 中补充手续费元信息格式化自检测试

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/test/stream.test.ts` 中补充针对带手续费转账记录的单元测试用例。
- **Details**：
  - 测试 `buildMetaParts` 正确格式化 `手续费 ¥2.00` 且位置在时间之前。
  - 测试无手续费转账不输出手续费字段。
- **Acceptance Criteria**：
  - 运行 `node --experimental-strip-types --test test/stream.test.ts` 全部通过。

---

## Phase 4：全链路回归验证与工程文档维护

### TASK-010：执行 make test 验证全量测试套件与前端静态编译

- **Status**：DONE
- **Executor**：主线
- **Description**：运行 `make test` 验证全量自动化测试（后端 Go 单元/集成测试、前端 Node 纯函数单测、前端 TypeScript 静态编译）无报错。
- **Details**：
  - 确认后端 `go test -v ./...` 全部通过。
  - 确认前端 `npm run test`（包含 `stream.test.ts`）全部通过。
  - 确认前端 `tsc -b --noEmit` 编译零错误。
- **Acceptance Criteria**：
  - 命令退出码为 0，终端全绿。

### TASK-011：更新 .docs/Project.md 同步架构变更、数据模型演进与交付决策

- **Status**：DONE
- **Executor**：主线
- **Description**：维护 `.docs/Project.md`，同步记录本次迭代的结构变更、约束与决策。
- **Details**：
  - 概述与阶段：更新为支持移动端 Toast 视口自适应与转账手续费纯资产调整闭环。
  - 结构：更新 `transactions.fee_cents` 模型与组件状态。
  - 约束与决策：点名修订 `Project.md:138`，将「总资产与净资产维持严格物理守恒（净变动为 0）」更新为「总资产与净资产精确守恒变动 -fee（无手续费时净变动为 0）」；追加探针热迁移、纯资产核算口径取舍（P&L 保持转账隔离）与 Toast 响应式居中规范记录。
- **Acceptance Criteria**：
  - `Project.md` 真实反映代码库最新状态，无过期陈述。

---

## 回归测试结论

- **执行时间**：2026-10-05
- **执行命令**：`make test`
- **结论**：
  - 后端：Go 全部单元与端到端测试 PASS（`ledger/internal/db`, `ledger/internal/server`, `ledger/web`）。
  - 前端：TypeScript 静态编译零错误（`tsc -b --noEmit`），纯函数单元测试 19 项全部 PASS（`node --test test/*.test.ts`）。
  - 任务状态：11/11 项 Task 全部标记为 DONE，业务全链路正常。

