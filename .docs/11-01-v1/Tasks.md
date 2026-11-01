# Tasks：Android 订阅页 UI/UX 修缮

**关联 Plan**：Plan.md —— Android 订阅页 UI/UX 修缮 v1.0
**状态**：DONE（2026-11-01 完成；回归：dart format 0 变更、flutter analyze No issues、flutter test 193 项通过、flutter build web 成功）
**日期**：2026-11-01
**总计 Task**：13 个
**执行主体**：主线

---

## 前置约定

- 设计基线为 Material 3：复用 app/lib/core/widgets 下的 LedgerCard、EmptyState、ErrorState、SkeletonList、ConfirmDialog、LedgerSliverAppBar；颜色只取 ColorScheme / FinanceColors 角色，不新增硬编码色值、圆角或阴影。
- 本轮只改 Android 客户端订阅页、订阅表单、Shell 的订阅 Tab FAB 条件与共享 ConfirmDialog 的危险色；不改后端、Web、数据库、API 契约、依赖版本与 Flutter SDK。
- 订阅业务口径不变：暂停项不计入 Hero、组小计、未来 7 天；金额只读 amount_cents；续费日短月夹取；订阅不写流水与统计。
- 已有测试基线为 177 项（2026-10-31）。执行前先跑一次格式/分析/测试，记录实际基线，不把既有失败算入本轮。
- 浏览器复核已完成并清理；如需复现：临时后端 8081 + Flutter debug web 5175 + 5 组/9 条订阅（见 Plan 第 1 节）。复核截图不提交仓库。
- 工作区已有暂存的技能/规则文件、.pi 删除、temp 未跟踪截图与 HTML；执行时以实时 git status 为准，不 reset、不恢复、不纳入本轮提交；提交使用 git commit --only -- 白名单路径。
- 根目录 Plan.md / Tasks.md 在交付完成后按 Archive 流程移入按执行日计算的 .docs/MM-DD-vN/。

---

## Phase 1：派生语义与文案

### TASK-001：组头计数/小计与筛选计数收口

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / 无
- **Description**：修正订阅页在任何筛选下组头计数与小计同可见行不一致的问题；删除筛选行下方与语义不符的独立计数。
- **Details**：
  - 在 subscriptions_screen.dart 的 _SectionCard 中计算 pausedCount = section.totalCount - section.activeCount。
  - 组头计数按筛选切换：全部视图 totalCount > 0 时显示“共 N 项”，totalCount == 0 时不渲染该行；使用中显示“N 项使用中”；已暂停显示“N 项已暂停”。
  - 组头小计统一规则：showDash = filter == paused || section.activeCount == 0；showDash 时显示“—”，颜色 scheme.onSurfaceVariant；否则显示“月合计 / 月”，金额只取 active 的 section.monthlyCents。
  - 空分组（totalCount == 0）不显示 0.00 与“0 项使用中”，由空行“暂无订阅 / 添加”承担说明。
  - _FilterBar 删除 totalCount、pausedCount 参数与第二行计数 Text；Screen 中删除只为该计数服务的 pausedCount 变量；筛选胶囊保留 key subscriptions-filter-all/active/paused。
  - 不改变 buildSubscriptionSections 的 active 口径与排序；不改 SubscriptionSection 字段，pausedCount 由 totalCount - activeCount 派生。
- **Acceptance Criteria**：
  - 全部视图“影音娱乐”组头显示“共 3 项”，其下列 3 行；使用中视图显示“2 项使用中”与“87.00 / 月”；已暂停视图显示“1 项已暂停”与“—”。
  - 空分组不再出现“0.00 / 月”或“0 项使用中”。
  - 页面不再出现“共 9 项”这类与 active 筛选不符的计数；筛选胶囊仍三个且可切换。
  - 更新 subscriptions_test.dart 对应断言；全量测试无回归。

### TASK-002：续费元信息与暂停文案

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-001
- **Description**：把行元信息收敛为单一纯函数，避免日期在“11 / 月15日”处断行，并把暂停徽标从名称区移入元信息。
- **Details**：
  - 在 subscriptions_utils.dart 新增 formatRenewalMeta(Subscription sub, DateTime now)：使用中返回“每月 N 日 · 下次 M月D日”；已暂停返回“已暂停 · 原扣款日 N 日”。
  - 新增内部日期格式化：基于现有 formatMonthDay，在数字与“月/日”之间插入 word joiner（U+2060），使“11月15日”不会在数字与单位之间断行，只允许在“·”处换行；可见文案与现有中文格式一致。
  - _SubscriptionRow 改用该函数；删除名称后的暂停胶囊 Wrap，名称改为 Text(maxLines: 2, overflow: ellipsis)；暂停状态只由元信息、头像/金额弱化与行底色表达。
  - 元信息 Text 使用 maxLines: 2, overflow: ellipsis，避免 2x 下无限增高；不在日期内部截断。
  - 不修改全局 formatMonthDay / formatDayLabel，避免影响流水、统计与既有测试字符串。
- **Acceptance Criteria**：
  - 使用中行元信息为“每月 15 日 · 下次 11月15日”（含不可断行分隔），320dp 下不会出现“下 / 次”或“11 / 月15日”。
  - 暂停行元信息为“已暂停 · 原扣款日 30 日”，名称区不再出现悬浮胶囊。
  - subscriptions_utils_test.dart 覆盖使用中/暂停/短月/跨年；subscriptions_test.dart 覆盖名称两行上限与元信息文本。
  - dart format / flutter analyze 无问题。

---

## Phase 2：页面结构与 Hero

### TASK-003：Hero 分布条与金额字阶

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-001
- **Description**：修复 Hero 底部分布条不可见，并为读屏补充构成描述；让主金额在 2x 下只收缩数字，不把货币与单位一起缩小。
- **Details**：
  - subscriptions_screen.dart 的 _SummaryHero 中，分布条 Row 增加 crossAxisAlignment: CrossAxisAlignment.stretch，使每个 Expanded 内的 ColoredBox 获得 7px 紧高度。
  - 分布条外层加 key subscriptions-distribution-bar 与 Semantics(label: '按分组划分的每月固定开支', child: ExcludeSemantics(...))；不新增图例。
  - 主金额 Row 拆为：固定 ¥（headlineSmall）、Flexible(FittedBox(scaleDown, Text(金额, displaySmall)))、固定“/ 月”（bodyMedium）；不再对整个 Row 套 FittedBox。
  - 保持 radius 28、padding 20、eyebrow + 使用中胶囊 + 年度预估/未来 7 天两列不变。
- **Acceptance Criteria**：
  - 390dp 浅色/深色下 Hero 底部出现 7px 多色分布条，无异常、无空白占位。
  - tester.getSize(find.byKey(ValueKey('subscriptions-distribution-bar'))).height == 7；Semantics 标签可被 find.bySemanticsLabel 找到。
  - 320dp + 2x 下 Hero 金额仍大于 bodyLarge，不出现整行缩到正文以下；无 RenderFlex 溢出。
  - Hero 其它数值（505.00 / 6,060.00 / 187.00 2 项）与暂停口径不变。

### TASK-004：页面操作、筛选与空态层级

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-001, TASK-003
- **Description**：把页面操作从 Hero 之上移到 Hero 之后，删除筛选计数行，去掉筛选胶囊的勾选位移，并把空/筛选空态收进卡片、消除重复 CTA。
- **Details**：
  - 加载成功且非空时，内容顺序固定为 _SummaryHero → SizedBox(16) → _ActionRow → SizedBox(16) → _FilterBar → SizedBox(12) → 分区。
  - _ActionRow 中“新建分组”改为 TextButton.icon（保留 key subscriptions-add-group），“添加订阅”保留 FilledButton.icon（key subscriptions-add）；右对齐 Wrap，320dp + 2x 可换行。
  - _FilterBar 只保留 ChoiceChip Wrap；ChoiceChip 增加 showCheckmark: false；spacing/runSpacing 8；不恢复独立计数行。
  - isEmpty 分支：渲染 _ActionRow + SizedBox(16) + LedgerCard(child: EmptyState(title: '还没有订阅', icon: autorenew, 不传 actionLabel/onAction))；不再同时出现“添加第一个订阅”。
  - 筛选无结果分支：LedgerCard(child: EmptyState(title: 暂无使用中/已暂停的订阅, actionLabel: '查看全部', onAction: 切回 all))。
  - firstLoading 继续 SkeletonList(rows: 5)；firstFailed 改为 SizedBox(height: 320, child: ErrorState(...))，避免错误面板贴顶。
  - 不改变 RefreshIndicator、AlwaysScrollableScrollPhysics 与空态下拉刷新。
- **Acceptance Criteria**：
  - 首屏纵向顺序为 Hero → 操作 → 筛选 → 分区；Hero 顶部不再被两个大按钮顶下去。
  - 切换“全部/使用中/已暂停”时三个胶囊不因勾选图标发生水平位移；页面无“共 N 项”注脚。
  - 空数据只有一个主 CTA（操作行的“添加订阅”）；EmptyState 的祖先是 LedgerCard；筛选空态仍提供“查看全部”。
  - 320dp + 2x 无溢出；加载/失败态不出现重复操作入口。

### TASK-005：订阅 Tab 隐藏 FAB 与底部留白

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P1 / TASK-004
- **Description**：订阅页不再显示与业务无关且遮挡右侧菜单的全局“记一笔”FAB，并收紧底部留白。
- **Details**：
  - app_shell.dart 增加 static const subscriptionsIndex = 2；floatingActionButton 在 _index == subscriptionsIndex 时返回 null，其余四页保持 FloatingActionButton.extended“记一笔”。
  - subscriptions_screen.dart 的 SliverPadding 底部由 100 改为 32；仍保证最后一张卡与底部导航有间距。
  - 不改变 NavigationBar 的五段顺序、返回键行为与其他页 FAB。
- **Acceptance Criteria**：
  - 订阅 Tab 不渲染 FloatingActionButton；流水/统计/资产/设置仍有“记一笔”。
  - 订阅页滚动到底部时最后一行菜单不被遮挡，底部不再出现 100dp 空白。
  - shell_test.dart 覆盖订阅 Tab 无 FAB、流水 Tab 有 FAB、五段切换不回归。

---

## Phase 3：分区与行排版

### TASK-006：组头对齐、表面与组色

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-001
- **Description**：让未分组与分组组头在标题、计数、金额三条基线上对齐，并建立分区表面的层级。
- **Details**：
  - _SectionCard 组头改为带底色 Container：color scheme.surfaceContainerHigh，padding fromLTRB(16, 10, 4, 10)；标题使用 titleMedium + w600；仍为两行（标题行 + 计数行）。
  - 前导槽：分组渲染 8×8、圆角 2 的色块 + 8dp 间距；未分组渲染 SizedBox(width: 16)；标题与计数行统一 padding-left 16，使两者 x 坐标一致。
  - 尾随槽：分组渲染 PopupMenuButton；未分组渲染 SizedBox(width: 48)，使金额右缘与分组一致。
  - 金额改为 LayoutBuilder + ConstrainedBox(maxWidth: 行宽 * 0.4) + FittedBox(scaleDown, alignment: centerRight)，不再使用 Flexible 平分；标题 Expanded + maxLines 1 + ellipsis。
  - 组头下统一加 Divider(height: 1)；删除第一行前的 if (i == 0) Divider，避免双线；行之间仍保留 Divider。
  - 组色：section.activeCount == 0 时用 scheme.outlineVariant（空组/纯暂停组），否则沿用 finance.chart[index % length]；颜色只用于 8dp 色块与 Hero 分段。
  - 不改变分组排序、菜单项与删除/调序逻辑。
- **Acceptance Criteria**：
  - 390dp 下“影音娱乐”“工具软件”“未分组”的标题左缘 x 相同（±0.5），计数行左缘相同，金额右缘相同（±0.5）。
  - 空分组不再出现红色色块与 0.00；纯暂停组使用中性色。
  - 组头有可见的表面底色与单条分隔线；320dp + 2x 下组头不溢出、长名称省略、金额不挤掉标题。
  - 更新 subscriptions_test.dart：新增对齐矩形断言与空组断言；既有菜单/调序用例不回归。

### TASK-007：行布局、暂停态与菜单语义

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-002, TASK-006
- **Description**：让行文本列吃到剩余宽度，金额有界收缩；暂停状态整体后退；菜单具备对象级无障碍标签。
- **Details**：
  - _SubscriptionRow 用 LayoutBuilder 获取行宽；文本列 Expanded 并加 key subscription-body-{id}；金额块改为 ConstrainedBox(maxWidth: 行宽 * 0.4) + FittedBox，加 key subscription-amount-{id}；不再使用 Flexible(Align(FittedBox))。
  - 名称 Text maxLines 2 + ellipsis；元信息使用 TASK-002 的 formatRenewalMeta，maxLines 2 + ellipsis；金额保留“/ 月”。
  - 暂停行整行底色 scheme.surfaceContainer；头像使用 surfaceContainerHigh + onSurfaceVariant；金额 onSurfaceVariant + w500；使用中行保持透明。
  - 行菜单 tooltip 改为“{订阅名} 操作”；分组菜单 tooltip 改为“{分组名} 分组操作”；空分组“添加”按钮加 Semantics(label: '添加订阅到{分组名}')（未分组为“添加订阅到未分组”）。
  - 保持 minHeight 62、头像 38、右侧菜单 48dp 点击区；不改菜单项与回调。
- **Acceptance Criteria**：
  - 390dp 下普通行文本列宽度大于金额块宽度（用两个 key 的 getSize 断言），Netflix 元信息不出现“11 / 月15日”断行。
  - 1Password 长名称最多两行；“已暂停”只出现在元信息中一次，名称区无徽标换行。
  - 320dp + 2x 无 RenderFlex 溢出，金额右缘在视口内，行高有界。
  - 读屏/长按 tooltip 能区分具体订阅或分组；既有行菜单、暂停/恢复、编辑、删除用例不回归。

---

## Phase 4：表单与确认

### TASK-008：订阅表单内容自适应高度

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P1 / TASK-004
- **Description**：去掉订阅表单固定 86% 屏高造成的巨大留白，让表单按内容高度展示并在键盘弹出时滚动。
- **Details**：
  - subscription_sheet.dart 移除 height = (size.height - insets.bottom) * 0.86 与固定 SizedBox(height: height)；改为 ConstrainedBox(maxHeight: (size.height - insets.bottom) * 0.86) 包裹 Column(mainAxisSize: MainAxisSize.min)。
  - 标题栏保持固定；字段区用 Flexible(child: SingleChildScrollView(...))；底部 SafeArea 保存按钮保持固定；外层 Padding(bottom: insets.bottom) 保留。
  - 根节点加 key subscription-sheet，便于用例测量高度；showModalBottomSheet 的 isScrollControlled/useSafeArea/isDismissible/enableDrag 值保持不变（保留提交保护）。
  - 保存按钮文案改为：编辑“保存”，新建“添加订阅”；不改变 busy 时禁用/进度指示。
- **Acceptance Criteria**：
  - 390×844 下编辑表单整体高度 < 590（约 70% 屏高），字段与保存按钮之间无 >100dp 空白。
  - 320×800 + 2x 下表单不溢出，字段可滚动，保存按钮不被键盘遮挡。
  - 新建表单按钮显示“添加订阅”，编辑显示“保存”；提交中禁用逻辑不变。
  - subscriptions_test.dart 新增高度断言与 320dp + 2x 表单用例。

### TASK-009：字段级校验与焦点

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P1 / TASK-008
- **Description**：把订阅表单的校验错误从顶部条改为字段级错误，并把焦点送到第一个错误字段。
- **Details**：
  - 新增 FocusNode nameFocus/amountFocus/dayFocus，dispose 时释放。
  - 新增 String? _nameError/_amountError/_dayError；_submit 校验时写入对应错误并 requestFocus 第一个失败字段，return；字段 onChanged 清对应错误。
  - 三个 TextField 的 InputDecoration 增加 errorText；不再用 _error 承载字段校验；_error 只保留 API/未知异常的服务端消息，仍在表单顶部显示。
  - 服务名空 -> “请输入服务名称”；金额非法 -> 既有金额文案；扣款日非法 -> 既有日期文案；分组不存在 -> 保留顶部条或字段级提示，不新增第二种文案。
  - 不改变提交体、金额解析、最大长度与输入格式化。
- **Acceptance Criteria**：
  - 空表单点保存：服务名称下方出现错误，焦点在服务名称，无网络请求。
  - 金额 0 / 扣款日 32：错误分别出现在金额/扣款日字段下方，焦点落到对应字段。
  - 修改字段后对应错误消失；API 失败仍在顶部错误条显示且保留输入。
  - 既有表单校验/提交/预填用例更新后通过。

### TASK-010：删除确认、空分组文案与创建后筛选回位

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P1 / TASK-001, TASK-008
- **Description**：让破坏性确认具备危险语义；修正删除 0 项分组的文案；新增订阅/分组后若当前筛选会隐藏结果，自动回到“全部”。
- **Details**：
  - app/lib/core/widgets/ledger_widgets.dart 的 ConfirmDialog：确认 FilledButton 使用 style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError)；取消按钮保持 TextButton + autofocus。
  - _deleteGroup：先算 count；count == 0 时 message 为“删除后不可恢复。”，成功提示“分组已删除”；count > 0 保持既有“「名称」内的 N 项订阅将移至未分组。”与“分组已删除，订阅已移至未分组”。
  - SubscriptionSheet.show 返回 Future<bool>（保存成功 true，取消/关闭 false）；GroupSheet.show 创建成功返回 true，重命名/取消返回 false。
  - _addSubscription / _addGroup 改为 async，await 结果；若返回 true 且 _filter != SubscriptionFilter.all，则 setState 切回 all，保证新建项可见；编辑/重命名不切换。
  - 删除订阅确认文案统一为“「{名称}」删除后不可恢复。”，与分组确认的引号风格一致。
- **Acceptance Criteria**：
  - 删除确认的“删除”按钮为 error/onError 配色，浅色/深色均与主操作区分；取消不产生请求。
  - 删除 0 项分组不再出现“订阅已移至未分组”；删除有订阅分组仍提示迁移。
  - 已暂停筛选下新建订阅：保存成功后筛选自动回到“全部”，新行可见并提示“订阅已添加”；取消表单不改变筛选。
  - 已暂停/使用中筛选下新建分组：成功后回到“全部”，新空组可见；重命名不改变筛选。
  - 既有删除/新增/分组用例更新后全绿。

---

## Phase 5：测试、文档、归档与提交

### TASK-011：订阅页与 Shell 用例补齐

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-001 ~ TASK-010
- **Description**：为本轮所有可见契约补齐可执行用例，覆盖常规/窄屏/大字体/深色与关键交互。
- **Details**：
  - subscriptions_test.dart：组头计数（全部/使用中/已暂停）、暂停小计“—”、空组无 0.00、Hero 分布条高度 7 与 Semantics、筛选胶囊切换无异常、操作区在 Hero 之后、空态在 LedgerCard 内、未分组/分组标题与金额对齐、行文本列宽度 > 金额块、元信息无日期词中断行、表单高度/字段级错误/新建按钮文案、删除 0 项分组文案、暂停筛选新增后回全部。
  - subscriptions_utils_test.dart：formatRenewalMeta 使用中/暂停/短月/跨年/word joiner。
  - shell_test.dart：订阅 Tab 无 FAB、流水 Tab 有 FAB、五段切换与返回键不回归。
  - 320dp + 2x：订阅页首屏、分区、表单打开与滚动；takeException 为 null；关键文本/金额矩形在视口内。
  - 深色：pump 页面或 Shell 的 dark 主题，确认无异常、关键文案可见；不新增金图。
- **Acceptance Criteria**：
  - 新增/更新用例全部通过；既有 177 项不回归；测试总数记录在 Project.md。
  - 320dp + 2x 与深色用例均无异常；分布条、表单高度、对齐三类回归点都有断言。
  - 用例不依赖网络、真实时间或审计数据；使用 harness 的 fake 服务与固定 now。

### TASK-012：门禁与 Project.md 同步

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-011
- **Description**：跑完整 Flutter 门禁并同步项目事实文档。
- **Details**：
  - 依次执行：dart format --output=none --set-exit-if-changed lib test；flutter analyze；flutter test --no-pub；flutter build web --no-pub。使用仓库 .pub-cache 与既有 HOME 约定。
  - 记录实际退出码、测试项数、Web 构建结果；构建产物 app/build/web 在通过后删除，若执行前已存在则保留原状，不误删用户产物。
  - 更新 .docs/Project.md：Android 订阅页的 Hero 分布条、页面操作顺序、组头对齐/计数/小计、行排版、FAB 在订阅 Tab 隐藏、表单内容自适应与字段级校验、ConfirmDialog 危险色；更新测试项数与已知限制（订阅不写快照、APK 待真机验收不变）。
  - 不改历史决策记录的既有事实；只改当前状态、结构描述、测试与已知限制。
- **Acceptance Criteria**：
  - 四条门禁退出码均为 0；flutter analyze 输出 No issues；测试项数记录准确。
  - Project.md 只描述已落地事实，不写计划口吻；与代码实际状态一致。
  - app/build/web 不残留在工作区（除非执行前已存在）。

### TASK-013：归档与白名单提交

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-012
- **Description**：按工作流归档 Plan/Tasks，并只提交本轮相关文件。
- **Details**：
  - 归档目录按执行日计算 .docs/MM-DD-vN/：同日已有目录取最大 N + 1；将根目录 Plan.md / Tasks.md 移入，校验两文件同时存在且根目录无残留。
  - git status 查看所有变更；git diff 检查本轮改动；git log -5 对齐提交风格。提交信息使用 fix(app): 前缀 + 中文说明（聚焦为什么修，而非逐条罗列）。
  - 使用 git commit --only -- 白名单路径提交：app/lib/features/subscriptions/、app/lib/features/shell/app_shell.dart、app/lib/core/widgets/ledger_widgets.dart、app/test/features/subscriptions_test.dart、app/test/features/subscriptions_utils_test.dart、app/test/features/shell_test.dart、.docs/Project.md、.docs/MM-DD-vN/。
  - 不提交既有暂存技能文件、.pi 删除、temp 截图/HTML、构建产物、临时数据库；不使用 git add -A、git reset、--no-verify。
- **Acceptance Criteria**：
  - .docs/MM-DD-vN/ 同时含 Plan.md 与 Tasks.md，根目录无残留。
  - HEAD 只包含白名单文件；git status 中既有暂存技能文件仍保持原状态，未被带入提交。
  - 提交信息符合 Conventional Commits 中文约定；提交后工作区无本轮构建/临时产物。
