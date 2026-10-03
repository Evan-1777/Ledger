# Tasks：负债还款复审反馈批判性修复（Quick）

**状态**：DONE  
**完成日期**：2026-10-03  
**模式**：Quick  
**回归测试结论**：`make test` 全部通过（Go 单元与集成测试 PASS，前端 TypeScript 检查零错误）；`make build` 成功产出单二进制可执行文件 `bin/ledger`。  
**总计 Task**：3 个（已全部完成）  

---

### TASK-001：修复渠道删除 409 守卫盲区并补充专用集成测试

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/server/settings.go` 的 `handleDeletePaymentMethod` 中，将关联账单检查扩展至 `source_payment_method_id`，并在 `internal/server/server_test.go` 中补充针对“仅作为转出渠道被引用”的 409 Conflict 拦截单测。
- **Details**：
  - 守卫 SQL 查询调整为 `SELECT COUNT(1) FROM transactions WHERE payment_method_id = ? OR source_payment_method_id = ?`；
  - 在 `server_test.go` 中新增测试用例，创建一个还款账单并指定资产渠道为 `source_payment_method_id`（目标为其他渠道），尝试删除该资产渠道，断言返回 409 Conflict。
- **Acceptance Criteria**：
  - 仅作为转出渠道被引用的支付渠道在删除时返回 409 Conflict，不再穿透至底层 FK RESTRICT 导致 500；
  - 现有及新增 Go 测试 100% PASS。

---

### TASK-002：补全 RecordModal 无负债渠道时交互引导与提交禁用

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/components/RecordModal.tsx` 与 `web/src/App.tsx` 中，当还款模式且负债渠道数量为 0 时，禁用提交按钮并提供前往基础设置的快捷引导。
- **Details**：
  - `RecordModalProps` 增加 `onNavigateToSettings?: () => void`；
  - 在 `App.tsx` 中透传该回调，点击后关闭模态窗并切换 `currentTab` 至 `'settings'`；
  - `RecordModal.tsx` 在无负债渠道的提示条内增加“前往设置添加 →”按钮，并将提交按钮设置为禁用状态（`disabled={submitting || (recordType === 'repayment' && liabilityMethods.length === 0)}`）。
- **Acceptance Criteria**：
  - 还款模式下无负债渠道时，表单提交按钮置灰且不可点击；
  - 点击引导文案能跳转至设置页面；
  - `npm run lint` / `tsc -b --noEmit` 检查零错误。

---

### TASK-003：清理测试死代码与修复历史归档文档口径与瑕疵

- **Status**：DONE
- **Executor**：主线
- **Description**：清理 `internal/server/server_test.go` 历史死代码行，并修复 `.docs/10-03-v3/Plan.md` 中的模板残留与协同执行口径。
- **Details**：
  - 移除 `server_test.go:279` 处的冗余死代码行 `req = httptest.NewRequest("DELETE", "/api/payment-methods/"+strings.TrimSpace(string(rune(pm.ID+'0'))), nil)`；
  - 修正 `.docs/10-03-v3/Plan.md` 第 13 行的字面量 `债务偿${还}` 为 `债务偿还`；
  - 对齐 `.docs/10-03-v3/Plan.md` 第 112 行关于 Phase 5 实际由主线完成的决策说明。
- **Acceptance Criteria**：
  - `server_test.go` 无死代码；
  - `.docs/10-03-v3/Plan.md` 瑕疵清理完毕，文档真实一致。
