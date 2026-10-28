# Tasks：收入统计口径补全、统计排除分类与下拉菜单圆角收敛

**关联 Plan**：`Plan.md` —— 收入统计口径补全、统计排除分类与下拉菜单圆角收敛 v1.1
**状态**：DONE（2026-10-28 交付完成）
**日期**：2026-10-28
**总计 Task**：9 个
**执行主体**：主线

---

## TASK-001：categories 增加统计排除列与热迁移

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / 无
- **Description**：在 `internal/db/db.go` 的全新建表语句加入 `exclude_from_stats INTEGER NOT NULL DEFAULT 0`，并在 `migrateCategoriesColumns` 中探测补列。
- **Details**：探针与既有 `type` 探测同轮完成；老库补列后默认 0，不重写已有数据；测试同时覆盖两条路径——`TestInitDB` 断言全新建库列存在且默认 0，`TestCategoriesMigration` 断言老库升级后列存在、默认 0，且升级后回填的用户数据不丢失。
- **Acceptance Criteria**：全新建库与老库升级均含该列且默认 0；`go test ./internal/db/...` 通过；把探针补列逻辑删除后两条用例均失败。

## TASK-002：分类接口读写统计排除字段

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-001
- **Description**：`internal/server/settings.go` 的 `Category` 增加 `ExcludeFromStats bool`（JSON `exclude_from_stats`），列表/创建/更新查询读写该列；创建与更新请求接受可选布尔值，缺省时创建为 false、更新保留原值。
- **Details**：更新沿用指针字段判定「未传」；系统分类仍走既有不可变守卫；不改变排序与标签语义；更新语句同时写回原值，避免默认值覆盖用户设置。
- **Acceptance Criteria**：创建带 `exclude_from_stats: true` 后列表返回 true；更新不传该字段时值不变；更新显式传 false 时回到 false；`go test ./internal/server/...` 相关用例通过。

## TASK-003：统计聚合补收入并统一排除过滤与排序

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-001
- **Description**：重构 `internal/server/stats.go`：抽出按类型的金额汇总、分类构成（含标签下钻）与渠道分布查询，支出/收入共用；所有收支聚合 JOIN `categories` 并过滤 `exclude_from_stats = 0`；响应新增 `week_income`、`last_month_income`、`income_category_distribution`、`income_payment_distribution`。
- **Details**：
  - 汇总：`SUM(amount_cents)` 取绝对值，按 `type` 与分类标记过滤；周/月/上月、收入/支出共 6 个基础值；趋势的 6 个月逐月同口径。
  - 分布排序：分类、标签、渠道统一 `ORDER BY ABS(SUM(t.amount_cents)) DESC`（支出为负数、收入为正数，绝对值降序在两种类型下都是「金额从大到小」）。
  - 百分比分母：分类与渠道使用同类型、过滤后的当月总额（收入用 `monthIncome`、支出用 `monthExpense`）；标签使用所属分类金额。四舍五入仍为一位小数。
  - 结余 = 纳入统计的收入 − 支出；储蓄率同口径；资产负债查询保持不动。
  - 共用逻辑仅按 `type`/`start`/`end` 收敛，不引入泛型或配置化查询框架。
  - 测试：(1) 创建一笔收入与一笔支出，断言 `week_income`、`month_income`、`last_month_income`、两份分布均非空且数值精确；(2) 构造大额与小额两个收入分类，断言收入构成首项为大额、两个百分比之和约 100（±0.2）；(3) 将支出分类置为排除后重新请求，断言周/月/上月支出、支出构成、渠道分布、趋势当月值、余额与储蓄率按排除后金额精确变化，且资产字段逐字段不变。
- **Acceptance Criteria**：上述断言全部通过；删除任一分类过滤条件或把排序改回 `ASC` 时对应用例失败；重复运行结果稳定。

## TASK-004：客户端模型、接口、控制器与测试夹具

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P1 / TASK-002、TASK-003
- **Description**：Dart `Category` 增加 `excludeFromStats` 并纳入 JSON 往返；`StatsSummary` 增加 `weekIncome`、`lastMonthIncome`、`incomeCategoryDistribution`、`incomePaymentDistribution`；`ApiClient.updateCategory` 支持可选 `excludeFromStats`；`LedgerController` 增加设置分类统计口径的方法并刷新配置与统计。
- **Details**：
  - 新字段按既有严格风格设为 required；`fromJson` 对缺省值容错（收入为 0、分布为空列表），旧缓存快照不被判为损坏。
  - 同步夹具：`app/test/support/fakes.dart` 的 `emptyStats()`、`app/test/features/stats_assets_test.dart` 的 `zero`、`app/test/support/harness.dart` 的 `statsJson()`（补收入汇总、收入分类与收入渠道样例）。`ledger_cache_test` 经 `statsJson()` 自动覆盖新字段往返。
  - 控制器方法写入后并行刷新 `loadConfig()` 与 `loadStats()`；`moveCategory` 不传该字段，避免调序覆盖用户设置。
- **Acceptance Criteria**：`flutter analyze` 无告警；模型 JSON 往返用例覆盖新字段；控制器用例断言一次设置触发配置与统计各刷新一次；`moveCategory` 请求体不含 `exclude_from_stats`。

## TASK-005：统一 PopupMenu 圆角裁剪

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / 无
- **Description**：为 5 处 `PopupMenuButton` 设置 `clipBehavior: Clip.antiAlias`：`app/lib/features/stream/stream_screen.dart`（筛选菜单、流水行更多操作）、`app/lib/features/settings/settings_screen.dart`（分类操作、账户操作）、`app/lib/features/settings/tag_sheet.dart`（标签操作）。
- **Details**：不改菜单形状、主题、内边距与条目结构；仅在内容层裁剪到既有 16px 圆角。
- **Acceptance Criteria**：5 处均有该参数；`stream_screen_test` 断言筛选与行操作菜单、`settings_test` 断言分类与账户菜单、打开标签抽屉后断言标签菜单的 `clipBehavior` 均为 `Clip.antiAlias`；既有菜单交互用例不回归。

## TASK-006：统计页收入视角与环形图文案

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P1 / TASK-004
- **Description**：统计页增加「支出 / 收入」视角切换；指标卡、构成图（含环形图中心与语义文案）、渠道分布、空态文案与标题随视角切换；派生函数改为按数值计算。
- **Details**：
  - 视角控件：全宽 `SegmentedButton`（`expandedInsets: EdgeInsets.zero`，与设置页同构），位置在结余头条与指标卡之间；切换视角不重置图表卡「构成 / 趋势」选择，趋势始终为双线收支。
  - `DonutChart` 增加 required `centerLabel` 与 `semanticsLabel`，由统计页按视角传入（「本月支出 / 支出构成环形图」「本月收入 / 收入构成环形图」），移除两处硬编码。
  - 指标卡：支出用现有「本周花费/当月花费/上月花费/日均花费」，收入用「本周收入/当月收入/上月收入/日均收入」；收入环比上升取收入色、下降取支出色。
  - 构成与渠道：支出用 `categoryDistribution`/`paymentDistribution` + `monthExpense`，收入用 `incomeCategoryDistribution`/`incomePaymentDistribution` + `monthIncome`；空态分别为「当月暂无分类支出/收入」「当月暂无渠道支出/收入」；渠道区块标题「支付途径 / 收入途径」。
  - 派生函数改为 `dailyAverage(amount, now)` 与 `monthOverMonth(current, previous)`，同步更新既有调用与单测。
  - 测试：切换收入后断言「收入构成」「本周收入」「收入途径」「本月收入」存在，断言「支出构成」「本周花费」「支付途径」「本月支出」不存在（结余头条的「支出」标签保持存在）；320dp + 2 倍字体下同时切换视角与图表模式无异常。
- **Acceptance Criteria**：上述断言通过；默认支出视角与现状一致；`stats_test` 既有用例仅按新派生函数签名调整，不断言失败。

## TASK-007：流水日小计接入统计口径

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P1 / TASK-004
- **Description**：`app/lib/features/stream/stream_utils.dart` 的 `daySubtotalParts`/`daySubtotal` 增加可选排除分类集合，流水页从 `LedgerController.categories` 派生后传入。
- **Details**：排除集合默认为空，保持既有调用与用例兼容；`TransactionDayGroup.expense/income` 增加按类别过滤的求和入口（或由小计函数自行过滤），流水条目本身不隐藏；配置未加载时集合为空，退化为全量小计。
- **Acceptance Criteria**：新增单测断言排除分类的流水不计入日小计、未排除分类不受影响；新增 Widget 用例断言排除后日小计与本月头条口径一致；既有 `daySubtotal` 断言不变。

## TASK-008：分类行统计口径开关

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P1 / TASK-004
- **Description**：分类行溢出菜单新增「不计入收支统计 / 计入收支统计」，行内副标题追加「不计入统计」；切换后写入并刷新。
- **Details**：失败走既有 SnackBar 错误提示；系统分类不显示该操作；开关不改变分类排序与标签；切换成功后统计与日小计同步刷新（复用 TASK-007 的口径）。
- **Acceptance Criteria**：Widget 用例断言菜单项文案随状态切换、请求体包含 `exclude_from_stats`、行内出现「不计入统计」；失败路径提示可见。

## TASK-009：门禁、文档、归档与提交

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-001 ~ TASK-008
- **Description**：执行门禁、同步 `.docs/Project.md`、标记 Plan/Tasks 完成并归档、按路径提交。
- **Details**：
  - 工具链前置：`export PATH=/home/dev/flutter/bin:$PATH`（当前文件策略下 SDK 可写，直接调用即可）；若 SDK 再次只读，改用 `FLUTTER_ALREADY_LOCKED=true` 直接调用 `flutter_tools.snapshot`，并把 `HOME` 指向 `/tmp/dart_home`。
  - 门禁（逐条取退出码并记录）：`go vet ./...`、`go test ./...`、`cd app && dart format --output=none --set-exit-if-changed lib test`、`flutter analyze`、`flutter test`。
  - 文档：Project.md 更新统计接口字段、分类标记、客户端视角与菜单裁剪、测试项数与决策记录；归档前把 Plan.md/Tasks.md 状态改为 `DONE`，回填完成日期、门禁结果与测试项数。
  - 归档：目标目录 `.docs/10-28-v1/`（同日已存在则递增 N），移入 Plan.md 与 Tasks.md，校验根目录无残留。
  - 提交：先用 `git diff --cached --name-only` 查看已暂存内容；本次提交使用路径限定 `git commit -- <本轮路径>`，或在提交前 `git restore --staged` 无关文件；提交后 `git show --name-only HEAD` 复核只含本轮路径。不触碰既有技能文件暂存与 `temp/` 未跟踪文件。
- **Acceptance Criteria**：五道门禁退出码为 0 并记录实际测试项数；Project.md 与实现一致；归档目录同时含 Plan.md 与 Tasks.md 且根目录无残留；`git show --name-only HEAD` 仅含本轮路径。

## 完成记录

- 完成日期：2026-10-28
- 门禁：`go vet ./...` 0；`go test -v ./...` 24 项通过；`dart format` 0 变更；`flutter analyze` No issues；`flutter test` 122 项通过。
- 新增用例：`TestStatsIncomeAndExclusionFilter`（收入汇总/分布排序/排除过滤/资产不变）、`TestSettingsCRUDAndGuards` 统计口径往返、`TestInitDB`/`TestCategoriesMigration` 排除列默认值、客户端统计双视角、分类开关写入与失败、流水日小计排除、五处菜单裁剪、模型/缓存/控制器契约。
- 归档：`.docs/10-28-v1/`。
