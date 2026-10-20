# Tasks：修复 Android 客户端资产、统计、流水页与一级页顶栏布局缺陷

**关联 Plan**：`Plan.md` —— Android 客户端布局缺陷修复 v1.3  
**总计 Task**：8 个（TASK-001 至 TASK-008）  
**执行主体**：主线  
**状态**：DONE（2026-10-20 完成；`dart format` 无变更，`flutter analyze` 无问题，`flutter test` 92 项通过）

---

## 验证环境（本轮专用）

- 工作目录：`/home/dev/projects/Ledger`。
- Flutter 3.44.6 / Dart 3.12.2：`/home/dev/flutter/bin/flutter`、`/home/dev/flutter/bin/dart`；`flutter` 不在默认 PATH。
- 依赖缓存：`PUB_CACHE=/home/dev/projects/Ledger/.pub-cache`；首次运行如缺依赖，先执行 `cd app && /home/dev/flutter/bin/flutter pub get --offline`。
- 本机只做格式、静态分析与 Widget 测试；不构建 Android APK、不连接模拟器、不启动长期服务。
- 工作区已有与本轮无关的暂存技能文件、`AGENTS.md` 变更，以及未跟踪的 `temp/image1.png` 至 `temp/image4.png`。提交必须按路径限定，禁止 `git add -A`。
- 基线：本轮探索与复审时已跑通 `stats_test.dart`、`assets_test.dart`、`stream_screen_test.dart` 共 12 项；复审还实测 `dart format` 0 变更、`flutter analyze` 无问题。全量套件在 TASK-006 执行。
- 设计预览：`temp/uiux-fixes-demo.html` 默认展示修复后；支持修复前/后、构成/趋势、筛选菜单与明暗主题。`temp/uiux-fixes-demo.png` 是默认修复后预览。两者是实现与评审的视觉基准，不参与构建、不提交。

---

## Phase 1：资产与负债金额列右对齐

### TASK-001：修正资产与负债金额列到卡片右侧内边距

- **Status**：DONE
- **Executor**：主线
- **Priority**：P0
- **Depends**：无
- **Description**：让资产行与负债行的金额块填满弹性槽位并贴齐右侧，使所有金额和“余额/欠款”标签共享同一条右缘。
- **Details**：
  - 文件：`app/lib/features/assets/assets_screen.dart`。
  - `_AssetRow` 中金额列当前是 `Flexible` 的直接子项；在 `Flexible` 与 `Column` 之间加入 `Align(alignment: Alignment.centerRight)`。`Align` 会填满松散槽位，`Column` 仍按内容取宽并整体贴右。
  - 保留 `Flexible` 外层约束、`FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight)`、`CrossAxisAlignment.end`、`FontFeature.tabularFigures()`、负余额着色与金额隐藏逻辑。
  - `_LiabilityRow` 的金额列做同样处理；两处结构保持一致，不引入固定宽度或按行特判。
  - 测试文件：`app/test/features/assets_test.dart`。
  - 新增用例 `asset and liability amounts share the right edge`：
    - 使用 `statsJson()`，把 `asset_summary.liability_channels` 替换为单条欠款 `1234.56`，`total_liabilities` 设为 `9999.99`，避免与 Hero 的 `12,680.00` 文本重名。
    - 以 `Size(390, 1400)` 挂载 `AssetsScreen`，确保三张资产行与负债行都已构建；390 宽定义右缘关系，320×800 + 2x 只做溢出/异常门禁。
    - 通过 `find.ancestor(of: find.text('招商银行'), matching: find.byType(LedgerCard)).first` 取资产卡矩形，期望金额右缘为 `cardRect.right - 16`；对 `45,200.00`、`32,800.00`、`8,200.00` 逐一断言，误差 `0.5`。
    - 通过 `find.ancestor(of: find.text('花呗'), matching: find.byType(LedgerCard)).first` 取负债卡矩形，对 `1,234.56` 断言同样的右缘。
- **Acceptance Criteria**：
  - 新增用例通过，四条金额文本的右缘与各自卡片的 `right - 16` 一致。
  - 既有 `assets page hides and reveals amounts`、`manage button...`、`distribution bar...`、`assets fit 320dp with 2x text` 全部通过。
  - 未引入固定宽度、未改动金额格式化或状态逻辑。
  - `git diff --check` 无输出。

---

## Phase 2：统计页指标网格与图表卡布局

### TASK-002：将统计指标卡改为四卡等高

- **Status**：DONE
- **Executor**：主线
- **Priority**：P0
- **Depends**：无
- **Description**：把 2×2 指标网格从独立高度的 `Wrap` 改为两行等高布局，并让无备注卡保留同字号备注行，使四张卡统一高度。
- **Details**：
  - 文件：`app/lib/features/stats/stats_screen.dart`，`_Metrics`。
  - 删除 `LayoutBuilder` 与 `(constraints.maxWidth - 12) / 2` 的宽度计算，改为：
    ```dart
    Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _MetricCard(data: items[0])),
              const SizedBox(width: 12),
              Expanded(child: _MetricCard(data: items[1])),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _MetricCard(data: items[2])),
              const SizedBox(width: 12),
              Expanded(child: _MetricCard(data: items[3])),
            ],
          ),
        ),
      ],
    )
    ```
  - `_MetricCard` 增加同字号备注占位：备注存在时保持现有 `Text`；备注为空时仍渲染 `SizedBox(height: 4)` 与 `ExcludeSemantics(child: Text(' ', maxLines: 1, style: noteStyle))`，让四张卡拥有相同的备注行高。`noteStyle` 复用现有 `labelSmall`（含 `noteColor` 逻辑），不新增字号或固定高度。
  - 保留四项顺序：本周花费、当月花费、上月花费、日均花费；保留备注文案与颜色、`FittedBox` 与等宽数字。
  - 视觉基准：`temp/uiux-fixes-demo.html` 的统计页 `after` 状态；四张卡同高，无备注卡多一行留白。
  - 不使用固定卡片高度；接受无备注卡的一行留白，以换取整块 2×2 网格对称。
  - 测试文件：`app/test/features/stats_test.dart`。
  - 新增用例 `metric cards share height across all four`：
    - 使用默认 `defaultApi`（当月花费与日均花费有备注），挂载 `StatsScreen` 于 `Size(390, 1400)`；390 宽用于定义布局关系，320×800 + 2x 只做溢出/异常门禁。
    - 通过 `find.ancestor(of: find.text(label), matching: find.byType(LedgerCard))` 取四张卡矩形；断言 `本周花费.top == 当月花费.top`、`上月花费.top == 日均花费.top`，并断言四张卡 `height` 的最大值与最小值相差 `<= 0.5`。
    - 增加截图场景变体：`statsJson()['last_month_expense'] = 0`，此时当月花费无备注；再次断言四张卡高度互差 `<= 0.5`。
- **Acceptance Criteria**：
  - 新增用例两组成立；四张卡高度一致，不是仅同一行内一致。
  - `stats page shows hero, metrics and chart toggle` 与 `stats fit 320dp with 2x text` 通过。
  - 未改变指标数据来源、备注文案或颜色语义；占位备注行不进入语义树。

### TASK-003：移除统计图表卡的固定高度与内部滚动

- **Status**：DONE
- **Executor**：主线
- **Priority**：P0
- **Depends**：TASK-002（同一源码与测试文件，按顺序执行）
- **Description**：让图表卡按当前模式内容取高；构成图全部图例直接展开，趋势图不再继承构成图的固定 400 高度。
- **Details**：
  - 文件：`app/lib/features/stats/stats_screen.dart`。
  - `_buildChartCard`：删除包裹图表面板的 `SizedBox(height: 400)`，把 `_CompositionPanel` / `_TrendPanel` 直接放入卡片 `Column`；保留标题、`SegmentedButton`、12px 间距与卡片内边距。
  - `_CompositionPanel`：删除外层 `SingleChildScrollView`，直接返回 `Column(crossAxisAlignment: CrossAxisAlignment.stretch)`；保留 160 环形图、图例行、选中分类的细分标签详情与 `EmptyState`。
  - `_TrendPanel`：删除外层 `SingleChildScrollView`，直接返回 `Column(crossAxisAlignment: CrossAxisAlignment.stretch)`；保留 190 高度趋势图、图例与单位说明。
  - 不新增最大高度、Top N 截断或“展开更多”交互；页面统一滚动。
  - 视觉基准：demo 统计页 `after` 的“支出构成”（全部五条图例）与“趋势”（卡片收缩、无空白）；`before` 展示固定 400 高度与内部滚动，作为反例。
  - 测试文件：`app/test/features/stats_test.dart`。
  - 新增用例 `chart card sizes to content without inner scrolling`：
    - 构造 5 条 `category_distribution`：功能性支出 77.63、零食消费 37.73、虚拟商品 30.33、生活缴费 20.33、购物消费 4.33；`month_expense` 设为 171.00，其余字段沿用 `statsJson()`。
    - 以 `Size(390, 1400)` 挂载；通过 `find.ancestor(of: find.text('支出构成'), matching: find.byType(LedgerCard))` 取构成卡。390 宽定义布局；320×800 + 2x 只做溢出/异常门禁。
    - 断言卡片内 `find.byType(SingleChildScrollView)` 数量为 0；断言五个分类名（功能性支出、零食消费、虚拟商品、生活缴费、购物消费）各出现一次，图例行数与分类数一致。
    - 点击 `趋势`，`pumpAndSettle`；通过 `近 6 个月收支` 取趋势卡；断言卡片内无 `SingleChildScrollView`，且趋势卡高度小于构成卡高度。
    - 新增或扩展 320×800 + 2x 用例：滚动到 `趋势` 分段并点击，`tester.takeException()` 为 null。
  - 若 `stats page handles empty data` 因内容高度变化在固定 `drag(0, -1000)` 后找不到支付途径，改用 `ensureVisible` 或增大滚动距离；不得恢复固定高度。
- **Acceptance Criteria**：
  - 新增用例通过；构成卡五条分类图例均构建，趋势卡无固定高度残留。
  - 图表卡内部无 `SingleChildScrollView`；切换模式无 RenderFlex 异常。
  - 既有空态、标签下钻与 `320dp + 2x` 用例通过。
  - 图表绘制、颜色映射、图例点选逻辑未改变。

---

## Phase 3：流水页月份与筛选收纳

### TASK-004：合并月份与筛选为列表头并移除整行胶囊

- **Status**：DONE
- **Executor**：主线
- **Priority**：P0
- **Depends**：无
- **Description**：取消月份说明与筛选胶囊各占一行的布局，将两者合并为 Hero 下方的列表头；筛选改为紧凑菜单，当前筛选在触发器中可见。
- **Details**：
  - 文件：`app/lib/features/stream/stream_screen.dart`。
  - 删除 `SliverChildListDelegate` 中 Hero 上方的月份 `Text` 与 `SizedBox(height: 12)`；Hero 之后加入 `SizedBox(height: 16)`、新的 `_ListHeader`、`SizedBox(height: 12)`，再进入骨架/错误/空态/日分组。
  - `_ListHeader` 为 `Row(crossAxisAlignment: center)`：左侧 `Expanded` 包 `Text(formatMonth(now))`，`maxLines: 1`、`overflow: TextOverflow.ellipsis`、`bodyMedium` + `onSurfaceVariant`；右侧为 `_FilterMenu`。
  - `_FilterMenu` 使用 `PopupMenuButton<TransactionFilter>`：
    - `key: ValueKey('filter-menu')`，`tooltip: '筛选'`，`initialValue: selected`，`onSelected: onSelected`。
    - 触发器外层 `ConstrainedBox(minHeight: 48)` 保证 48dp 触达；内部为 `Container`（`surfaceContainerHigh`、`StadiumBorder`、水平 10–12、垂直 6、最小高度 36），内容为 `Icons.filter_alt_outlined`（18）、当前 `selected.label`、`Icons.expand_more_rounded`（18）。文字使用 `labelLarge`，颜色 `onSurface`；图标 `onSurfaceVariant`。
    - 菜单项遍历 `TransactionFilter.values`，每项 `key: ValueKey('filter-${filter.name}')`；行内左侧 24 宽占位，选中项显示 `Icons.check_rounded`（18），随后 8 间距和 `filter.label`。
  - 删除 `_FilterBar` 与 `_FilterPill` 两个类，移除横向滚动筛选行。
  - 视觉基准：demo 流水页 `after` 的列表头与菜单展开态；`before` 保留月份上方、五枚胶囊整行的旧布局作为反例。
  - 测试文件：`app/test/features/stream_screen_test.dart`。
  - 更新 `filter tap requests the matching type`：先 `tap(find.byKey(const ValueKey('filter-menu')))`，`pumpAndSettle`，再 `tap(find.byKey(const ValueKey('filter-expense')))`，`pumpAndSettle`；保持原有请求断言。
  - 更新 `stream shows headline, day group and filters`：保留 Hero、金额与日分组断言；`全部` 仍由触发器文本断言；原直接依赖页面可见的 `转账` 改为先打开 `filter-menu`，再按 `filter-*` key 断言五项齐全。该用例不依赖旧胶囊常驻。
  - 新增用例 `filter menu exposes options and keeps the current label visible`：
    - 初始触发器内可见“全部”；`tester.getSize(find.byKey(const ValueKey('filter-menu'))).height >= 48`。
    - 打开菜单后五个 `filter-*` key 均存在；点击“支出”后，触发器内 `find.descendant(of: find.byKey('filter-menu'), matching: find.text('支出'))` 为 1。
    - Hero 矩形通过 `find.ancestor(of: find.text('本月结余'), matching: find.byType(Container)).first` 取得；首个日分组通过 `find.ancestor(of: find.text('午餐 · 牛肉面'), matching: find.byType(LedgerCard)).first` 取得。断言 `formatMonth(DateTime.now())` 的顶边位于 Hero 底部与首个日分组顶部之间。
  - 扩展 `stream fits 320dp with 2x text`：`ensureVisible(filter-menu)` 后打开菜单，`pumpAndSettle`，`tester.takeException()` 为 null。
- **Acceptance Criteria**：
  - 筛选菜单五项可选，选择“支出”发出的请求包含 `type=expense`。
  - 触发器显示当前筛选；48dp 触达；320dp + 2x 打开菜单无溢出或异常。
  - 月份说明位于 Hero 下方、列表上方；旧的整行胶囊组件已移除。
  - 空态“本月还没有记账”、删除确认、刷新与 `stream shows headline, day group and filters` 均通过。

---

## Phase 4：紧凑顶栏、回归验证、文档、归档与提交

### TASK-005：四个一级页统一紧凑顶栏

- **Status**：DONE
- **Executor**：主线
- **Priority**：P0
- **Depends**：TASK-001、TASK-002、TASK-003、TASK-004
- **Description**：把四个一级页的 `SliverAppBar.large` 替换为共享的 64 高、非 pinned 紧凑顶栏，让标题上移到顶栏中心，并随内容滑动被推上去；设置页同步，内容不改。
- **Details**：
  - 文件：`app/lib/core/widgets/ledger_widgets.dart`（新增共享组件）、`app/lib/features/stream/stream_screen.dart`、`app/lib/features/stats/stats_screen.dart`、`app/lib/features/assets/assets_screen.dart`、`app/lib/features/settings/settings_screen.dart`。
  - 在 `ledger_widgets.dart` 新增：
    ```dart
    class LedgerSliverAppBar extends StatelessWidget {
      const LedgerSliverAppBar({super.key, required this.title});

      final String title;

      @override
      Widget build(BuildContext context) {
        final theme = Theme.of(context);
        return SliverAppBar(
          pinned: false,
          toolbarHeight: 64,
          titleSpacing: 20,
          automaticallyImplyLeading: false,
          title: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(title),
          ),
          titleTextStyle: theme.textTheme.headlineMedium?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.2,
          ),
        );
      }
    }
    ```
  - 四个页面把 `const SliverAppBar.large(title: Text('...'))` 替换为 `const LedgerSliverAppBar(title: '...')`；保留既有的背景、前景、零 elevation 与状态栏处理，不新增 actions/leading。
  - 视觉基准：Demo 手机框内的 64 高紧凑顶栏（不是 demo 页面的品牌头）；标题 28/34、左边距 20，与顶部状态栏分离；在手机框内滚动内容时顶栏随之上移。不保留 `expandedHeight` 或大标题区。标题用 `FittedBox(scaleDown)` 兜住 2x 字体，不改变 1x 字号。
  - 测试文件：新建 `app/test/core/widgets/ledger_app_bar_test.dart`；在 `app/test/features/assets_test.dart`、`stats_test.dart`、`stream_screen_test.dart`、`settings_test.dart` 各加一条屏内使用断言。
  - 新增用例 `compact top bar scrolls away and is 64 high`：
    - 用 `MaterialApp(theme: AppTheme.light(), home: Scaffold(body: CustomScrollView(slivers: [const LedgerSliverAppBar(title: '测试'), const SliverToBoxAdapter(child: SizedBox(height: 900))])))` 挂载。
    - `tester.widget<SliverAppBar>(find.byType(SliverAppBar))`：断言 `toolbarHeight == 64`、`pinned == false`、`floating == false`、`expandedHeight == null`、`titleSpacing == 20`、`titleTextStyle?.fontSize == 28`、`fontWeight == FontWeight.w500`；标题 `测试` 的顶部小于 40。
    - `await tester.drag(find.byType(CustomScrollView), const Offset(0, -160)); await tester.pumpAndSettle();` 再断言标题顶部小于 0，或已不在树中，证明顶栏随滚动被推上去。
    - 四个屏测试通过 `find.byType(LedgerSliverAppBar)` 断言各一；`settings_test` 同样覆盖。
- **Acceptance Criteria**：
  - 四个一级页均使用 `LedgerSliverAppBar`，无 `SliverAppBar.large` 残留；顶栏 64 高、非 pinned、标题 28/34 居中；滚动后标题离开视口。
  - 新增组件测试与四个屏使用断言通过；320dp + 2x 无标题溢出或 RenderFlex 异常。
  - 未改动设置页内容、四个页面的滚动内容与业务逻辑。

### TASK-006：执行格式检查、静态分析与全量 Flutter 测试

- **Status**：DONE
- **Executor**：主线
- **Priority**：P0
- **Depends**：TASK-001、TASK-002、TASK-003、TASK-004、TASK-005
- **Description**：在提交前执行本轮全部质量门禁，修复由布局高度变化引起的测试回归。
- **Details**：
  - 命令：
    ```bash
    export PUB_CACHE=/home/dev/projects/Ledger/.pub-cache
    cd /home/dev/projects/Ledger/app
    /home/dev/flutter/bin/dart format --output=none --set-exit-if-changed lib test
    /home/dev/flutter/bin/flutter analyze
    /home/dev/flutter/bin/flutter test
    ```
  - 执行前先确认 `/home/dev/flutter/bin/flutter --version` 可运行；若 SDK 缓存不可写或工具链异常，停止并报告，不得把未执行写成通过。本轮复审已实测 `flutter analyze` 退出 0，三份基线测试 12 项通过；交付环境若不同，重新验证。
  - 命令逐条读取 `$?`；不要把输出接到 `| tail`/`| head` 后用管道末端退出码判断。需要保留日志时用 `> /tmp/ledger-analyze.log 2>&1`，或启用 `set -o pipefail` 并检查 `PIPESTATUS[0]`。
  - 全量测试会覆盖 API、控制器、纯函数、Widget、320dp + 2x、空态、删除确认与刷新；记录实际通过数量。
  - 若空态用例因图表高度变化失效，只调整滚动方式（`ensureVisible` 或加大拖动距离），不恢复固定高度。
  - 若 `flutter analyze` 报告新增告警，回到对应 Task 修正；不扩大修改范围。
  - 额外执行 `git diff --check`，确认无空白错误。
- **Acceptance Criteria**：
  - 格式检查退出码 0，无文件被格式化。
  - `flutter analyze` 输出 `No issues found`。
  - `flutter test` 全部通过，记录总用例数与本轮新增用例名。
  - 三条质量命令的退出码逐条记录，未使用管道末端的退出码冒充检查结果。
  - `git diff --check` 无输出。

### TASK-007：同步 Project.md 并清理本轮临时文件

- **Status**：DONE
- **Executor**：主线
- **Priority**：P1
- **Depends**：TASK-006
- **Description**：把五项布局与顶栏修正、测试结论与范围边界写入 Project.md，并清理本轮产生的临时文件。
- **Details**：
  - 文件：`.docs/Project.md`。
  - 在“约束与决策”追加 2026-10-20 条目：资产/负债金额列在松散弹性槽位内右对齐；统计四张指标卡统一等高（无备注卡保留同字号备注行）；图表卡内容驱动并移除内部滚动；流水页月份与筛选合并为列表头，筛选改紧凑菜单；四个一级页统一使用 64 高、非 pinned 的 `LedgerSliverAppBar`；全量测试通过，320dp + 2x 覆盖。
  - 更新“Android 客户端”结构描述：
    - `core/widgets/`：共享 `LedgerSliverAppBar`，四个一级页共用。
    - `features/stream/`：流水页、月份/筛选合并列表头、日分组纯函数。
    - `features/stats/`：统计页、等高指标网格、内容自适应图表卡、自绘环图/趋势图与派生。
    - `features/assets/`：资产页、右对齐金额列与资产派生。
    - `features/settings/`：设置页；顶栏同步为紧凑样式，内容不变。
  - 在“测试”段补充本轮新增覆盖：金额列右缘、指标卡四卡等高、图表卡无内部滚动、筛选菜单交互、四个一级页顶栏 64/非 pinned/滚动滚出。
  - 检查 `lib/features/**` 不再出现 `SliverAppBar.large`；顶栏标题统一由 `LedgerSliverAppBar` 提供。
  - 清理：删除 `temp/crops/`、`app/test/_probe_test.dart`（探索阶段已删除则确认不存在）、`temp/debug-*.html`、`temp/debug-demo.html`、`temp/debug-before.html` 与中间状态截图 `temp/demo-*.png`；保留设计预览 `temp/uiux-fixes-demo.html`、`temp/uiux-fixes-demo.png` 与用户提供的 `temp/image1.png` 至 `temp/image4.png`，均不纳入提交。
  - 检查 `git status --short`：确认没有新增临时文件；既有技能文件/AGENTS.md 的暂存状态保持原样。
- **Acceptance Criteria**：
  - Project.md 的五项描述与代码实际状态一致，不残留“固定 400 高度”“整行筛选胶囊”“SliverAppBar.large”等过期表述。
  - 本轮临时文件不存在；用户截图未提交。
  - `git diff --check` 无输出。

### TASK-008：标记完成、归档并按路径提交

- **Status**：DONE
- **Executor**：主线
- **Priority**：P0
- **Depends**：TASK-007
- **Description**：在 Plan/Tasks 标注完成与测试结论，移入当日归档目录，按路径拆分代码与文档提交。
- **Details**：
  - 将 `Plan.md` 与 `Tasks.md` 状态改为 `DONE`，补充完成日期、全量测试数量、五项修复的验收结论。
  - 归档：
    ```bash
    mkdir -p .docs/10-20-v1
    mv Plan.md Tasks.md .docs/10-20-v1/
    ```
    若 `.docs/10-20-v1` 已存在，按 `10-20-v2` 递增，不覆盖既有目录。
  - 代码提交（五份源码与五份测试）：
    ```bash
    set -e
    git add app/lib/core/widgets/ledger_widgets.dart \
      app/lib/features/assets/assets_screen.dart \
      app/lib/features/stats/stats_screen.dart \
      app/lib/features/stream/stream_screen.dart \
      app/lib/features/settings/settings_screen.dart \
      app/test/core/widgets/ledger_app_bar_test.dart \
      app/test/features/assets_test.dart \
      app/test/features/stats_test.dart \
      app/test/features/stream_screen_test.dart \
      app/test/features/settings_test.dart
    git diff --cached --name-only -- app/lib app/test
    git commit -m "fix(app): 修复布局缺陷并统一紧凑顶栏" \
      -m "金额列右对齐；统计指标卡四卡等高；图表卡内容驱动；流水筛选收纳；四个一级页统一 64 高非 pinned 顶栏。新增对应 Widget 布局断言。" \
      -- app/lib/core/widgets/ledger_widgets.dart \
         app/lib/features/assets/assets_screen.dart \
         app/lib/features/stats/stats_screen.dart \
         app/lib/features/stream/stream_screen.dart \
         app/lib/features/settings/settings_screen.dart \
         app/test/core/widgets/ledger_app_bar_test.dart \
         app/test/features/assets_test.dart \
         app/test/features/stats_test.dart \
         app/test/features/stream_screen_test.dart \
         app/test/features/settings_test.dart
    git reset -- app/lib/core/widgets/ledger_widgets.dart \
      app/lib/features/assets/assets_screen.dart \
      app/lib/features/stats/stats_screen.dart \
      app/lib/features/stream/stream_screen.dart \
      app/lib/features/settings/settings_screen.dart \
      app/test/core/widgets/ledger_app_bar_test.dart \
      app/test/features/assets_test.dart \
      app/test/features/stats_test.dart \
      app/test/features/stream_screen_test.dart \
      app/test/features/settings_test.dart
    test -z "$(git diff --cached --name-only -- app/lib app/test)"
    ```
    关键点是 `-m` 放在 `--` 之前：`git commit -- <paths> -m ...` 会把 `-m` 当成路径。提交后按十条路径 `git reset`，让代码/测试路径在索引中与 HEAD 对齐；不影响工作区既有暂存文件。
  - 文档提交（Project.md 与归档）：
    ```bash
    set -e
    git add .docs/Project.md .docs/10-20-v1/Plan.md .docs/10-20-v1/Tasks.md
    git diff --cached --name-only -- .docs
    git commit -m "docs(app): 记录客户端 UI/UX 布局修复" \
      -- .docs/Project.md .docs/10-20-v1/Plan.md .docs/10-20-v1/Tasks.md
    ```
  - 不推送；若用户明确要求推送，再执行，并说明会触发 Android/Docker CI。
  - 使用 `git show --stat HEAD`、`git show --stat HEAD~1`、`git status --short` 核对提交范围；既有暂存技能文件、`AGENTS.md` 与 `temp/redesign-demo.html` 的既有暂存删除不得进入这两笔提交。
- **Acceptance Criteria**：
  - 根目录无 `Plan.md`/`Tasks.md`；`.docs/10-20-v1/` 同时包含两者并标注 DONE。
  - 两笔提交只包含预期源码、测试与文档路径；`git show --stat` 可核对。
  - 代码提交后 `git diff --cached --name-only -- app/lib app/test` 为空；文档提交只含 `.docs/` 预期路径。
  - 工作区既有暂存文件、`AGENTS.md`、`temp/redesign-demo.html` 的既有暂存删除与 `temp/image*.png` 未被提交。
  - 无 `--no-verify`、无 amend、无强制推送。
