# Tasks：记账分类标签层级、流水筛选面板与统计区间筛选

**关联 Plan**：`Plan.md` —— 记账分类标签层级、流水筛选面板与统计区间筛选 v1.2
**状态**：DONE（2026-10-29 交付完成）
**日期**：2026-10-29
**版本**：v1.2（按 2026-10-29 评审报告修订门禁、类型约束、面板契约与测试缺口）
**总计 Task**：14 个
**执行主体**：主线

---

## 前置约定

- 所有界面沿用项目既定的 Material 3 体系：seed `#0078D4`，颜色只用 `Theme.of(context).colorScheme` 与 `financeColors(context)`，间距用 4/8 刻度，不新增硬编码色值。
- 记账与统计弹层沿用现有 `LedgerCard`、`SegmentedButton`、`ChoiceChip`、`FilledButton` 等构件，不引入第三方依赖。
- 门禁命令（2026-10-29 在本机实测：`dart format` 0 变更、`analyze` 无问题、`test` 122 项通过）：

```bash
cd app
/home/dev/flutter/bin/dart format --output=none --set-exit-if-changed lib test
FLUTTER_ALREADY_LOCKED=true /home/dev/flutter/bin/flutter analyze
FLUTTER_ALREADY_LOCKED=true /home/dev/flutter/bin/flutter test
cd .. && gofmt -l . && go vet ./... && go test -count=1 ./...
cd web && npm run lint && npm test
```

- 若执行环境 `$HOME` 只读导致 `bin/cache` 写入失败，改用 `flutter_tools.snapshot` 直接调用（`.docs/Project.md` 记录的同一方式），不因此缩小门禁范围。
- Web 端本轮不改，但 `make test` 的口径包含 `web`，门禁照跑，避免「未改即未验」。
- Demo 文件：`temp/ledger-ui-variant-b.html`（采纳方案：分类/标签双字段 + 各自选择面板、分类面板限当前类型、流水选择面板、统计「口径摘要 + 统一筛选面板」）、`temp/ledger-ui-variant-a.html`（备选对照：单入口内联二级分组 + 三胶囊筛选）。实现以方案 B 为准。

---

## Phase 1：后端区间聚合与筛选契约

### TASK-001：统计聚合增加分类/标签过滤入口

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P1 / 无
- **Description**：在 `internal/server/stats.go` 引入单一过滤条件值对象（分类 ID、标签 ID，0 表示不过滤），把条件拼装集中到一处；`sumByType`、`categoryDistribution`、`paymentDistribution` 增加该参数并在各自的分类/标签查询中应用；`handleStatsSummary` 全部调用改传空过滤。
- **Details**：
  - 过滤条件以 `t.category_id = ?` / `t.tag_id = ?` 追加到既有 WHERE 之后，保留 `c.exclude_from_stats = 0` 与类型条件。
  - 分类构成的标签下钻查询同样应用过滤，避免「主分布过滤、标签下钻不过滤」的口径分裂。
  - 不改变 `StatsSummaryResponse` 字段与任何现有数值；不新增参数到 `/api/stats/summary`。
- **Acceptance Criteria**：
  - `gofmt -l internal/server` 无输出；`go vet ./...` 退出码 0。
  - `go test -count=1 ./...` 既有 24 项全部通过（数值与改动前一致）。
  - 过滤拼装的变异校验统一在 TASK-003 执行，本 Task 不重复。

### TASK-002：新增区间统计端点 GET /api/stats/range

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-001
- **Description**：在 `internal/server/stats.go` 实现 `handleStatsRange`，并在 `internal/server/server.go` 注册 `GET /api/stats/range`（走 `requireAuth`）。
- **Details**：
  - 查询参数：`start`、`end`（`yyyy-MM-dd`，含首含尾）、`category_id`、`tag_id`（可选正整数）。
  - 参数校验：只传一个日期、格式非法、`start > end`、ID 非正整数均返回 400。
  - 兜底默认（客户端固定传日期，正常流程走不到）：两个日期都缺省时取「服务端本地时间的当月 1 日 ~ 今天」；未来区间 `days` 按 1 计。只作为接口自洽，不进入主流程用例。
  - 响应字段（snake_case）：`days`（区间内已过天数，未来区间按 1 计）、`expense`、`income`、`balance`、`previous_expense`、`previous_income`、`expense_count`、`income_count`、`category_distribution`、`income_category_distribution`、`payment_distribution`、`income_payment_distribution`、`monthly_trends`。
  - 「上期」= 起止日期各向前移动一个日历月，日期超出目标月天数时夹取到月末（如 10-31 → 09-30）。
  - 6 个月趋势以 `end` 所在月为末月，向前 6 个月，逐月按同一过滤条件聚合。
  - 所有金额沿用 `math.Abs(cents)/100`；分类构成百分比分母为该类型过滤后总额；渠道分布同口径。
  - 复用 TASK-001 的过滤入口，不复制 SQL 分支。
- **Acceptance Criteria**：
  - 缺省参数返回当月起止区间与正确天数；显式区间返回对应金额。
  - `category_id` 与 `tag_id` 分别只影响过滤后的汇总、构成与趋势。
  - `exclude_from_stats = 1` 的分类在所有字段中被排除。
  - 非法日期、单边日期、反向区间、非法 ID 均返回 400 与 JSON 错误体。

### TASK-003：后端区间统计集成用例

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-002
- **Description**：在 `internal/server/server_test.go` 新增 `TestStatsRange` 与 `TestStatsRangeFilters`，冻结 `nowFunc` 到 `2026-10-28 20:00` 并在 `t.Cleanup` 恢复。
- **Details**：
  - 数据：当月两笔支出（同分类不同标签、不同渠道）、一笔收入、上月同区间一笔支出、一笔本地 `2026-10-01 00:30` 的支出（UTC 为 09-30 16:30），以及一个 `exclude_from_stats = 1` 的分类流水。
  - `TestStatsRange`：断言 `days=28`、区间收支与结余（本地日界那笔归入 10 月）、`expense_count`/`income_count`、上期金额（9 月 1~28 日）、`monthly_trends` 长度 6 且末月为 `2026-10`、构成与渠道金额。
  - 月末夹取：另以 `2026-10-01`~`2026-10-31` 请求，断言上期区间为 `2026-09-01`~`2026-09-30`。
  - `TestStatsRangeFilters`：分别用 `category_id`、`tag_id` 请求，断言汇总、分类构成、渠道分布与 `monthly_trends` 四者都只剩对应维度；断言排除分类不进入任何字段；表驱动覆盖非法参数 400。
  - 变异校验：临时移除 `statsFilter` 的 WHERE 拼装后两条用例必须失败（一次即可，不在 TASK-001 重复）。
- **Acceptance Criteria**：
  - `go test -count=1 ./internal/server/...` 通过，新增用例 2 项。
  - 变异后用例失败，恢复后通过。
  - 不修改既有用例的期望值。

---

## Phase 2：客户端统计数据层

### TASK-004：区间统计模型、查询值对象与客户端方法

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P1 / TASK-002
- **Description**：在 `app/lib/core/api/models.dart` 增加 `RangeStats`（含 `days`、`expense`、`income`、`balance`、`previousExpense`、`previousIncome`、`expenseCount`、`incomeCount`、两组 `CategoryStat`、两组 `PaymentMethodStat`、`monthlyTrends`），字段解析全部走既有 `_asDouble`/`_asList` 容错；新增 `StatsQuery`（起止日期 + 可选分类/标签 ID，含 `==`/`hashCode` 与 `StatsQuery.currentMonth(DateTime now)`）。
- **Details**：
  - `app/lib/core/format/dates.dart` 增加 `formatDateParam(DateTime)`（`yyyy-MM-dd`）。
  - `app/lib/core/api/api_client.dart` 增加 `getRangeStats(StatsQuery)`，query 参数 `start`/`end`，有值时附 `category_id`/`tag_id`。
  - `RangeStats` 不需要 `toJson`（本轮不入缓存）；不新增端点常量表或抽象层。
- **Acceptance Criteria**：
  - 空对象 JSON 解析为全零 `RangeStats` 不抛错；完整 JSON 各字段解析正确。
  - `getRangeStats` 生成的 URL 路径与四个 query 参数符合端点契约（在 TASK-005 的控制器用例中断言）。

### TASK-005：控制器区间统计状态、加载与刷新接线

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-004
- **Description**：在 `app/lib/core/state/ledger_controller.dart` 增加 `statsQuery`、`rangeStats`、`rangeStatsLoading`、`rangeStatsError` 与 `_rangeStatsGeneration`，实现 `loadRangeStats()`、`setStatsQuery(next)` 与 `_pruneStatsQuery()`；把区间统计接入 `loadAll`、`refreshAfterTransactionChange`、`setCategoryExcluded`、`refreshAfterChannelChange`，并在 `clear()` 中重置（含代际自增）。
- **Details**：
  - `statsQuery` 在构造时初始化为 `StatsQuery.currentMonth(DateTime.now())`。
  - `loadRangeStats` 与 `loadStats` 采用同一代际/401/错误文案模式，错误文案「加载统计失败」。
  - `setStatsQuery` 相同时直接返回；变化时置 `statsQuery`、清空 `rangeStats` 与 `rangeStatsError`、通知、再加载——失败时页面上没有旧数字可残留。
  - `_pruneStatsQuery()` 在 `loadConfig` 成功分支末尾调用：筛选的分类不在新 `categories` 中则同时清空分类与标签；标签不在该分类下则只清空标签；有变化时 `await loadRangeStats()`。分类/标签新增与重命名不触发区间请求。
  - `loadAll` 改为四域并行；不新增缓存读写。
  - 在 `app/test/core/ledger_controller_test.dart` 补三例：查询变化触发带 `start/end/category_id/tag_id` 的请求并更新结果；快速连续切换时旧响应不覆盖新结果；删除正在筛选的标签后 `statsQuery.tagId` 归零并重新请求。
- **Acceptance Criteria**：
  - 新用例通过；既有控制器用例（水合、写穿、401、筛选代际）全部通过。
  - 记账新增/编辑/删除后区间统计被重新请求。
  - 删除正在筛选的分类后 `statsQuery` 回落为「全部维度」、删除标签后只剩分类，两者都重新请求；重命名不产生额外请求。

---

## Phase 3：共享选择面板与记账双字段

### TASK-006：共享选择面板构件

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / 无
- **Description**：在 `app/lib/core/widgets/ledger_widgets.dart` 增加 `showLedgerPicker<T>`（带标题的模态底部面板，返回所选值）与 `LedgerPickerOption`（48dp 起、左标题右勾选、可选副标题/前置图标），供记账与流水复用；统计筛选面板沿用同一视觉约定。
- **Details**：
  - 签名与返回语义（三个调用点共用，不再各自定义）：
    ```dart
    Future<T?> showLedgerPicker<T>({
      required BuildContext context,
      required String title,
      String? description,
      required List<Widget> children,
      Widget? footer,
    });
    ```
    面板只做容器：遮罩、28dp 顶部圆角、`useSafeArea`/`isScrollControlled`、内容可滚动、左右 8dp 内边距、标题 `titleMedium` + `w600`；**不持有选中态、不调用控制器**。返回值只来自选项 `onTap` 里的 `Navigator.pop(context, value)`；遮罩/返回键/下滑得到 `null`。
  - 打开前执行 `FocusScope.of(context).unfocus()`：记账金额输入框聚焦时打开面板，键盘 `viewInsets` 不再压缩面板高度。
  - 选项行 `LedgerPickerOption({required String label, String? subtitle, bool selected = false, VoidCallback? onTap, IconData? leading})`：`Material` + `InkWell` + `Semantics(selected: ...)`，最小高度 48，选中显示 `Icons.check_rounded`（`primary`），未选中保留等宽占位避免文字跳动。
  - 分组标题与空态由调用方以普通 `Text`/`EmptyState` 放进 `children`，不新增分组构件与数据驱动 API；不新增文件。
- **Acceptance Criteria**：
  - 记账分类/标签与流水筛选复用同一面板壳与选项行，无重复实现；统计筛选面板沿用同一标题、内边距与安全区约定。
  - 三个调用点都只通过 `Navigator.pop` 回传选择，面板内没有控制器调用。
  - 选项与标题在 2 倍字体下不溢出（由 TASK-008/009/012 覆盖）。

### TASK-007：记账弹层改为分类/标签双字段

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-006
- **Description**：在 `app/lib/features/record/record_sheet.dart` 删除内联展开的分类区，改为「分类」「标签」两个字段行，各自通过 `showLedgerPicker` 打开分类面板与标签面板；转账/还款分支保持只读系统分类行。
- **Details**：
  - 只替换 `_type` 为支出/收入的分支（`record_sheet.dart` 中调用 `_buildCategorySection` 的那个 `if`）；转账/还款继续调用 `_buildSystemCategory`，只读行与系统分类自动回填不变。
  - 删除 `_categoryOpen` 状态与 `_buildCategorySection`（胶囊、汇总卡、「更换」「收起」一并移除）；新增 `_openCategoryPicker` 与 `_openTagPicker`，各自 `await showLedgerPicker<T>` 后按返回值 `setState`。
  - 字段行：`LedgerCard`（`surfaceContainerHigh`，`onTap`），左侧 `sell_outlined` / `local_offer_outlined`，中间值（未选显示「选择分类」/「选择标签」），右侧 `chevron_right`；保持与其他字段一致的标签在上、控件在下的节奏。
  - 分类面板：标题「选择分类」，说明行「支出分类」/「收入分类」；选项只取 `_categoriesForType()`，不出现另一类型的分类；每行副标题为该分类的标签名以「 · 」连接（无标签显示「暂无细分标签」）；返回 `Category` 后写入 `_categoryId` 并自动带入该分类首个标签（无标签置空）。
  - 标签面板：标题「选择标签」，说明行为当前分类名；选项只取当前分类的标签；返回 `Tag` 后写入 `_tagId`；分类无标签时显示「该分类暂无细分标签」，`onOpenSettings != null` 时在 `footer` 提供「前往设置」。
  - 无分类时：分类面板以 `EmptyState` 显示「暂无分类，请先在设置中添加」并提供设置入口；标签面板显示「先选择分类」。
  - 保留 `_needsDefaults` / `_adoptMissingDefaults` / 类型切换重置与校验逻辑；提交契约不变。
- **Acceptance Criteria**：
  - 支出/收入表单只出现「分类」「标签」两个字段行，不再有内联展开区、「更换」或「收起」。
  - 支出单据的分类面板不出现任何收入分类；切到收入后只出现收入分类。
  - 点分类字段只打开分类面板，点标签字段只打开标签面板；两者都靠返回值回填，面板关闭后表单值才变化。
  - 分类行显示标签摘要；选分类后标签字段自动变为该分类首个标签。
  - 标签面板只包含当前分类的标签；空标签有说明与（回调存在时）设置入口。
  - 转账/还款仍显示只读系统分类行，分类字段不可点击。
  - 编辑既有账单时两个字段显示原分类与标签。

### TASK-008：记账双字段与面板用例

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-007
- **Description**：更新 `app/test/features/record_sheet_test.dart`，覆盖双字段、面板内容、分类联动标签与空态。
- **Details**：
  - 默认态：存在「分类」「标签」两个字段标签，值分别为「餐饮美食」「午餐」；不存在内联分组标题。
  - 点分类字段：面板出现「选择分类」与「支出分类」，点「交通出行」后面板关闭、标签字段变为「地铁」。
  - 类型隔离：支出单据的分类面板不出现收入分类（如「职业收入」）；切到收入后分类面板不出现支出分类。
  - 点标签字段：面板只出现当前分类的标签（如「地铁」），不出现其他分类的标签；点选后面板关闭。
  - 空标签：让某分类 `tags` 为空，选中后打开标签面板显示说明；`onOpenSettings` 为空时不渲染「前往设置」。
  - 转账单据：仍渲染系统分类行，不出现可点击的分类字段。
  - 320dp + 2x：分别打开分类与标签面板后无异常；既有 320dp + 2x 用例保留。
- **Acceptance Criteria**：
  - 新增用例 ≥5 项并通过；既有记账用例不回归。

---

## Phase 4：流水筛选与统计筛选面板

### TASK-009：流水页筛选改为选择面板

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-006
- **Description**：在 `app/lib/features/stream/stream_screen.dart` 用 `showLedgerPicker<TransactionFilter>` 替换 `_FilterMenu` 的 `PopupMenuButton`；触发胶囊保持「筛选图标 + 当前值 + 下箭头」、48dp 触达与 `ValueKey('filter-menu')`。
- **Details**：
  - 每个选项 `onTap` 只做 `Navigator.pop(context, filter)`，选项保留 `ValueKey('filter-${filter.name}')`；调用处 `final picked = await showLedgerPicker<TransactionFilter>(...); if (picked != null) ledger.setFilter(picked);`。
  - 当前项以 `selected: filter == item` 显示勾选；面板关闭后才发请求。
  - 行内「更多操作」菜单保持 `PopupMenuButton` 与 `Clip.antiAlias` 不动。
  - 更新 `app/test/features/stream_screen_test.dart`：删除筛选菜单的 PopupMenu 裁剪断言，保留行内菜单裁剪断言；改为打开面板、断言五个选项与选中态、选择后请求 `type=expense`、触发胶囊文案更新；320dp + 2x 用例改为打开面板后无异常且选项可见。
- **Acceptance Criteria**：
  - 流水页不再有筛选用 PopupMenuButton；面板完整显示 5 个选项。
  - 用例全部通过，行内删除确认流程不回归。

### TASK-010：统计口径摘要与统一筛选面板

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-005、TASK-006
- **Description**：在 `app/lib/features/stats/stats_screen.dart` 顶部加入「口径摘要 + 筛选」入口与 `_StatsFilterSheet` 草稿面板；在 `app/lib/features/stats/stats_utils.dart` 增加范围预设（`StatsRangePreset` + `resolveRange(preset, now)`）、范围标签、口径摘要与按天数日均的纯函数。
- **Details**：
  - 摘要行：`{范围标签} · {维度摘要}`；维度摘要 = 有标签时「{分类名} · {标签名}」、仅分类时分类名、都没有时「全部维度」；右侧「筛选」胶囊（`Icons.filter_alt_outlined` + 文案，48dp 触达，`ValueKey('stats-filter')`）。
  - 面板为独立 `StatefulWidget`（打开时以当前 query 初始化草稿），**不调用控制器**；标题「筛选」；范围区为「本周 / 本月 / 上月 / 近 30 天 / 自定义」chips，边界由 `resolveRange` 给出：本周 = 周一~今天、本月 = 1 日~今天、上月 = 上月整月、近 30 天 = 含今天共 30 天；点「自定义」调用 `showDateRangePicker`（`firstDate: 2000-01-01`、`lastDate: 今天`、`initialDateRange` 为草稿范围），取消保持草稿，确认后草稿范围与「自定义」chip 文案更新。
  - 分类区：「全部分类」+ 支出分类 + 收入分类 chips（支出在前）；选中分类时清空不兼容的草稿标签。
  - 标签区：草稿未选分类时只显示「选择分类后可筛选标签」；已选分类时显示「全部标签」+ 该分类的标签 chips。
  - 底部操作：「重置」把草稿恢复为「本月 + 全部分类 + 全部标签」；「应用」只执行 `Navigator.pop(context, StatsQuery(...))`；点遮罩/返回得到 `null`，不提交。
  - 页面侧：`final applied = await showModalBottomSheet<StatsQuery>(...)`；`applied != null` 时先 `ledger.setStatsQuery(applied)`，再按所选分类的 `type` 在需要时 `setState(() => _view = ...)`，摘要行随 `statsQuery` 更新。
  - 统计页 `RefreshIndicator` 同时刷新月度汇总与区间统计；错误分支改读 `rangeStatsError` 并重试 `loadRangeStats`；筛选面板与摘要行在 320dp + 2x 下不溢出。
  - 主要 `ValueKey`：`stats-range-<preset>`、`stats-category-<id>`、`stats-tag-<id>`、`stats-filter-reset`、`stats-filter-apply`。
- **Acceptance Criteria**：
  - 默认摘要为「本月 · 全部维度」，筛选胶囊可见且可打开面板。
  - 未点应用时：关闭面板、切换范围/分类/标签草稿都不改变页面数据、摘要与请求次数（面板不持有控制器）。
  - 点应用后：请求参数为草稿的范围与维度，摘要同步更新，面板关闭。
  - 应用收入类分类后视角切到收入，请求带该 `category_id`。
  - 「重置」只改草稿；未选分类时标签区为提示，选分类后只列该分类标签。
  - 自定义日期选择器可打开，取消后草稿不变。
  - 空数据时页面显示空态而不是错误；请求失败时显示错误与重试，不显示上一次的数字。

### TASK-011：统计内容改读区间结果

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-010
- **Description**：把 `app/lib/features/stats/stats_screen.dart` 的 Hero、指标卡、构成/趋势卡与渠道分布全部改为消费 `ledger.rangeStats` 与 `ledger.statsQuery`。
- **Details**：
  - Hero 标题「结余」，收入/支出取自区间结果；储蓄率徽标（`balance / income` 派生，收入为 0 时不显示）只在「全部分类 + 全部标签」时出现；有维度筛选时同一位置改显示「{expense_count + income_count} 笔」——单维度下储蓄率恒为 0 或 100%，没有解释力。
  - 四张指标卡：本期支出/收入（注脚「较上期 ±x%」，分母为 0 时无注脚）、日均（注脚「按 N 天」）、上期支出/收入、单笔均额（注脚「N 笔」）；沿用两行 `IntrinsicHeight` 等高布局与 `FittedBox`。
  - 构成环图中心文案改为「支出 / 收入」，空态文案改为「暂无分类支出 / 暂无分类收入」；渠道空态改为「暂无渠道支出 / 暂无渠道收入」；渠道分布标题与总额随视角。
  - 趋势卡继续使用 `monthly_trends`（区间端已按 6 个月返回）与「近 6 个月收支」标题；图例与「单位为元，按服务端自然月统计」说明保留。
  - 移除对 `ledger.stats`（月度汇总）的读取与 `formatMonth(now)` 的月份文案；页首改为 TASK-010 的「口径摘要 + 筛选」行。
  - 页面状态按 `rangeStats == null && rangeStatsLoading`（骨架）/ `rangeStats == null`（`ErrorState(ledger.rangeStatsError)` + 重试 `loadRangeStats`）/ 有值渲染；不再读 `statsError` 与 `loadStats`。
- **Acceptance Criteria**：
  - 页面所有数字与图表来自区间结果；切换视角与应用新筛选后同步更新。
  - 应用分类或标签筛选后 Hero 不出现「储蓄率」而出现「N 笔」，清除筛选后恢复。
  - 四卡等高；环图/渠道/趋势空态全覆盖；加载失败时只显示错误与重试。

### TASK-012：统计用例、夹具与冷启动断言

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-011
- **Description**：更新 `app/test/support/harness.dart` 的 `defaultApi` 增加 `/api/stats/range` 夹具 `rangeStatsJson(...)`；重写 `app/test/features/stats_test.dart`；同步 `app/test/features/stats_assets_test.dart` 的 `dailyAverage` 调用；调整 `app/test/app_cold_start_test.dart` 的骨架断言范围。
- **Details**：
  - 夹具字段与端点契约一致，提供 `expense/income/days/counts/previous_*` 与构成/渠道/趋势参数。
  - 新增 `app/test/features/stats_utils_test.dart`：`resolveRange` 覆盖周一为周首（周三、周日各一例）、本月 1 日~今天、上月整月、近 30 天含今天共 30 天（起点为 `now - 29 天`）。
  - 用例：首屏显示结余、四卡、构成与渠道；摘要为「本月 · 全部维度」且请求参数为当月 1 日与今天；打开面板点「上月」但在应用前关闭，页面与请求不变；再次打开点「上月」并应用，请求变为上月整月、摘要为「上月 · 全部维度」。
  - 分类/标签：应用「职业收入」后视角切到收入且请求带 `category_id=4`；应用「午餐」后请求带 `tag_id=1` 与 `category_id=1`，摘要为「本月 · 餐饮美食 · 午餐」；未选分类时标签区显示提示。
  - 「重置」+「应用」后回到默认 query；点「自定义」打开日期范围选择器后返回（`handlePopRoute`）不改变草稿。
  - 失败态：让 `/api/stats/range` 返回 500，页面显示错误与重试、不显示上一轮数字；点重试后恢复。
  - Hero：应用「餐饮美食」后不出现「储蓄率」、出现「N 笔」；清除筛选后恢复「储蓄率」。
  - 趋势切换、环图标签下钻、空数据空态、四卡等高、320dp + 2x（打开面板与应用后均无异常）。
  - 冷启动用例：把「首帧无骨架」断言限定在 `StreamScreen` 子树内；保留「无缓存首帧有骨架」与「刷新失败一个 SnackBar」。
- **Acceptance Criteria**：
  - `flutter test` 全量通过（记录项数，基线 122 项）。
  - 用例断言请求的 `start/end/category_id/tag_id`、「未应用不请求」、预设边界与失败态，而不是只看界面文案。

---

## Phase 5：门禁、文档、归档与提交

### TASK-013：门禁与项目文档同步

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-001 ~ TASK-012
- **Description**：执行全量门禁；更新 `.docs/Project.md` 的模块说明、统计接口契约、客户端交互与测试记录。
- **Details**：
  - 门禁按前置约定逐条执行并记录退出码与项数：`gofmt -l .`（无输出）、`go vet ./...`、`go test -count=1 ./...`、`dart format`、`flutter analyze`、`flutter test`、`cd web && npm run lint && npm test`。
  - Project.md：`stats.go` 说明补区间端点与过滤；`app/lib` 说明补统计筛选与记账层级；测试记录补本轮新增项数与日期；术语表按需补「统计区间 / 上期」。
  - 临时产物口径：本轮只新增 `Plan.md`、`Tasks.md` 与 `temp/ledger-ui-variant-b.html`（采纳 Demo，与既有 `temp/redesign-demo.html` 同口径提交）；`temp/ledger-ui-variant-a.html` 与两张用户截图保留为未跟踪的本地素材，不提交。
  - 工作区既有的 `temp/redesign-demo.html` 删除、`.pi/` 删除与技能文件改动不属于本轮，不恢复也不纳入提交。
- **Acceptance Criteria**：
  - 全部门禁（含 Web）退出码 0 并记录实际项数。
  - Project.md 与实际端点、交互、文件一致，无过期描述。
  - `git status` 中无本轮产生的失控临时文件，仅余明确保留的未跟踪素材与既有无关改动。

### TASK-014：归档与提交

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-013
- **Description**：将 Plan.md 与 Tasks.md 标记 DONE、补完成日期与门禁结论，移动到 `.docs/10-29-v1/`，按路径提交。
- **Details**：
  - 归档目录名固定 `10-29-v1`（`.docs/` 下无同日前缀目录）。
  - 提交信息使用中文 + 英文 Conventional Commits 前缀，聚焦「为什么」。
  - 提交按路径限定：业务代码与测试、`.docs/Project.md`、`.docs/10-29-v1/`、`temp/ledger-ui-variant-b.html`；不包含技能文件改动、`.pi/` 删除、`temp/redesign-demo.html` 删除、`temp/ledger-ui-variant-a.html` 与用户截图。
- **Acceptance Criteria**：
  - `.docs/10-29-v1/` 同时含 Plan.md 与 Tasks.md；根目录无残留。
  - `git show --name-only HEAD` 只含上面列出的路径。
  - 提交信息符合项目规范。

---

## 完成记录

- **完成日期**：2026-10-29
- **交付结果**：TASK-001 ~ TASK-014 全部完成。后端新增 `/api/stats/range` 与统一分类/标签过滤；客户端新增区间统计模型、查询代际与筛选剪枝；记账改为分类/标签双字段并复用共享选择面板；流水筛选改为底部选择面板；统计页改为区间结果与「口径摘要 + 草稿筛选」；相关测试、文档与归档同步完成。
- **回归结论**：`gofmt -l .` 无输出；`go vet ./...` 退出码 0；`go test -count=1 ./...` 全包通过（db 6 项、server 19 项）；`dart format --output=none --set-exit-if-changed lib test` 0 变更；`flutter analyze` No issues；`flutter test` 141 项通过；`cd web && npm run lint && npm test` 通过（38 项）。
- **变异校验**：临时移除 `statsFilter` 的 WHERE 拼装后 `TestStatsRangeFilters` 失败；恢复实现后通过。
- **归档**：`.docs/10-29-v1/Plan.md` 与 `.docs/10-29-v1/Tasks.md`。