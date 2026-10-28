# Tasks：收入统计复审残留收敛（Quick）

**关联 Plan**：无（Quick 模式跳过 Plan，故本归档仅含 Tasks.md）  
**状态**：DONE（2026-10-28 完成）  
**日期**：2026-10-28  
**总计 Task**：4 个  
**执行主体**：主线

## 背景

上一轮 `.docs/10-28-v1`（`cf679fa`）的 Review 报告给出 95 分与 4 条问题、1 条观察。逐条对照代码核实后的取舍：

- **P3 系统分类迁移后无法调整统计口径**：成立。`ensureSystem*Category` 会把老库中同名自建分类直接改为 `type='system'`，而系统分类的 PUT 被 400 拦截、设置页也无统计口径入口；若该分类下已有历史 expense/income 流水，这些流水仍进入统计且无自助出口。采纳：系统分类在 ensure 时同步置 `exclude_from_stats = 1`，并补带历史流水的升级用例。系统分类本就不参与收支（还款/转账按 type 排除），该标志只影响被迁移分类里的历史流水，语义一致。
- **P4 统计测试依赖运行时周/月边界**：成立但概率极低。采纳最小确定性方案：统计处理器读取包级 `nowFunc`，两个统计用例冻结到固定时刻；不引入时钟接口或注入框架。
- **P4 `last_month_income` 排除过滤缺直接断言**：成立。上月补一笔被排除分类的收入，断言排除前 1500、排除后 1000。
- **P4 Web `StatsSummary` 类型未同步**：部分采纳。Web 只消费部分字段，补齐未消费字段违背 YAGNI；在接口处注明「仅声明已消费字段」，不改类型形状。
- **观察：视角切换保留分类选中态**：驳回。选中分类在另一视角不存在时详情面板自然隐藏，切回原视角恢复原选择；无错误数据，重置反而增加跨视角状态耦合。

范围限定 2 个 Go 源文件、2 个 Go 测试文件、1 个 Web 类型声明与 `.docs/Project.md`。

## TASK-001：系统分类默认排除统计并覆盖迁移场景

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / 无
- **Description**：`internal/db/db.go` 的 `ensureSystemRepaymentCategory` 与 `ensureSystemTransferCategory` 在既有幂等 `UPDATE ... SET type = 'system'` 中同步写入 `exclude_from_stats = 1`。
- **Details**：不新增迁移轮次、不新增列；两处系统分类的 ensure 每次启动都会执行，既有已升级库在下一次启动时自动补齐。`internal/db/db_test.go` 更新全新建库与分类迁移断言：用户分类默认计入、两个系统分类默认排除；`TestOldDatabaseWithCustomTransferCategoryUpgrade` 增加一条挂在旧「账户转账」分类下的 expense 流水，升级后断言该分类 `exclude_from_stats = 1`、按统计过滤口径计数为 0、流水本身仍保留。
- **Acceptance Criteria**：`go test ./internal/db/...` 通过；移除 ensure 中的 `exclude_from_stats = 1` 后全新建库、分类迁移与自定义转账分类三条用例均失败。

## TASK-002：冻结统计时钟并补上月收入排除断言

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P1 / 无
- **Description**：`internal/server/stats.go` 增加包级 `nowFunc = time.Now`，`handleStatsSummary` 改用它取当前时间；`TestStatsSummary` 与 `TestStatsIncomeAndExclusionFilter` 冻结到 `2026-10-28 20:00` 本地时间并在 `t.Cleanup` 恢复。
- **Details**：不引入时钟接口、依赖注入或新包。后者在「内部转入」分类的上月位置补一笔 500 元收入，排除前 `LastMonthIncome` 断言 1500，排除后仍断言 1000，直接覆盖上月收入的过滤路径。
- **Acceptance Criteria**：`go test ./internal/server/...` 通过；把 `sumByType` 的分类过滤删除后，上月收入断言由 1000 变为 1500 并失败。

## TASK-003：注明 Web 统计类型为已消费子集

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P1 / 无
- **Description**：`web/src/lib/api.ts` 的 `StatsSummary` 接口上方加一行注释，说明仅声明 Web 已消费字段、其余字段按需补充。
- **Details**：不补 `week_income`、`last_month_income` 与两份收入分布等未消费字段；Plan 已明确 Web 不提供收入视角，类型形状保持不变，避免死类型面。
- **Acceptance Criteria**：`cd web && npm run lint` 退出码 0；接口字段与改动前一致。

## TASK-004：门禁、文档、归档与按路径提交

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-001 ~ TASK-003
- **Description**：执行 Go 与 Web 门禁，同步 `.docs/Project.md`，标记本文档完成，归档至 `.docs/10-28-v2/`，按路径提交。
- **Details**：门禁逐条取退出码并记录：`go vet ./...`、`go test -count=1 ./...`、`cd web && npm run lint && npm test`。Flutter 代码未改动，沿用上一轮 122 项通过记录，不重复执行。提交前 `git diff --cached --stat` 确认范围，使用路径限定提交，不触碰工作区既有的技能文件暂存、`.pi/` 删除与 `temp/` 未跟踪文件。
- **Acceptance Criteria**：门禁退出码为 0 并记录测试项数；Project.md 与实现一致；`.docs/10-28-v2/Tasks.md` 存在且根目录无残留；`git show --name-only HEAD` 仅含本轮路径。

## 完成记录

- 完成日期：2026-10-28
- 门禁：`gofmt -l` 无输出；`go vet ./...` 退出码 0；`go test -count=1 ./...` 24 项通过（db 6、server 17、web 1）；`cd web && npm run lint` 退出码 0；`npm test` 38 项通过。Flutter 代码未改动，沿用上一轮 122 项通过记录。
- 变异校验：移除两处 `exclude_from_stats = 1` 后，`TestInitDB`、`TestCategoriesMigration`、`TestOldDatabaseWithCustomTransferCategoryUpgrade` 三条用例均失败；移除 `sumByType` 的分类过滤后，上月收入断言由 1000 变为 1500 并失败；恢复后全部通过。
- 变更：`internal/db/db.go`、`internal/db/db_test.go`、`internal/server/stats.go`、`internal/server/server_test.go`、`web/src/lib/api.ts`、`.docs/Project.md`。
- 归档：`.docs/10-28-v2/`。
