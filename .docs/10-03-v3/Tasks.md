# Tasks：负债还款与主系统全链路业务衔接（修订版 v1.1）

**状态**：DONE  
**完成日期**：2026-10-03  
**关联 Plan**：`Plan.md` —— 负债还款与主系统全链路业务衔接 v1.1  
**回归测试结论**：`make test` 全部通过（Go 单元与全链路集成测试 PASS，前端 TypeScript 检查零错误）；`make build` 成功产出单二进制可执行文件 `bin/ledger`。  
**功能设计文档**：`temp/debt-repayment-functional-design.md`  
**总计 Task**：12 个（已全部完成）  

---

## Phase 1：数据模型演进与探针热迁移（前置注入）

### TASK-001：实现 transactions 表探针热迁移与历史数据类型回填

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/db/db.go` 中新增 `migrateTransactionsColumns` 探针热迁移函数，为 `transactions` 表动态补充 `type` 与 `source_payment_method_id` 列，并原子回填既有数据。
- **Details**：
  - 通过 `PRAGMA table_info(transactions)` 探测是否存在 `type` 与 `source_payment_method_id` 列；
  - 若缺失 `type`，执行 `ALTER TABLE transactions ADD COLUMN type TEXT NOT NULL DEFAULT 'expense'`；并执行 `UPDATE transactions SET type = CASE WHEN amount_cents < 0 THEN 'expense' ELSE 'income' END` 回填历史数据；
  - 若缺失 `source_payment_method_id`，执行 `ALTER TABLE transactions ADD COLUMN source_payment_method_id INTEGER DEFAULT NULL REFERENCES payment_methods(id) ON DELETE RESTRICT`；
  - 在 `migrateAndSeed` 的事务流程中无缝挂载。
- **Acceptance Criteria**：
  - 启动服务时探针热迁移无报错；
  - 既有老数据库与新建数据库均具备包含 `type` 和 `source_payment_method_id` 的 schema；
  - 历史正负金额账单的 `type` 字段正确补齐。

### TASK-002：前置注入系统预置还款分类与标签及 ID 级持久化保护

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/db/db.go` 中将系统分类初始化挂载于 `seed_initialized` 早退检查之前；注入单系统分类「债务偿还」及单标签「负债还款」，将 ID 存入 `system_meta`，并在 `internal/server/settings.go` 中基于 ID 拦截改名与删除。
- **Details**：
  - **位置保障**：必须挂载在 `migrateAndSeed` 中 `seed_initialized` 检查（`db.go:114`）之前，与 `migratePaymentMethodsColumns` 处于同等前置位，确保老数据库升级时必然执行；
  - **单标签精简**：以幂等方式插入单分类「债务偿还」（`sort_order = 999`）与关联单标签「负债还款」（消除死数据标签）；
  - **ID 持久化**：将生成的分类 ID 与标签 ID 存入 `system_meta` 表（key: `system_category_repayment_id` 与 `system_tag_repayment_id`）；
  - **防改名与防删除守卫**：在 `settings.go` 的 `handleUpdateCategory`、`handleDeleteCategory`、`handleUpdateTag`、`handleDeleteTag` 中读取上述 ID，若匹配则返回 400 Bad Request（“系统内置还款分类/标签不可修改或删除”），根因级防范被改名击穿。
- **Acceptance Criteria**：
  - 老数据库与全新数据库在启动后均必然存在「债务偿还」分类与「负债还款」标签；
  - `system_meta` 中准确记录对应 ID；
  - 调用 PUT / DELETE 端点尝试重命名或删除该分类与标签均返回 400。

---

## Phase 2：服务端 API 与聚合统计引擎演进

### TASK-003：交易 CRUD 完整升级、更新路径（PUT）闭环与筛选谓词修正

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/server/transactions.go` 中升级 `TransactionRequest` 与输入校验，打通 POST 与 PUT 完整更新链路，修正金额符号校验与筛选过滤谓词。
- **Details**：
  - **请求与实体结构补齐**：`TransactionRequest` 与 `Transaction` 均补齐 `Type`（`type`）、`SourcePaymentMethodID`（`source_payment_method_id`）、`SourcePaymentMethodName`（`source_payment_method_name`）；
  - **金额与类型校验**：
    - `validateTransactionInput` 针对 `repayment` 校验：必须 `amount > 0`（拦截负数还款反向增加欠款）；
    - 目标 `payment_method_id` 必须为 liability 渠道；
    - 若传入 `source_payment_method_id`，必须为 asset 渠道；
    - 若未传分类或标签，自动从 `system_meta` 读取系统分类与标签 ID 绑定；
  - **创建与更新双路径闭环**：
    - `handleCreateTransaction` 写入 `type` 与 `source_payment_method_id`；
    - `handleUpdateTransaction`（PUT 路径）在 `UPDATE` 语句中同步更新 `type`, `source_payment_method_id`, `payment_method_id`, `amount_cents`, `description`, `category_id`, `tag_id`, `transacted_at`，完整支持还款记录编辑；
  - **筛选谓词修正（防收入污染）**：
    - `handleListTransactions` 中 `?type=expense` 过滤 `t.type = 'expense'`；
    - `?type=income` 过滤 `t.type = 'income'`（绝不包含还款）；
    - `?type=repayment` 过滤 `t.type = 'repayment'`。
- **Acceptance Criteria**：
  - POST 创建还款成功，入库字段完整；
  - PUT 编辑还款成功，能正确修改还入渠道、转出资产渠道与金额；
  - 还款金额小于等于 0 时返回 400；
  - 访问 `GET /api/transactions?type=income` 零还款记录。

### TASK-004：在收支统计与月度趋势中排除还款记录（防污染）

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/server/stats.go` 中修改收支统计与趋势聚合 SQL，明确排除 `type = 'repayment'` 交易。
- **Details**：
  - `week_expense`、`month_expense`、`last_month_expense` 过滤条件更新为 `t.type = 'expense'`（或 `amount_cents < 0 AND t.type != 'repayment'`）；
  - `month_income` 过滤条件更新为 `t.type = 'income'`（或 `amount_cents > 0 AND t.type != 'repayment'`）；
  - `category_distribution`、`tag_distribution`、`payment_distribution` 聚合查询均增加 `AND t.type != 'repayment'`；
  - `monthly_trends` 6 个月趋势双柱统计中排除还款。
- **Acceptance Criteria**：
  - 记录一笔 1000 元还款后，当月花费、当月收入、月度趋势数值保持不变，绝不发生指标虚增。

### TASK-005：在宏观资产负债汇总中接入还款双向账户核算

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/server/stats.go` 的资产负债汇总计算中，纳入还款对负债渠道欠款冲销及对转出资产渠道余额扣减的联动核算。
- **Details**：
  - 负债渠道：还款正金额进入 `COALESCE(SUM(t.amount_cents), 0)`，基于现有公式 `currentDebt = initBal - txSum` 自动抵扣欠款，可用额度与使用率自然恢复；
  - 资产渠道：在聚合查询中统计以该渠道作为 `source_payment_method_id` 的还款金额总和，在 `remainingCents` 中予以扣减（`initBal + txSum - sourceRepaymentSum`）；
  - 净资产（`netAssets = totalAssets - totalLiabilities`）核算保持绝对物理守恒。
- **Acceptance Criteria**：
  - 从工行（资产）还款 500 元至招行信用卡（负债）后，工行余额扣减 500，信用卡欠款减少 500，总资产减 500，总负债减 500，净资产绝对守恒。

---

## Phase 3：前端记账模态窗交互重塑

### TASK-006：在前端 API 模型库中补充还款相关类型与参数定义

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/lib/api.ts` 中扩展 `Transaction`、`FilterType` 与创建/更新请求载荷。
- **Details**：
  - `Transaction` 补充 `type: 'expense' | 'income' | 'repayment'`、`source_payment_method_id?: number`、`source_payment_method_name?: string`；
  - `createTransaction` 与 `updateTransaction` 载荷支持传入 `type` 与 `source_payment_method_id`。
- **Acceptance Criteria**：
  - `api.ts` 类型定义准确，无 TypeScript 编译警告。

### TASK-007：重构 RecordModal 顶部收支切换为 3 段滑块与新增态交互

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/components/RecordModal.tsx` 中升级收支切换为 3 段式胶囊滑块，实现新增模式下的还款分类锁定与双渠道选择。
- **Details**：
  - 容器网格调整为 `grid-cols-3`（`− 支出` | `+ 收入` | `↺ 还款`），应用 Fluent 2 视觉令牌与 GPU 位移动效（`translateX(0% | 100% | 200%)`）；
  - 还款模式下：
    - 分类与细分标签展示区置为只读卡片，禁用 Hover 与点击，显示 `债务偿还 · 负债还款` 并附带精细小锁图标；
    - 渠道选择候选池仅展示 `type === 'liability'` 渠道作为还款账户（必选）；
    - 新增转出资产渠道单选组件，展示 `type === 'asset'` 渠道并提供“外部/未在账本记录资金”选项，默认选中首个资产渠道；
  - 表单提交时组装 `type: 'repayment'` 载荷。
- **Acceptance Criteria**：
  - 点击滑块在支出、收入、还款间流畅切换；
  - 还款模式下分类锁定不可点，渠道仅可选负债渠道；
  - 新增还款成功提交并落库。

### TASK-008：实现 RecordModal 编辑模式下类型滑块锁定与还款数据回填

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/components/RecordModal.tsx` 中实现编辑已有账单时的交互约束与字段回填。
- **Details**：
  - 当 `initialTransaction` 存在时：
    - 顶部 3 段胶囊滑块置为**禁用锁定态**（视觉保留当前类型高亮，不可点击切换，杜绝跨类型状态错乱）；
    - 若编辑还款账单，滑块锁定在「还款」，分类保持锁定态；
    - 回填 `payment_method_id`（负债渠道）与 `source_payment_method_id`（转出资产渠道）；
    - 允许用户修改金额、用途说明、还入渠道、转出渠道与记账时间；
    - 提交时调用 `onSubmit` 并触发 `api.updateTransaction`，传递完整更新载荷。
- **Acceptance Criteria**：
  - 打开任意账单编辑弹窗时，顶部类型滑块不可点击切换；
  - 打开还款账单编辑时，正确回填负债渠道与转出资产渠道，修改后成功保存。

---

## Phase 4：流水列表与筛选胶囊联动

### TASK-009：升级 BottomBar 筛选胶囊为 4 档位

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/components/BottomBar.tsx` 中扩展筛选类型定义，并新增「还款」筛选按钮。
- **Details**：
  - `FilterType` 扩展为 `'all' | 'expense' | 'income' | 'repayment'`；
  - 底部浮动胶囊内依次排列：`全部`、`支出`、`收入`、`还款`。
- **Acceptance Criteria**：
  - 点击「还款」高亮对应按钮，流水列表仅展示还款账单；
  - 移动端与桌面端自适应排版无重叠与挤压。

### TASK-010：美化还款流水卡片流向展示并修正日分组小计（防污染）

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/pages/StreamPage.tsx` 中定制还款流水卡片的视觉排版，并修正日分组标题的收支小计聚合逻辑。
- **Details**：
  - **还款卡片流向展现**：还款记录金额使用中性品牌蓝标识（`¥ 1,000.00`），无红绿歧义；副行渠道处若指定了转出渠道则显示 `[资产渠道] → [负债渠道]`，未指定转出渠道则显示 `还入 [负债渠道]`；分类胶囊显示中性预置标签；
  - **日分组小计防污染**：修改 `StreamPage.tsx:106-112` 的 `groupExpense` 与 `groupIncome` 聚合，仅对 `item.type === 'expense'` 累加支出、`item.type === 'income'` 累加收入，**严格排除 `item.type === 'repayment'`**，杜绝单日收入被还款正金额虚增。
- **Acceptance Criteria**：
  - 还款流水卡片呈现清晰的资金流转指引；
  - 当天存在还款时，日期标题右侧的“收入 ¥xxx”绝对不包含该笔还款金额。

---

## Phase 5：集成测试、文档维护与全链路验收

### TASK-011：编写还款全业务集成测试用例

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/server/server_test.go` 与 `internal/db/db_test.go` 中补充还款业务测试用例。
- **Details**：
  - 验证老数据库升级前置注入系统分类（确保 `seed_initialized` 老库平滑升级成功）；
  - 验证系统分类与标签的改名与删除拦截（基于 ID 守卫）；
  - 验证还款创建、PUT 编辑更新、金额小于等于 0 拦截；
  - 验证服务端 `?type=income` 零还款污染与收支统计隔离；
  - 验证双渠道还款后资产、负债与净资产计算完全守恒。
- **Acceptance Criteria**：
  - `go test -v ./...` 全部通过，零失败用例。

### TASK-012：更新 Project.md 与完成静态编译构建校验

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `.docs/Project.md` 中同步追加还款业务架构决策，执行前端与后端的全量编译构建。
- **Details**：
  - 在 `Project.md` 约束与决策中记录交易模型升级、双边还款核算与 ID 级系统分类保护机制；
  - 执行 `make test` 确保 Go 单测与前端 TS 检查全部通过；
  - 执行 `make build` 验证单二进制编译无误。
- **Acceptance Criteria**：
  - `make test` 零报错；
  - `Project.md` 准确反映系统最新状态；
  - `bin/ledger` 单二进制构建成功。
