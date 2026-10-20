# Tasks：客户端 Review 复审吸收与残留收敛（Quick）

**关联 Plan**：无（Quick 模式跳过 Plan，故本归档仅含 Tasks.md）  
**状态**：DONE（2026-10-20 完成；`dart format` 0 变更，`flutter analyze` No issues found，`flutter test` 93 项通过）  
**日期**：2026-10-20  
**总计 Task**：5 个  
**执行主体**：主线

## 背景

上一轮归档 `10-20-v1`（`89eca4d`、`583350b`）的 Review 报告给出 89 分，提出三类问题：流水行与图例存在未进入任务的满宽包装、顶栏记录"28/34"与实现不一致、顶栏与图表卡测试只锁定配置。逐条核实结果：

- **流水行/图例包装**：初判为"惰性防御"并尝试还原，实测 320dp + 2x 下两处 `Row` 分别溢出 33px 与 46px，图例百分比在 52 宽固定列内折行到 240 高。包装是 2x 门禁所需的约束，不是空转代码；结论改为保留并补记。唯一无需求依据的是 `Expanded(flex: 2)` 的 2:1 分配，删除。
- **28/34**：`headlineMedium` 是 M3 2021 的 28/36（1.29 行高），28/34 来自 demo 的 34px 行高。以设计系统 token 为准修正记录，不改代码迁就 mock。
- **测试只锁配置**：`tester.getSize(find.byType(SliverAppBar))` 实测抛出 `_RenderSliverScrollingPersistentHeaderForWidgets is not a subtype of RenderBox`，报告建议的断言写法不可行；改断言 `AppBar` 矩形、标题矩形与首个内容 dy。
- **驳回**：标题 `FittedBox` 改单行省略（2x 下实测封顶 48 高、约 1.33 倍，省略号只会截断两字标题）；`PopupMenuButton.initialValue` 视为与勾选图标重复（其同时决定菜单弹出位置）；为 2x 金额补"可读性"阈值断言（本机测试字体为等宽 Ahem，2x 下每字 1em，阈值只会把合成字体的最坏值写死）。
- **不改动**：工作区既有的 `.agents/`、`.dsh/`、`.pi/`、`AGENTS.md` 暂存状态与 `temp/` 未跟踪文件；提交仍按路径限定。

范围限定为 1 个源码文件、2 个测试文件与 `.docs/Project.md`。

## TASK-001：删除流水行的 2:1 弹性分配

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / 无
- **Description**：删除 `_TransactionRow` 中 `Expanded` 的 `flex: 2`，金额列与描述列回归 1:1 分配。
- **Details**：`app/lib/features/stream/stream_screen.dart` 仅删一行。`Flexible` + `Align` + `FittedBox` 保留：2x 下删掉它整行溢出 33px（实测），1x 下金额右缘不变（`Expanded` 之后的自然宽子项起点固定，右缘由"`SizedBox(8)` + 固定宽菜单按钮"锁定）。1:1 分配使 2x 下金额可用宽度由 1/3 回到 1/2。
- **Acceptance Criteria**：1x 下金额右缘与改动前一致；320dp + 2x 无溢出；描述列仍省略号截断。

## TASK-002：顶栏测试改为渲染几何断言

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / 无
- **Description**：重写 `ledger_app_bar_test.dart`，用渲染结果替代 `toolbarHeight`/`titleSpacing`/`expandedHeight` 等配置断言，并新增 2x 用例。
- **Details**：断言 `AppBar` 矩形 `top == 0`、`height == 64`；标题 `left == 20`、`center.dy` 与顶栏中心差 < 0.5；`DefaultTextStyle` 实际字号 28；首个内容（带 key 的 `SizedBox`）顶边 `dy == 64`；拖动 160 后标题离场且内容顶边上移。2x 用例断言标题矩形落在 `[0, 64]` 内且高度 > 1x 的 36（实测 48），锁住"缩放但不回退到 1x"。
- **Acceptance Criteria**：两用例通过；改成 pinned、加 `expandedHeight`、去掉 `titleSpacing` 均会被断言捕获。

## TASK-003：图表卡滚动断言限定到卡片子树

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P1 / 无
- **Description**：`stats_test.dart` 两处 `find.byType(SingleChildScrollView), findsNothing` 改为 `find.descendant(of: 图表卡, ...)`。
- **Details**：构成卡与趋势卡各自限定到 `LedgerCard` 子树；页面级滚动容器与将来无关的滚动容器不再触发误报。
- **Acceptance Criteria**：两处断言通过；失败条件收窄为"图表卡内部出现独立滚动容器"。

## TASK-004：校正 Project.md 并补记复审结论

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P1 / TASK-001
- **Description**：修正 2026-10-20 条目中的行高与包装描述，新增复审吸收条目，同步测试数量。
- **Details**：行高改为 M3 `headlineMedium` 28/36；"列表行金额……保持右对齐"改为 2x 收缩表述；测试段由 92 改为 93 并注明顶栏 2x 用例；新增条目记录保留/删除/驳回的判定与实测证据。
- **Acceptance Criteria**：Project.md 与代码一致；不残留"28/34"及"保持右对齐"这类失真表述。

## TASK-005：门禁、归档与按路径提交

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-001、TASK-002、TASK-003、TASK-004
- **Description**：执行格式、静态分析与全量测试，标记 DONE，归档 `.docs/10-20-v2/`，按路径提交。
- **Details**：门禁以 `FLUTTER_ALREADY_LOCKED=true` 直接调用 `flutter_tools.snapshot`（`/home/dev/flutter` 只读）；提交分两笔（源码/测试、Project.md 与归档），`-m` 置于 `--` 之前，提交后按路径复盘 `git show --stat` 并 `git reset` 收口。
- **Acceptance Criteria**：格式 0 变更、分析无问题、全量通过并记录数量；`.docs/10-20-v2/` 含 Tasks.md；提交不含工作区既有暂存与 `temp/` 文件。

## 回归结论

- `dart format --output=none --set-exit-if-changed lib test`：0 变更（exit 0）。
- `flutter analyze`：`No issues found!`（exit 0）。
- `flutter test`：93 项通过（上一轮 92 项 + 顶栏 2x 用例）。
- 实测证据：320dp + 2x 下流水行溢出 33px、图例 `Row` 溢出 46px、`100.0%` 在 52 宽列内折行到 240 高（均为还原包装后的测量值）。
