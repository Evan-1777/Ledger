# Tasks：复审问题修复与资产健壮性提升

**状态**：DONE  
**完成日期**：2026-10-03  
**关联 Plan**：`Plan.md`  
**总计 Task**：4 个（全部完成）  
**回归测试结论**：`make test` 与 `make build` 100% 通过。  

---

## Phase 1：服务端非负校验与额度自洽

### TASK-001：后端渠道创建与更新接口非负金额校验及错误拦截

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/server/settings.go` 的 `createPaymentMethod` 与 `updatePaymentMethod` 中统一拦截 `< 0` 的 `InitialBalance` 与 `CreditLimit`，返回 400 Bad Request。
- **Details**：
  - `createPaymentMethod`：若 `req.InitialBalance != nil && *req.InitialBalance < 0` 返回 400（"initial balance cannot be negative"）；若 `req.CreditLimit != nil && *req.CreditLimit < 0` 返回 400（"credit limit cannot be negative"）；
  - `updatePaymentMethod`：同上增加相同校验；
  - 杜绝负授信额度绕过导致静默退化为不限额度。
- **Acceptance Criteria**：
  - 传入负数金额时返回 HTTP 400；
  - 正常正数或零值请求不受影响。

### TASK-002：后端负债渠道负欠款溢缴场景剩余额度上限自洽与单查询优化

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/server/stats.go` 中，对负债渠道多还款（溢缴款）时的可用额度进行上限 clamp，并移除 GROUP BY 冗余列。
- **Details**：
  - 在 `stats.go` 的资产负债统计中，`remainingCreditCents = creditLimitCents - currentDebtCents`；若 `remainingCreditCents > creditLimitCents` 则 clamp 为 `creditLimitCents`；若 `remainingCreditCents < 0` 则 clamp 为 0；
  - 聚合查询 SQL 的 `GROUP BY` 中移除冗余未查询列 `pm.sort_order`。
- **Acceptance Criteria**：
  - 当负债渠道欠款为负数时，剩余可用额度严格等于授信额度本身，不再超出上限；
  - SQL 聚合查询正常返回且无语法或逻辑错误。

### TASK-003：后端非负校验与溢缴额度上限测试用例覆盖

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/server/server_test.go` 中补充测试用例，覆盖非负校验与溢缴款场景额度上限自洽。
- **Details**：
  - 在 `TestPaymentMethodsAssetAndLiability` 中测试创建/更新渠道传入负初始金额或负授信额度时断言 400 响应；
  - 补充溢缴款场景测试，断言 `remaining_credit` 上限不超过 `credit_limit`。
- **Acceptance Criteria**：
  - `go test -v ./internal/server` 100% 通过。

---

## Phase 2：前端输入拦截、术语统一与去噪

### TASK-004：前端渠道输入非负约束、术语统一与宏观 KPI 解释性噪声消除

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `SettingsPage.tsx` 与 `StatsPage.tsx` 中落实非负数值约束、统一资产侧文案为“初始余额”，并移除宏观资产 KPI 中的解释性副标题。
- **Details**：
  - `SettingsPage.tsx`：为资产与负债新增及编辑表单的所有数值输入框添加 `min="0"`；并在提交处理函数中增加 `< 0` 前置校验与 Toast 友好提示；
  - `SettingsPage.tsx`：编辑表单中资产渠道的“底账”文案统一为“初始余额”；
  - `StatsPage.tsx`：资产渠道明细中的“底账：¥”统一为“初始余额：¥”；
  - `StatsPage.tsx`：移除净资产、资产总计、负债总计 3 联卡片下的解释性副标题（如“总资产扣减全部未清负债”等），去除界面解释性噪声。
- **Acceptance Criteria**：
  - 前端无法输入或提交负数金额；
  - 页面无“底账”混用，统一为“初始余额”；
  - 宏观 KPI 卡片布局紧凑清晰无文字噪声；
  - `tsc -b --noEmit` 编译无报错。
