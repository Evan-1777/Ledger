# Tasks：移动端体验优化、收入分类逻辑重构与账户转账

**关联 Plan**：`Plan.md` —— 移动端体验优化、收入分类逻辑重构与账户转账 v1.0  
**总计 Task**：13 个

---

## Phase 1：数据层扩展与探针热迁移

### TASK-001：编写 categories 表探针热迁移追加 type 列与老数据打标

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/db/db.go` 中新增 `migrateCategoriesColumns` 探针迁移函数，并由 `migrateAndSeed` 调用，安全追加 `type` 列并回填初始数据。
- **Details**：
  - 迁移函数执行位置约束：必须显式放置在 `seed_initialized` 提前 return 判定之前（与既有的 `migratePaymentMethodsColumns` 及 `migrateTransactionsColumns` 严格并列，位于 `db.go:113-118` 同级），确保所有存量生产库无损升级；
  - 通过 `PRAGMA table_info(categories)` 探测是否存在 `type` 列；若缺失则执行 `ALTER TABLE categories ADD COLUMN type TEXT NOT NULL DEFAULT 'expense'`；
  - 迁移后原子更新已知数据：将名称为「职业收入」的分类更新为 `type = 'income'`；将系统预置的「债务偿还」分类更新为 `type = 'system'`；
  - 在 `defaultCategories` 种子定义中补齐 `type` 字段（`expense` 或 `income`），保证全新库与老库升级同构。
- **Acceptance Criteria**：
  - 全新数据库与已有数据老库（已标记 `seed_initialized = 'true'`）初始化均成功且包含 `type` 列；
  - 历史「职业收入」成功标记为 `income`，「债务偿还」标记为 `system`。

### TASK-002：预置系统级转账分类与标签并注入 ID 级不可变守卫

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/db/db.go` 中新增 `ensureSystemTransferCategory` 函数，并在 `internal/server/settings.go` 中扩展不可变守卫。
- **Details**：
  - 在迁移事务中检查并创建分类「账户转账」（`type = 'system'`, `sort_order = 998`）与标签「资金互转」（`sort_order = 1`）；
  - 调用点全量对齐约束：必须与既有 `ensureSystemRepaymentCategory(tx)` 保持三处调用点完全对称（1. `seed_initialized == "true"` 提前 return 分支；2. 已有数据老库升级分支；3. 全新安装种子分支）；
  - 将生成的分类 ID 与标签 ID 分别写入 `system_meta` 表（键：`system_category_transfer_id`、`system_tag_transfer_id`）；
  - 在 `internal/server/settings.go` 的 `handleUpdateCategory`、`handleDeleteCategory`、`handleUpdateTag`、`handleDeleteTag` 中增加该 ID 的拦截判断，若尝试修改或删除则严格返回 400 Bad Request。
- **Acceptance Criteria**：
  - 启动后 `system_meta` 存在转账分类与标签 ID 记录；
  - 对转账系统分类和标签执行 PUT 或 DELETE 均返回 400，杜绝外键与逻辑击穿。

### TASK-003：扩展 settings.go 分类 API 契约支持 type 字段

- **Status**：DONE
- **Executor**：主线
- **Description**：修改 `internal/server/settings.go` 中的 `Category` 结构体及相关处理函数，使 API 正确序列化与校验 `type`。
- **Details**：
  - 在 `Category` 结构体中增加 `Type string json:"type"`；
  - `handleListCategories` 查询字段补齐 `c.type`，前端拉取全量分类后本地按需过滤（遵循 YAGNI，不增加无消费方的服务端过滤参数）；
  - `handleCreateCategory` 支持接收 `type` 入参（默认 `'expense'`，仅限 `'expense'` 或 `'income'`，禁止直接通过接口创建 `'system'`）；
  - `handleUpdateCategory` 支持可选更新 `type` 字段（若入参未传 `type`，必须保留既有 `type`，禁止清空或重置；禁止将普通分类改为 `system`，禁止修改 `system` 分类）。
- **Acceptance Criteria**：
  - 既有重命名/调序调用（不传 `type`）时，分类既有 `type` 严格保留；
  - GET `/api/categories` 返回对象包含合法 `type` 字段；
  - POST `/api/categories` 可正确创建 `income` 或 `expense` 分类。

---

## Phase 2：后端交易契约与宏观统计核算

### TASK-004：扩展 transactions.go 交易创建与更新接口支持 transfer 类型

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/server/transactions.go` 中增强 `validateTransactionInput`，全面支持转账交易校验与系统分类自动绑定。
- **Details**：
  - `txType` 合法类型扩充支持 `'transfer'`；
  - 当 `txType == 'transfer'` 时：
    1. 校验金额必须为大于 0 的正数（`amount > 0`），转为正数分值存储（`amountCents > 0`）；
    2. 校验目标账户 `payment_method_id` 必须为资产渠道（`type == 'asset'`）；
    3. 校验来源账户 `source_payment_method_id` 为必填项，且必须为资产渠道（`type == 'asset'`）；
    4. 校验 `payment_method_id != *source_payment_method_id`，禁止同渠道转账；
    5. 若未显式传入分类标签，自动从 `system_meta` 读取 `system_category_transfer_id` 和 `system_tag_transfer_id` 并回填；
  - GET `/api/transactions` 支持可选过滤 `?type=transfer`。
- **Acceptance Criteria**：
  - 传入非法转账（如负金额、负债转资产、自身转自身）均严格返回 400；
  - 合法转账创建成功并正确返回包含 `source_payment_method_id` 与 `source_payment_method_name` 的交易模型。

### TASK-005：升级 stats.go 资产渠道余额公式与宏观守恒核算

- **Status**：DONE
- **Executor**：主线
- **Description**：修改 `internal/server/stats.go` 的资产统计查询，精确纳管转账资金流动，排除收支损益污染。
- **Details**：
  - 在 `handleStatsSummary` 资产渠道聚合查询中，追加查询作为转账来源方的转出总额：
    `COALESCE((SELECT SUM(amount_cents) FROM transactions WHERE source_payment_method_id = pm.id AND type = 'transfer'), 0) AS source_transfer_sum`；
  - 资产渠道剩余余额公式更新为：
    `remainingCents := initBalCents + txSumCents - sourceRepaymentCents - sourceTransferCents`；
  - 确保周花费、月花费、上月花费、月收入、收支趋势图及分类下钻 SQL 中，严格维持 `type = 'expense'` 与 `type = 'income'`，转账记录不计入损益。
- **Acceptance Criteria**：
  - 转账后，转出资产渠道余额减少对应金额，转入资产渠道余额增加对应金额；
  - 宏观总资产（`TotalAssets`）与净资产（`NetAssets`）保持绝对不变；
  - 收支损益各项 KPI 与收支趋势图完全不受转账影响。

### TASK-006：编写转账与分类契约后端集成测试用例

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/server/server_test.go` 中补充全场景集成测试用例。
- **Details**：
  - 测试用例覆盖：
    1. 迁移后分类 `type` 字段校验与系统转账分类不可变保护；
    2. 创建转账交易正常链路与错误拦截（同渠道转账、负债渠道作为转账端、负金额）；
    3. 转账前后宏观资产统计验证：断言转出与转入渠道余额变动，断言总资产与净资产恒等不变；
    4. 验证月度收支统计与分类分布排除转账记录。
- **Acceptance Criteria**：
  - `go test -v ./internal/server` 全量通过，无失败断言。

---

## Phase 3：前端交互与移动端体验重塑

### TASK-007：重构 RecordModal.tsx 移动端布局与常驻底部操作栏

- **Status**：DONE
- **Executor**：主线
- **Description**：改造 `web/src/components/RecordModal.tsx` 模态外壳，将操作按钮抽离为常驻 Footer，使用动态视口规范杜绝移动端截断。
- **Details**：
  - 外层容器采用 `max-h-[calc(100dvh-24px)]` 替换原有 `max-h-[90vh]`，适配移动端地址栏与工具条的动态伸缩；
  - 结构调整为 Flex 列布局：固定 Header（`flex-shrink-0`）+ 可滚动表单主体（`flex-1 overflow-y-auto`）+ 常驻 Footer（`flex-shrink-0 border-t border-[var(--color-neutral-stroke)] bg-[var(--color-card-bg)]`）；
  - 表单内边距在小屏适配为 `p-4 sm:p-6`，确保小屏设备可视区饱满且操作区常驻可见。
- **Acceptance Criteria**：
  - 移动端（375px–414px）在地址栏与工具栏动态伸缩下弹窗底栏常驻可见、表单平滑自适应滚动无截断；虚拟键盘弹起场景按标准滚动查看。

### TASK-008：重构 RecordModal.tsx 分类选择器为收支严格分流与平滑内联展开结构

- **Status**：DONE
- **Executor**：主线
- **Description**：改造分类与标签选择逻辑，消除绝对定位悬浮浮层，实现收支分类彻底隔离。
- **Details**：
  - 契约穿透扩展：在 `web/src/lib/api.ts` 的 `Category` 接口中追加 `type: 'expense' | 'income' | 'system'` 字段；
  - 根据 `recordType` 动态过滤分类池：`recordType === 'expense'` 仅展示 `type === 'expense'` 分类；`recordType === 'income'` 仅展示 `type === 'income'` 分类；
  - 切换到收入模式时，默认自动选中首个收入分类（如职业收入）及其首个标签，彻底消除“收入默认选中餐饮午餐”问题；
  - 移除原 `absolute h-[220px]` 级联面板，改为表单流内的平滑内联折叠展开（Inline Collapsible）；点选标签后自动收起，消除浮层遮挡与触屏滚动死锁。
- **Acceptance Criteria**：
  - 记收入时仅可选收入分类，默认回填合理收入类别；
  - 记支出时分类列表不包含职业收入；
  - 分类选择平滑流畅，不遮挡下方渠道按钮。

### TASK-009：实现 RecordModal.tsx 四段胶囊滑块与转账全链路接通

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/components/RecordModal.tsx` 接入四段滑块、转账双渠道选择与自动锁定系统标签。
- **Details**：
  - 契约穿透扩展：在 `web/src/lib/api.ts` 中 `Transaction.type` 联合类型追加 `'transfer'`；在 `web/src/App.tsx` 的 `handleSaveTransaction` 参数联合类型追加 `'transfer'`；
  - 顶部胶囊滑块扩展为 `grid-cols-4`：`− 支出` | `+ 收入` | `⇄ 转账` | `↺ 还款`，滑块位移精准对齐四档；
  - 选中「转账」时：
    1. 分类标签自动切换为锁态卡片，展示「账户转账 · 资金互转 🔒 系统固定」；
    2. 渲染双资产渠道选择网格：【转出资产账户】与【转入资产账户】（均仅展示 `type === 'asset'` 渠道）；
    3. 前置互斥防重：用户选择转出账户后，转入账户中同名项自动置灰禁用，杜绝非法状态可选；
    4. 提交数据装配 `type: 'transfer'`、`payment_method_id`（转入）与 `source_payment_method_id`（转出）。
  - 编辑态（`initialTransaction`）时四段滑块锁定为禁用态防跨类型错乱。
- **Acceptance Criteria**：
  - 可正常完成转账记账，表单数据与错误校验准确；
  - 编辑账单正确回填转账两端账户。

### TASK-010：升级 BottomBar.tsx 5 档筛选胶囊与 StreamPage.tsx 转账流向卡片展示

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/components/BottomBar.tsx` 扩充 5 档筛选位，并在 `web/src/pages/StreamPage.tsx` 呈现转账资金流向。
- **Details**：
  - `BottomBar.tsx` 的 `FILTER_OPTIONS` 增加 `{ key: 'transfer', label: '转账' }` 档位；小屏下维持避让右下角 FAB；在 `web/src/lib/api.ts` 的 `getTransactions` 过滤器类型中同步追加 `'transfer'`；
  - `StreamPage.tsx` 流水卡片适配：
    - 当 `item.type === 'transfer'` 时，金额采用 Fluent 品牌蓝中性高亮展示（`¥ 1,000.00`），无正负号歧义；
    - 渠道位置显示流向路径：`[转出渠道] → [转入渠道]`（如 `招商银行卡 → 微信支付`）；
    - 标签显示中性品牌蓝胶囊 `账户转账 · 资金互转`；
    - 校验并维持 `StreamPage.tsx:106-112` 既有日小计逻辑（仅按 `expense` 与 `income` 分支累加），天然隔离转账，不污染日消费与日收入。
- **Acceptance Criteria**：
  - 底部筛选点击“转账”仅展示转账流水；
  - 流水卡片清晰表达双向账户流向，小计计算准确无污染。

### TASK-011：升级 SettingsPage.tsx 分类管理支持收支分段展示与纠错

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/pages/SettingsPage.tsx` 分类与标签工作台中区分支出分类与收入分类，打通调用链并提供类型纠错能力。
- **Details**：
  - 契约穿透扩展：在 `web/src/lib/api.ts` 中 `createCategory` 与 `updateCategory` 方法补齐可选 `type` 参数；在 `web/src/App.tsx` 中 `handleAddCategory` 与 `handleUpdateCategory` 转发 `type` 参数；
  - 在「分类与标签」工作台顶部增加二级轻量分段（支出分类 / 收入分类）；
  - 新增分类时自动继承当前所处分段的 `type`；
  - 在分类内联重命名/编辑状态中提供类型切换单选（支出/收入），允许用户对历史误标或改名的分类进行类型纠错；
  - 系统内置分类「账户转账」与「债务偿还」标注不可变系统标识，隐藏删除与重命名入口。
- **Acceptance Criteria**：
  - 用户可清晰按收支分段管理分类与细分标签，系统内置分类受到界面层保护；
  - 设置页编辑分类可调整分类类型，解决老库历史数据纠错需求。

---

## Phase 4：全流程回归测试与系统文档维护

### TASK-012：执行前后端全量回归测试与静态类型检查

- **Status**：DONE
- **Executor**：主线
- **Description**：执行项目自动化构建与测试链路，确保代码质量与无破坏性回归。
- **Details**：
  - 执行 `cd web && npm run build`（验证 Vite 打包与 TypeScript 类型检查 `tsc -b --noEmit`）；
  - 执行 `go test -v ./...`（覆盖全部 Go 后端单元测试与集成测试）；
  - 执行 `make test` 全量流水线。
- **Acceptance Criteria**：
  - 前后端编译与测试零警告、零失败全部通过。

### TASK-013：同步更新 .docs/Project.md 架构记录与业务决策

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `.docs/Project.md` 中记录本次版本新增的约束、决策与功能演进。
- **Details**：
  - 概述阶段更新为包含移动端动态视口、收支分类分流、双向账户转账与守恒核算闭环；
  - 在约束与决策中追加：categories 扩展 type 探针热迁移、转账交易规则与双资产核算公式、模态常驻 Footer 与动态视口规范、收支分类隔离；
  - 检查文档一致性，消除过期陈述。
- **Acceptance Criteria**：
  - Project.md 完整准确反映最新代码库状态与业务规则。
