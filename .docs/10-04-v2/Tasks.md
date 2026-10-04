# Tasks：复审问题修复与移动端边界适配 (Quick)

**关联审查**：复审报告（.docs/10-04-v1/）  
**总计 Task**：4 个

---

### TASK-001：修复 categories 迁移回填作用域至探针缺列分支

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/db/db.go` 中将历史老数据类型回填逻辑移入 `if !hasType` 分支内，杜绝每次重启覆盖用户手动纠错的分类类型。
- **Details**：
  - 将 `db.go:264-269` 的「职业收入→income」和「债务偿还→system」两句 UPDATE 语句移动到 `if !hasType { ... }` 内部；
  - 仅在探测到 categories 表缺失 `type` 列并执行 `ALTER TABLE ADD COLUMN` 之后执行一次性回填；
  - 在 `internal/db/db_test.go` 中追加测试：老库升级后模拟用户将「职业收入」修改为 `expense`，再次调用 `InitDB`，断言「职业收入」仍为 `expense`。
- **Acceptance Criteria**：
  - 存量无列老库升级时正常打标；
  - 已迁移数据库重启时不再强制执行类型回填，保留用户的类型修改。

### TASK-002：修复老库同名账户转账升级状态一致性与显式打标

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/db/db.go` 的 `ensureSystemTransferCategory` 中，获取分类 ID 后显式更新其 `type = 'system'`。
- **Details**：
  - 在 `ensureSystemTransferCategory` 取得 `catID` 后增加 `UPDATE categories SET type = 'system' WHERE id = ?`；
  - 确保即使老库曾自建过同名「账户转账」分类（导致 `INSERT OR IGNORE` 跳过），也能正确将其设置为 `system` 类型并由 `system_meta` 锁定；
  - 对称检查并在 `ensureSystemRepaymentCategory` 中同样增加 `UPDATE categories SET type = 'system' WHERE id = ?` 保持架构自洽；
  - 在 `internal/db/db_test.go` 中验证老库已含「账户转账」场景下的升级一致性。
- **Acceptance Criteria**：
  - 无论系统分类是新插入还是匹配既有同名行，升级后其 `type` 恒为 `system`；
  - 老库升级后系统分类正确归入设置页「系统内置分类」区。

### TASK-003：调整 BottomBar 筛选按钮移动端横向内边距消除重叠

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/components/BottomBar.tsx` 中调整胶囊按钮在移动端的内边距，消除 ≤375px 下与右侧悬浮记账按钮（FAB）的边缘重叠。
- **Details**：
  - 将按钮内边距样式由 `px-3.5 sm:px-4` 调整为 `px-2.5 sm:px-4`；
  - 移动端 5 个按钮总宽减少 40px，胶囊右缘收敛至约 272px，在 375px 视口下距离 FAB（起点 307px）保留 35px 充足安全间距；
  - 保持 `min-h-[40px]` 触控高度与 13px Segoe UI 字阶。
- **Acceptance Criteria**：
  - 320px–375px 视口下底部筛选胶囊与右侧 FAB 完全无视觉重叠；
  - 桌面端（≥640px）展示与既有排版完全一致。

### TASK-004：修复 Project.md 目录树排版冗余并执行全量测试

- **Status**：DONE
- **Executor**：主线
- **Description**：清理 `.docs/Project.md` 中重复出现的 `├─ internal/` 行，并执行前后端全量回归测试。
- **Details**：
  - 删除 `.docs/Project.md:44` 冗余的 `├─ internal/` 行，使 `config`、`db`、`server` 统一挂在单个 `internal` 节点下；
  - 运行 `go test -v -count=1 ./...` 与 `make test`；
  - 运行 `cd web && npm run build`。
- **Acceptance Criteria**：
  - `.docs/Project.md` 目录树排版正确无语法冗余；
  - 全量自动化测试与静态类型检查 100% 通过。
