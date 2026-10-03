# Tasks：资产与负债系统架构演进

**状态**：DONE  
**完成日期**：2026-10-03  
**关联 Plan**：`Plan.md` —— 资产与负债系统架构演进 v1.0  
**前端 Demo**：[`temp/asset-liability-workbench-demo.html`](file:///home/dev/projects/Ledger/temp/asset-liability-workbench-demo.html)  
**总计 Task**：11 个（全部完成）  
**回归测试结论**：`make test` 与 `make build` 100% 通过。

---

## Phase 1：数据库表结构扩展与老库平滑热迁移

### TASK-001：扩展 internal/db/db.go 表结构与增量列探测热迁移逻辑

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/db/db.go` 中更新 `payment_methods` 表 schema，增加 `type`、`initial_balance_cents` 和 `credit_limit_cents` 列，并在 `migrateAndSeed` 中实现基于 `PRAGMA table_info` 的自动增量平滑迁移。
- **Details**：
  - 更新建表 SQL：`payment_methods` 增加 `type TEXT NOT NULL DEFAULT 'asset'`、`initial_balance_cents INTEGER NOT NULL DEFAULT 0`、`credit_limit_cents INTEGER NOT NULL DEFAULT 0`；
  - 编写 `migratePaymentMethodsColumns(tx *sql.Tx) error` 函数，查询 `PRAGMA table_info(payment_methods)`，检测若缺失字段则分别执行 `ALTER TABLE payment_methods ADD COLUMN ...`；
  - **迁移执行时机**：列探测迁移逻辑须置于 `system_meta` 的 `seed_initialized` 早退检查之前无条件执行，确保所有已有数据且已打标的生产老库在启动时均能正确增量补齐新列；
  - **种子数据规范**：全新安装初始化（`pmCount == 0 && catCount == 0 && txCount == 0`）保留原 4 项资产渠道（微信、支付宝、招商银行卡、现金），并新增第 5 项默认负债渠道 `{"招商信用卡", 5, "liability", 0, 2000000}`（初始欠款 0，额度 20,000 元）；已有数据的历史老库受既有 `pmCount > 0` 保护不重复注入种子；
  - 保持历史老库数据向后兼容，已有行增量追加后默认纳管为 `asset` 且初始底账为 0。
- **Acceptance Criteria**：
  - 全新数据库初始化成功建表并包含 3 个新字段及默认信用卡负债渠道；
  - 已打标 `seed_initialized` 的老数据库启动时在早退前平滑完成列追加且不报错；
  - 启动过程无任何 SQL 语法错误。

### TASK-002：在 internal/db/db_test.go 中补充老库增量升级与新字段断言单测

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/db/db_test.go` 中新增测试用例，验证新表字段正确性及老数据库无新字段时的平滑热升级。
- **Details**：
  - 编写 `TestPaymentMethodsMigration`：先手动创建一个旧版本结构的 `payment_methods` 表（仅含 id, name, sort_order, created_at）并插入测试记录；
  - 显式构造并覆盖“`system_meta` 中已写入 `seed_initialized = 'true'` 但 `payment_methods` 仍为旧结构”的场景，调用 `InitDB` 触发迁移；
  - 查询 `PRAGMA table_info(payment_methods)` 断言 3 个新字段均在早退前被成功补齐；
  - 查询旧测试记录，断言其默认 `type` 为 `'asset'`，`initial_balance_cents` 为 0，`credit_limit_cents` 为 0；
  - 验证老库种子防复活机制依旧正常生效（旧库不被注入新的默认项）。
- **Acceptance Criteria**：
  - `go test -v ./internal/db/...` 全部通过；
  - 覆盖已初始化的老库增量列迁移路径。

---

## Phase 2：后端渠道业务扩展与多维资产统计引擎

### TASK-003：扩展 internal/server/settings.go 中的 PaymentMethod 结构体与 CRUD 处理逻辑

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/server/settings.go` 中扩展 `PaymentMethod` 结构体，并修改创建、列表、更新接口以支持渠道类型、初始底账与信用额度读写，同时完整保留 `sort_order` 契约。
- **Details**：
  - `PaymentMethod` 结构体新增：
    - `Type string` (`json:"type"`)；
    - `InitialBalance float64` (`json:"initial_balance"`)，底层对应 `initial_balance_cents`；
    - `CreditLimit float64` (`json:"credit_limit"`)，底层对应 `credit_limit_cents`；
    - 完整保留既有字段：`ID`、`Name`、`SortOrder`、`CreatedAt`；
  - `handleListPaymentMethods`：SQL 查询增加新字段并转换为元浮点数返回，维持 `ORDER BY sort_order ASC, id ASC`；
  - `handleCreatePaymentMethod`：接收 `name`、`sort_order`、`type`（合法值为 `asset` 或 `liability`，缺省默认为 `asset`）、`initial_balance`（转换为整数分）、`credit_limit`（转换为整数分），写入数据库；
  - `handleUpdatePaymentMethod`：保留 `sort_order` 现有更新逻辑，同步支持更新 `name`、`type`、`initial_balance` 与 `credit_limit`；
  - **渠道类型翻转决策**：显式允许更新渠道 `type`（个人工具保持灵活自由，语义由用户自担，不引入额外锁定分支）；
  - 保留并确保 `handleDeletePaymentMethod` 中存在流水引用的 409 Conflict 拦截不受破坏。
- **Acceptance Criteria**：
  - 成功创建 `type="liability"` 且带有 `sort_order` 与 `credit_limit` 的渠道并返回 201；
  - 成功读取包含新属性与 `sort_order` 的渠道列表并返回 200；
  - 更新渠道属性正常落盘并保留排序权重；
  - 关联交易删除仍严格拦截返回 409。

### TASK-004：在 internal/server/stats.go 中实现多维资产与负债聚合计算引擎

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/server/stats.go` 中定义资产与负债统计响应结构，并在 `handleStatsSummary` 中实现渠道余额、当前欠款、剩余额度及总净资产计算。
- **Details**：
  - 定义 `AssetChannelStat`：`ID`、`Name`、`Type`、`RemainingBalance`、`InitialBalance`、`Percentage`；
  - 定义 `LiabilityChannelStat`：`ID`、`Name`、`Type`、`CurrentDebt`、`InitialDebt`、`CreditLimit`、`RemainingCredit`、`UsageRate`；
  - 定义 `AssetSummary`：`TotalAssets`、`TotalLiabilities`、`NetAssets`、`AssetChannels`、`LiabilityChannels`；
  - 在 `StatsSummaryResponse` 中新增 `AssetSummary AssetSummary` (`json:"asset_summary"`) 字段；
  - 编写计算逻辑：
    - 查询所有渠道的初始底账与额度，并按 `payment_method_id` 聚合全量交易流水 `COALESCE(SUM(amount_cents), 0)`；
    - 针对 `asset` 渠道：`remaining_cents = initial_balance_cents + tx_sum_cents`；累加到 `total_assets_cents`；
    - 针对 `liability` 渠道：`current_debt_cents = initial_balance_cents - tx_sum_cents`；累加到 `total_liabilities_cents`；若 `credit_limit_cents > 0`，派生 `remaining_credit_cents = credit_limit_cents - current_debt_cents` 及 `usage_rate`；
    - 计算 `net_assets_cents = total_assets_cents - total_liabilities_cents`；
    - 转换为元浮点数填充结构体。
- **Acceptance Criteria**：
  - 接口在拥有资产与负债多笔交易时，计算结余与欠款精确无误差；
  - 净资产计算符合 `总资产 - 总负债` 代数公式；
  - 无交易记录时各渠道安全回退显示初始底账。

### TASK-005：在 internal/server/server_test.go 中补充渠道属性与资产统计端点集成测试

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/server/server_test.go` 中扩充测试用例，覆盖负债渠道创建、更新、资产统计聚合及 409 守卫。
- **Details**：
  - 编写 `TestPaymentMethodsAssetAndLiability`：测试创建资产渠道、创建负债渠道（带额度与初始欠款）、列表获取与更新；
  - 编写 `TestStatsSummaryWithAssetsAndLiabilities`：
    - 创建储蓄卡（资产，初始 5,000 元）与信用卡（负债，初始欠款 0 元，额度 20,000 元）；
    - 录入储蓄卡收入 10,000 元与支出 2,000 元；
    - 录入信用卡消费 3,000 元；
    - 请求 `/api/stats/summary`，断言储蓄卡余额为 13,000 元，总资产为 13,000 元；信用卡欠款为 3,000 元，剩余额度为 17,000 元，总负债为 3,000 元；净资产为 10,000 元；
  - 断言被流水绑定的渠道删除时返回 409。
- **Acceptance Criteria**：
  - `go test -v ./internal/server/...` 100% 通过；
  - 边界场景（负余额、0 额度、全量交易）全部覆盖。

---

## Phase 3：前端设置页渠道工作台与新增负债渠道

### TASK-006：更新 web/src/lib/api.ts 渠道与统计数据类型定义及请求客户端

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/lib/api.ts` 中更新 TypeScript 接口契约，适配渠道新属性与资产负债统计模型。
- **Details**：
  - 扩展 `PaymentMethod` 接口：增加 `type: 'asset' | 'liability'`、`initial_balance: number`、`credit_limit: number`；
  - 扩展 `createPaymentMethod` 与 `updatePaymentMethod` 方法签名与请求体：支持传递 `type`、`initial_balance`、`credit_limit`；
  - 增加 `AssetChannelStat`、`LiabilityChannelStat`、`AssetSummary` 接口；
  - 扩展 `StatsSummary` 接口，纳入 `asset_summary: AssetSummary` 字段。
- **Acceptance Criteria**：
  - `web/src/lib/api.ts` 类型定义严谨无 `any`；
  - 前端 `npm run build` 或 `tsc -b --noEmit` 编译无类型报错。

### TASK-007：重构 web/src/pages/SettingsPage.tsx 渠道工作台支持资产与负债分类分段管理

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/pages/SettingsPage.tsx` 中重构支付途径管理区域为统一渠道账户工作台，分设“资产渠道”与“负债渠道”两大平行容器。
- **Details**：
  - 在渠道板块内提供资产与负债的分段胶囊或分栏容器，清晰聚合展示 `paymentMethods.filter(pm => pm.type === 'asset')` 与 `paymentMethods.filter(pm => pm.type === 'liability')`；
  - 资产渠道卡片展示：渠道名称、初始底账；
  - 负债渠道卡片展示：渠道名称、初始欠款、授信额度（若设置）；
  - 保留卡片悬浮操作：删除渠道按钮（保留 409 捕获并触发 Toast 提示）；
  - 遵循 `production-frontend` 规范，不增加任何多余的教学与解释文案。
- **Acceptance Criteria**：
  - 资产与负债渠道主次清晰分开呈现；
  - 界面排版符合 Fluent 2 令牌与四层 Z 轴（Layer 1 卡片）；
  - 删除带流水的渠道时正确弹出中文冲突拦截 Toast。

### TASK-008：在 web/src/App.tsx 与 web/src/pages/SettingsPage.tsx 中实现渠道状态接线、新增负债渠道内联表单与编辑保存交互

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/App.tsx` 中扩展渠道创建与更新的处理函数，并传递给 `web/src/pages/SettingsPage.tsx`，支持新增资产/负债渠道的内联展开表单及已有渠道属性编辑。
- **Details**：
  - 在 `web/src/App.tsx` 中：
    - 扩展 `handleCreatePaymentMethod` 签名，接收 `(name: string, type: 'asset' | 'liability', initialBalance: number, creditLimit: number)` 并调用扩展后的 `api.createPaymentMethod`；
    - 新增 `handleUpdatePaymentMethod` 回调：接收 `(id: number, name: string, sortOrder: number, type: 'asset' | 'liability', initialBalance: number, creditLimit: number)`，调用 `api.updatePaymentMethod`，成功后统一刷新 `fetchConfigData()`；
    - 将 `onAddPaymentMethod` 与新增的 `onUpdatePaymentMethod` 作为 props 传递给 `<SettingsPage />`；
  - 在 `web/src/pages/SettingsPage.tsx` 中：
    - `SettingsPageProps` 增加 `onUpdatePaymentMethod` 类型声明；
    - 设立“添加资产渠道”与“添加负债渠道”独立触发入口；
    - 展开内联表单：
      - 资产渠道表单：输入名称、初始余额（数字输入框，默认 0）；
      - 负债渠道表单：输入名称、初始欠款（数字输入框，默认 0）、授信额度（可选数字输入框，默认 0 表示不限）；
    - 增加渠道就地快速编辑模式（点击编辑按钮或双击名称），可修改名称、底账与额度并调用 `onUpdatePaymentMethod`；
    - 校验防重名与非负金额限制；按 ESC 或点击取消平滑折叠表单。
- **Acceptance Criteria**：
  - `web/src/App.tsx` 与 `web/src/pages/SettingsPage.tsx` 的 props 契约完整闭环；
  - 成功新增负债渠道并即时在界面响应刷新；
  - 表单展开与收起平滑，无全屏模态遮挡；
  - 空名称与非法数值有前置阻止，不发异常请求。

---

## Phase 4：前端统计看板资产与负债总览及全量回归

### TASK-009：在 web/src/pages/StatsPage.tsx 顶部构建资产与负债全局 KPI 看板

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/pages/StatsPage.tsx` 页面顶部新增资产与负债全局概览 KPI 卡片矩阵（净资产、资产总额、负债总额）。
- **Details**：
  - 基于 Fluent 2 卡片规范（`--color-card-bg`、`--shadow-card`、`--color-neutral-stroke`），在收支 4联卡上方或并列构建资产总览卡片簇；
  - 核心展示：
    - **净资产**：突出字号与中性/品牌色，等宽数字 `tabular-num`，若为负值采用柔和红褐色；
    - **资产总计**：展示目前所有资产渠道剩余金额之和；
    - **负债总计**：展示目前所有负债渠道当前欠款之和；
  - 数据从 `stats.asset_summary` 中提取，空状态优雅平滑处理。
- **Acceptance Criteria**：
  - 3 大资产 KPI 卡片与原有收支卡片视觉比例和谐；
  - 净资产、总资产、总负债数值与后端返回完全一致；
  - 严格去除解释性冗余文案，纯净呈现。

### TASK-010：在 web/src/pages/StatsPage.tsx 中实现各资产渠道剩余金额卡片簇与负债渠道欠款额度监控条

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/pages/StatsPage.tsx` 中新增渠道存量分布与负债监控卡片区域，展示各资产渠道剩余金额及负债渠道欠款与剩余可用额度。
- **Details**：
  - 资产渠道存量卡片组：展示各个资产渠道的名称与当前剩余金额（`remaining_balance`），显示占总资产比例；
  - 负债渠道监控卡片组：展示各个负债渠道的名称与当前欠款（`current_debt`）；若设置了 `credit_limit > 0`，渲染 4px 极细微额度占用条（`usage_rate`），并标注剩余可用额度；
  - 当无负债渠道时，优雅退化为极简空状态提示；
  - 所有金额遵循等宽数字排版，移动端自适应单列/双列折行。
- **Acceptance Criteria**：
  - 资产渠道展示清晰的“渠道剩余金额”，数值带人民币符号与双位小数；
  - 负债渠道展示“当前欠款”与“剩余可用额度”，额度条无溢出；
  - 响应式在 375px–1280px 视口下均无挤压错位。

### TASK-011：执行全流程端到端自动化验证

- **Status**：DONE
- **Executor**：主线
- **Description**：运行全量自动化测试套件与静态类型检查，执行单二进制构建并验证产物可执行性。
- **Details**：
  - 执行后端测试：`go test -v ./...`；
  - 执行前端类型检查与构建：`cd web && npm run build`（或 `tsc -b --noEmit`）；
  - 执行全流程构建：`make build`，验证生成 `bin/ledger` 单二进制；
  - 检查老数据库升级与全业务闭环，确认无编译错误与测试回归。
- **Acceptance Criteria**：
  - `make test` 零报错通过；
  - `make build` 顺利产出单二进制可执行文件；
  - 全流程测试用例覆盖资产与负债核心链路。
