# Tasks：复审问题修复（文档一致性与前端防御收敛）

**模式**：Quick  
**状态**：DONE  
**完成日期**：2026-10-05  
**总计 Task**：3 个（已完成 3 个）

---

## 执行任务清单

### TASK-001：消除 RecordModal.tsx 中前端手续费不可达防御分支

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/components/RecordModal.tsx` 中剔除表单提交阶段针对手续费的 `parsedFee < 0` 不可达冗余防御，保持逻辑纯净。
- **Details**：
  - 检查 `RecordModal.tsx:305`，手续费输入已受正则 `/^\d*\.?\d*$/` 严格约束为非负数值。
  - 将 `if (isNaN(parsedFee) || parsedFee < 0)` 简化为 `if (isNaN(parsedFee))`。
  - 服务端 `transactions.go` 保持对 `req.Fee < 0` 的信任边界校验。
- **Acceptance Criteria**：
  - 代码无不可达死分支；
  - 前端 `npx tsc -b --noEmit` 编译零错误；
  - 转账与手续费提交功能正常。

### TASK-002：校准 Project.md 术语表中双向资产转账守恒定义

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `.docs/Project.md` 术语表中修订「双向资产转账」定义，补充存在手续费时的精确变动表述，消除前后口径脱节。
- **Details**：
  - 将 `.docs/Project.md` 术语表中「双向资产转账」的定义调整为：
    `- **双向资产转账 (Bilateral Asset Transfer)** = 资金在两个资产渠道之间的内部划转，转出方扣减余额（含可选转账手续费），转入方增加本金余额，无手续费时总资产与净资产保持绝对守恒，产生手续费时总资产与净资产精确变动 -fee，不计入收支损益`。
  - 与约束决策中第 138/148 条保持口径完全一致。
- **Acceptance Criteria**：
  - 文档各处关于转账资产守恒陈述完全一致，无冲突矛盾。

### TASK-003：修正 Plan.md 方案比对表移除临时原型虚假引用并执行回归验证

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `.docs/10-05-v1/Plan.md` 中移除方案比对矩阵中指向已清理本地临时文件的 `Demo 静态原型` 行，并运行 `make test` 验证整体质量。
- **Details**：
  - 移除 `.docs/10-05-v1/Plan.md` 方案比对表格中第 111-115 行的 `Demo 静态原型` 行，消除对已删除临时原型的虚假引用。
  - 运行 `make test`，确保后端测试（`go test -v ./...`）与前端测试（`npm run lint && npm run test`）全部绿灯通过。
- **Acceptance Criteria**：
  - 归档 Plan.md 不再包含不存在文件的路径链接；
  - `make test` 退出码为 0，终端全绿。

---

## 回归测试结论

- **执行时间**：2026-10-05
- **执行命令**：`make test`
- **结论**：
  - 前端静态检查：`tsc -b --noEmit` 零错误；
  - 前端单元测试：`node --test test/*.test.ts` 19 项通过；
  - 后端单元与集成测试：`go test -v ./...` 全绿；
  - 任务状态：3/3 项 Task 全部标记为 DONE，复审意见逐项核销。

