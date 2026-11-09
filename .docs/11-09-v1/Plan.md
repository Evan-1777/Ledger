# Plan：Android 账单流水的信息展示、筛选与搜索

**状态**：DONE（2026-11-09 交付完成，已归档 .docs/11-09-v1/）
**日期**：2026-11-09
**完成日期**：2026-11-09
**版本**：v1.0
**回归结论**：`go test ./...` 通过；`dart format` 0 变更；`flutter analyze` No issues；`flutter test` 全量 211 项、209 通过（2 项既有订阅用例在改动前基线即失败，与本轮无关）；`flutter build web` 成功。
**设计哲学**：Material 3（Android 主交付面既定体系，`ColorScheme.fromSeed(#0078D4)` + FinanceColors 语义色）
**依据**：用户 Main-Hybrid 需求、用户提供的 Android 截图、.docs/SCOPE.md、.docs/Project.md、app/ 与 internal/server 源码、temp/ 既有 Android 原型约定

---

## 1. 背景与目标

用户本轮提出三条需求：

1. 新增对支付方式、分类与标签的筛选；
2. 支持搜索消费；
3. 优化账单信息展示逻辑与 UI/UX——目前信息展示不全、被省略号替代、标签显示不全、支付方式未展示。

### 1.1 现状证据

| 证据 | 位置 | 结论 |
|------|------|------|
| 截图 temp/Screenshot_2026-10-29-08-51-44-830_com.evan1777.ledger.jpg | 流水页行 | 行元信息显示为「额外收入 · 拼多多 …」，标签被截断，支付渠道与时间完全不可见 |
| `transactionMeta()` 拼接单行 `分类 · 标签 · 渠道 · 时间` | app/lib/features/stream/stream_utils.dart:84-103 | 四类异构字段同挤一条截断行，尾部字段必然丢失 |
| 行渲染 `maxLines: 1, overflow: ellipsis` | app/lib/features/stream/stream_screen.dart:420-427 | 截断发生在渲染层，字段越多丢失越多 |
| 筛选只有一个类型维度 | app/lib/features/stream/stream_screen.dart:247-320（_FilterMenu）与 app/lib/core/state/ledger_controller.dart:8-30（TransactionFilter） | 无分类/标签/渠道维度，无搜索 |
| `GET /api/transactions` 仅接受 limit/offset/type | internal/server/transactions.go:47-134 | 服务端没有维度筛选与关键词检索能力 |
| `getTransactions({type, limit})` | app/lib/core/api/api_client.dart:271-281 | 客户端只上送类型与条数 |

### 1.2 本轮目标

在不改数据库 schema、不改 Web 端、不新增依赖、不改版本号的前提下：

- 把流水查询从「单一类型」升级为「类型 + 分类 + 标签 + 支付渠道 + 关键词」的正交查询模型，筛选在服务端生效（单一数据源，避免只过滤已加载的 100 条而产生漏检）；
- 重排行信息为两个稳定槽位：中栏承载「分类 · 标签 · 时间」，右栏承载「支付渠道（支出/收入）或转账手续费」，使支付渠道不再被其它字段挤出；
- 列表头引入搜索入口与当前条件摘要，筛选维度通过底部选择面板收口，交互与统计页既有面板同构。

---

## 2. 范围

### 范围内

- internal/server/transactions.go（列表查询维度与关键词检索）
- internal/server/server_test.go（新查询维度契约用例）
- app/lib/core/api/models.dart（TransactionQuery 值对象）
- app/lib/core/api/api_client.dart（列表查询参数拼装）
- app/lib/core/state/ledger_controller.dart（查询状态、请求代际、缓存写入条件、失效维度剪枝）
- app/lib/features/stream/stream_utils.dart（行信息派生与条件摘要纯函数）
- app/lib/features/stream/stream_screen.dart（行布局、列表头搜索与筛选面板）
- app/test/core/api_client_test.dart、app/test/core/ledger_controller_test.dart、app/test/features/stream_utils_test.dart、app/test/features/stream_screen_test.dart
- .docs/Project.md 的流水页、数据流、测试与已知限制同步
- temp/stream-filter-search-demo.html（规划段原型，见第 9 节）

### 范围外

- Web 端（web/）：React 前端本轮不动。新增查询参数为可选参数，旧调用方 `/api/transactions?limit=100` 行为不变。
- 数据库 schema、依赖版本、Flutter SDK、Android 版本号与 CI 工作流。
- 流水分页/无限加载：列表仍为「最近 N 条」窗口（服务端筛选先于 LIMIT，结果正确），本轮不引入分页。
- 月份窗口语义：列表头左槽在无条件时仍显示当前月份（既有行为），本轮只在其上叠加「条件摘要」，不改列表的取数范围。
- 统计页、资产页、设置页、订阅页：不改动其布局与逻辑。

---

## 3. 设计决策

| 决策项 | 选择 | 理由 | 替代方案（为何不选） |
|--------|------|------|----------------------|
| 筛选/搜索执行位置 | 服务端 `GET /api/transactions` 新增 category_id / tag_id / payment_method_id / q | 客户端只持有最近 100 条，本地过滤会漏掉历史记录；统计端点已按同一口径在服务端筛选，保持单一数据源与对称性 | 客户端内存过滤（漏检、与统计页口径不一致） |
| 渠道维度匹配口径 | payment_method_id 双边匹配目标与来源渠道（`t.payment_method_id = ? OR t.source_payment_method_id = ?`） | 转账的转出账户与还款的扣款账户存在 source_payment_method_id，行上也同时展示；不双边匹配会让用户筛某张卡时漏掉该卡转出/还款的账单，且与关键词匹配 spm.name、与 settings.go 渠道引用检查口径不一致 | 只匹配 t.payment_method_id（漏检、与关键词检索行为矛盾） |
| 查询状态模型 | 新增不可变 `TransactionQuery`（type/categoryId/tagId/paymentMethodId/keyword + `isActive`/`hasDimensions` + `==`/`hashCode`），置于 models.dart | 与既有 `StatsQuery` 同构；`==` 让 setQuery 天然去重，避免 5 个散落字段各自的比较逻辑 | 在控制器上堆 5 个字段与 getter（状态分散、相等判断手写易错） |
| 类型维度表达 | 删除 `TransactionFilter` 枚举，类型用 `TransactionType?`（null = 全部） | 该枚举的 4 个 label 与 `TransactionType.label` 完全重复；筛选面板本来就要重写，删除即消除重复概念 | 保留枚举并新增映射函数（多一层转换与一处重复词表） |
| 类型与分类/标签的正交联动 | 分类组随类型收敛（全部→支出+收入；支出→仅支出；收入→仅收入；转账/还款→隐藏整组并清空该维度）；切换类型使已选分类失效时同步清空分类与标签 | 支出仅关联支出分类、收入仅关联收入分类、转账与还款固定绑定系统分类（validateTransactionInput 自动注入），面板若保留全量分类就会构造出服务端恒空的组合 | 保留全量分类列表（用户可选出恒空结果）；把系统分类也列入（转账/还款只剩唯一系统分类，无筛选价值） |
| 筛选面板形态 | 底部草稿面板：类型 / 分类 / 标签 / 支付渠道 + 「重置 / 应用」，复用 `showLedgerPicker` 外壳与 ChoiceChip | 与统计页既有筛选面板同构（草稿态、应用后生效），避免每点一下都发一次请求；外壳复用共享构件，不新增第二套 sheet 实现 | 即时生效的多级菜单（多次请求、无草稿回退）；自建第二套 sheet 外壳（重复实现） |
| 标签维度前置条件 | 先选分类再列其标签；未选分类或该分类无标签时整组（含标题）不渲染 | 标签在模型上隶属于分类，同名标签跨分类存在时扁平列表语义歧义；渐进披露本身即自解释，不需要「选择分类后可筛选标签」这类引导文案（用户明确要求无提示） | 扁平列出全部标签（歧义、分类维度被隐式改写）；保留空分组与提示文案（无交互价值且违反无提示约束） |
| 搜索入口 | 列表头内的搜索图标 → 同行内联展开搜索框（关键词为查询的一维，300ms 防抖） | 复用同一条列表与同一套行渲染，搜索结果与普通列表行为一致（日分组、小计、编辑/删除）；不做独立结果页，避免第二套列表 UI | 独立搜索页 / SearchAnchor（需复制结果列表渲染与空/错/加载态）；每击键一次请求（抖动与浪费） |
| 行信息分槽 | 中栏「分类 · 标签 · 时间」；右栏「支付渠道」，转账右栏为「手续费」、还款右栏留空 | 渠道占用不参与中栏截断的独立槽位，长标签/长描述不再挤掉它；金额与渠道形成右对齐列，扫视更快 | 元信息放宽到两行（渠道仍可能被挤掉）；多行 Chip 陈列（行高膨胀、视觉噪声） |
| 时间位置 | 中栏末尾（各类型统一），转账/还款的中栏为「转出 → 转入 · 时间」 | 类型之间时间位置一致，且不占用不可截断的右槽 | 时间放右槽（支出/收入类型下与渠道争位） |
| 中栏行数 | 元信息最多两行（描述仍单行） | 用户点名「标签显示不全」；右列占用后中栏更窄，单行下长分类与长标签仍会被省略 | 强制单行（长标签与时间继续被截断）；固定行高（行高随内容在 56–78dp 浮动，短元信息行不受影响） |
| 列表头左槽 | 查询生效时显示条件摘要（如「支出 · 虚拟商品 · 微信支付」「搜索「拼多多」」），否则显示当前月份 | 筛选/搜索后必须能看出列表为何变短；与统计页摘要行同构 | 只给筛选胶囊加高亮（多维度下无法表达具体条件） |
| 筛选入口 | 纯图标按钮：仅 `Icons.filter_alt_outlined`，48dp 触达，tooltip「筛选」，条件生效时以 secondaryContainer / onSecondaryContainer 着色 | 用户明确要求「能用 SVG Icon 就不用文字展示」；去掉文字与下拉箭头后为搜索框释放约 65dp，320dp + 2x 搜索态不再挤压 | 文字 + 图标 + 下拉箭头（违反用户指令，320dp + 2x 下搜索框正文仅剩约 65dp）；无 tooltip 的裸图标（失去无障碍名称） |
| 冷启动快照 | 仅当 `!query.isActive` 时写入流水快照 | 快照语义是「全量流水」，筛选子集写入会让下次冷启动首帧展示残缺列表 | 按查询分别缓存（多份键、无实际收益） |
| 维度失效剪枝 | 配置刷新后若所选分类/标签/渠道已不存在，清空该维度并重新拉取流水 | 与既有统计筛选剪枝同构；否则用户删除渠道后流水页会永久卡在空结果 | 不剪枝（界面与数据不一致） |
| 关键词匹配范围 | 描述、分类名、标签名、目标渠道名、转出渠道名 | 与行上可见的信息一致：用户按看到的任意名字都能搜到 | 仅匹配描述（搜渠道/分类名无结果，与界面不符） |
| LIKE 通配符 | 转义 `%`、`_`、`\` 并 `ESCAPE '\'` | 用户输入「50%」不应退化为「包含 50 的任意串」；属输入边界正确性，非防御性膨胀 | 直接拼接通配符（语义错误） |

---

## 4. 阶段划分

### Phase 1：服务端查询维度（TASK-001 ~ TASK-002）

- **输入**：internal/server/transactions.go 现有列表查询、stats.go 的 `parseOptionalPositiveID` 与 `statsFilter.clause` 拼装范式、server_test.go 既有账单用例脚手架。
- **输出**：`GET /api/transactions` 支持 category_id / tag_id / payment_method_id / q 与它们的正交组合；非法 ID 返回 400；关键词 LIKE 转义；服务端契约用例。
- **验收**：`go test ./...` 通过；单维度、组合维度、关键词（描述/分类/标签/渠道名）与 `%` 字面量用例均有断言。

### Phase 2：客户端查询模型与数据流（TASK-003 ~ TASK-004）

- **输入**：Phase 1 的参数契约、models.dart 的 `StatsQuery` 范式、ledger_controller 的请求代际与快照写入规则。
- **输出**：`TransactionQuery` 值对象；ApiClient 按查询拼装参数；控制器以 `query` 取代 `filter`，`setQuery` 去重后重新拉取；快照只写全量结果；配置刷新剪枝失效维度。
- **验收**：`flutter analyze` 无引用残留（`TransactionFilter` 已删除）；请求 queryString 断言覆盖五维；筛选态不覆盖快照、剪枝后重新请求用例通过。

### Phase 3：行信息分槽与条件摘要（TASK-005 ~ TASK-006）

- **输入**：Phase 2 的 `TransactionQuery`、stream_utils 既有派生函数与 app/test/support 假数据。
- **输出**：中栏/右栏两个派生函数与条件摘要纯函数；`_TransactionRow` 改为「文本列吃剩余宽度 + 右列有界（金额/渠道）」双槽布局；`_ListHeader` 左槽在条件生效时显示摘要；空态文案按条件区分。
- **验收**：渠道名以独立 Text 渲染且在行右缘内；长分类+长标签不再影响渠道可见性；320dp + 2x 无溢出、行高有界；摘要文案用例通过。

### Phase 4：筛选面板与搜索入口（TASK-007 ~ TASK-009）

- **输入**：Phase 2 的查询模型、Phase 3 的列表头结构、`showLedgerPicker` 外壳与统计页筛选面板范式。
- **输出**：`_StreamFilterSheet`（类型/分类/标签/支付渠道 + 重置/应用，草稿态）；列表头搜索图标与内联搜索框（防抖、清空、关闭）；交互与边界用例。
- **验收**：应用后面板关闭并发起一次对应请求；重置回到全部维度且保留关键词；搜索 300ms 内多次输入只发一次请求；搜索框清空/收起行为确定；320dp + 2x 面板可滚动且底部按钮可达。

### Phase 5：门禁、文档、归档与提交（TASK-010 ~ TASK-012）

- **输入**：全部实现与测试。
- **输出**：Go 与 Flutter 全量门禁结论；Project.md 同步；归档目录与白名单提交。
- **验收**：`go test ./...`、`make app-format`、`make app-analyze`、`make app-test`、`make app-web` 全部退出码 0 并记录项数；Project.md 只写已落地事实；归档目录同时含 Plan.md 与 Tasks.md；提交不夹带既有暂存技能文件、temp 截图与未采纳原型、构建产物。

---

## 5. 风险与缓解

| 风险 | 等级 | 缓解 |
|------|------|------|
| 服务端 `type` 由 if/else 链改为条件数组拼装时语义漂移（含未知值静默不过滤的既有行为） | 中 | 保持「未知 type 不过滤」的既有语义；用例覆盖 type=expense/income/transfer/repayment 与未知值 |
| 关键词 LIKE 在大表上全表扫描 | 低 | 个人单账本、行数量级小；本轮不建索引（YAGNI），在 Project.md 已知限制中注明 |
| 行布局改双槽后 320dp + 2x 压缩文本列 | 中 | 文本列 Expanded + 单行省略；右列 ConstrainedBox(maxWidth: 行宽 * 0.42) + 金额 FittedBox；用例断言无溢出且渠道矩形在行内 |
| 右栏渠道名过长仍会省略 | 低 | 渠道名由用户维护且通常较短；保证「不被其它字段挤出」是本轮契约，极端长名省略属可接受降级 |
| 搜索防抖与请求代际交互导致旧响应覆盖新结果 | 中 | 复用控制器既有 `_transactionsGeneration`；用例断言快速连续输入后仅一次最终结果写入 |
| 筛选面板维度增多后 320dp + 2x 溢出 | 中 | 面板内 chips 使用 Wrap + 滚动区 + 固定底部按钮；用例覆盖 |
| 删除 `TransactionFilter` 枚举造成编辑态类型锁定等既有引用遗漏 | 低 | `flutter analyze` 全量兜底；RecordSheet 的编辑锁定使用 `TransactionType`，不受影响 |
| 提交时夹带工作区既有暂存文件（.agents/.codebuddy/.dsh 技能、.pi 删除、temp 截图与未采纳原型） | 高 | 使用 `git commit --only --` 白名单路径；提交前后核对 git status 与 `git show --stat`；不 reset、不恢复 |

---

## 6. Subagent 协同评估

| 维度 | 评估 |
|------|------|
| 任务复杂度 | 服务端约 60 行 + 用例；客户端集中在 4 个文件 + 4 个测试文件，改动相互咬合（同一查询对象贯穿模型/客户端/控制器/页面） |
| 上下文关联 | 高：五维查询契约、行信息分槽、面板草稿态共享同一批决策，拆开后需反复对齐同一契约 |
| 经济与时间效益 | Phase 1（服务端）文件集独立，理论可并行；但其体量约占本轮的 10%，而 `executor` 契约以「执行 → 测试 → 文档 → 归档 → 提交」整链收尾，与其为单一切片引入一次归档/提交风险，不如由主线先落服务端契约再顺势推进客户端 |

**结论**：本轮不派发 Subagent，全部由主线执行。服务端切片体量小、且与客户端共用同一查询契约，主线串行推进的端到端成本低于一次隔离上下文的交接成本。

---

## 7. Task 预览

| Phase | 预估 Task 数 | 执行主体 | 示例 |
|-------|-------------|----------|------|
| Phase 1 | 2 | 主线 | 列表查询维度与关键词检索；服务端契约用例 |
| Phase 2 | 2 | 主线 | TransactionQuery 与 ApiClient 参数；控制器查询状态与剪枝 |
| Phase 3 | 2 | 主线 | 行信息派生函数；行双槽布局与列表头摘要 |
| Phase 4 | 3 | 主线 | 筛选面板；搜索入口；交互与边界用例 |
| Phase 5 | 3 | 主线 | 门禁；Project.md 同步；归档与白名单提交 |

> 总计 12 个 Task，详见 Tasks.md。

---

## 8. 交互与视觉规格（供实现与原型对照）

### 8.1 列表头（390dp）

```
[ 月份 / 条件摘要 ................. ] (搜索 icon) (筛选 icon)
[ 搜索框（展开态，替代左槽） ....... ] (筛选 icon)
```

- 搜索图标 48×48 点击区（`stream-search-toggle`），点击后在同行左槽展开输入框并聚焦。
- 输入框（`stream-search-field`）：前缀搜索图标、单行、`hintText: 搜索账单`、`textInputAction: search`；后缀按钮（`stream-search-clear`）：有输入时清空，空输入时收起搜索。
- 筛选入口（`stream-filter-menu`）：纯图标按钮 48×48，仅 `Icons.filter_alt_outlined`，tooltip「筛选」，不渲染文字与下拉箭头；条件生效时底色 `secondaryContainer`、前景 `onSecondaryContainer`，否则 `surfaceContainerHigh` 与 `onSurface`。

### 8.2 行（两槽，元信息最多两行）

```
[类型图标 36] [ 描述 (bodyLarge, 1 行)            ] [ 金额 (titleSmall, FittedBox) ]
              [ 分类 · 标签 · 时间 (bodySmall ≤2 行) ] [ 支付渠道 (labelSmall, 右对齐) ]
```

- 中栏 `Expanded`：描述单行省略，元信息最多两行后省略（短元信息行仍保持单行行高）；右栏 `ConstrainedBox(maxWidth: 行宽 * 0.42)`，右对齐。
- 转账：中栏 `转出 → 转入 · 时间`，右栏 `手续费 ¥X`（无手续费则不渲染该行）；还款：中栏 `来源（缺省为「外部/未记录资金」）→ 目标 · 时间`，右栏留空。
- 类型用色、图标与菜单沿用现状（`TypeIcon`、`amountColor`、`PopupMenuButton`）。

### 8.3 筛选面板

复用 `showLedgerPicker`（顶部把手 + 标题「筛选」+ 滚动区 + 固定底部操作行）：

| 分组 | 选项 |
|------|------|
| 类型 | 全部 / 支出 / 收入 / 转账 / 还款 |
| 分类 | 随类型收敛：类型=全部 → 支出分类 + 收入分类（先支出后收入）；类型=支出 → 仅支出分类；类型=收入 → 仅收入分类；类型=转账/还款 → 整组不渲染 |
| 标签 | 仅在已选分类且该分类有标签时渲染：全部标签 + 该分类标签；未选分类或该分类无标签时整组（含标题）不渲染，不使用引导文案 |
| 支付渠道 | 全部渠道 + 渠道列表（接口返回顺序，资产与负债同列）；过滤双边匹配目标与来源渠道 |
| 底部 | TextButton「重置」 + FilledButton「应用」 |

- 草稿态：面板内改动只落在草稿，点「应用」才写回控制器并重新拉取；「重置」恢复类型=全部、分类/标签/渠道=未选，并保留当前关键词。
- 类型联动：切换类型后若已选分类不在收敛后的可选列表内（含类型切到转账/还款），同步清空分类与标签，避免构造出 `type AND category_id` 恒空组合。
- 对齐：`showLedgerPicker` 滚动区自带 8dp 水平内边距，内容补 12dp 后与面板标题、底部按钮共同对齐在 20dp。
- 空态/加载/错误态不变；筛选无结果时文案为「没有符合条件的账单」。

---

## 9. 原型记录

- 原型文件：`temp/stream-filter-search-demo.html`（静态 HTML，浏览器直接打开；390×844 手机框，Material 3 令牌与既有 temp 原型一致）。
- 覆盖对象：①现状行（对照） ②新行双槽 ③搜索展开态 ④筛选面板 ⑤筛选生效态（摘要 + 图标着色）。
- 已按 2026-11-09 审阅意见更新：筛选入口改为纯图标、标签组随分类渐进披露（无引导文案）、中栏元信息最多两行。
- 克制范围：只画本次改动的列表头、行与筛选面板；统计/资产/订阅等未触及页面不进入原型。

---

## 10. 交接说明

规划段到此结束。接手模型先读本 Plan 与 Tasks.md，再按 TASK-001 起的顺序执行。

- 执行前先 `git status` 核对工作区既有暂存文件（技能目录、.pi 删除、temp 截图与未采纳原型 ledger-ui-variant-a.html），不 reset、不恢复、不纳入本轮提交。
- 原型提交遵循仓库既有约定：采纳的方案原型随交付提交（见 91fc9cc 的 temp/ledger-ui-variant-b.html、57256b9 的 temp/subscriptions-page-demo.html），未采纳的备选与截图不提交；本轮采纳原型为 temp/stream-filter-search-demo.html。
- 测试基线：改前先跑一次 `go test ./...` 与 `make app-format && make app-analyze && make app-test`，记录实际基线项数（Project.md 记录最近基线为 Flutter 193 项，2026-11-01）。
- 临时后端与 Flutter Web 复核如需复现：`LEDGER_PORT=8081`、`LEDGER_DB_PATH=/tmp/ledger-audit.db`、`flutter run -d web-server --web-port=5175`；复核结束关闭进程、删除临时数据库与 `app/build/web`。

---

## 11. 审阅吸收记录（2026-11-09）

交接期收到外部审阅报告，逐条对照代码库核实后的处理：

| 编号 | 审阅意见 | 判定 | 依据与落点 |
|------|----------|------|------------|
| 1 | payment_method_id 应双边匹配来源渠道 | 采纳 | `internal/server/settings.go:258` 的渠道引用检查即 `payment_method_id = ? OR source_payment_method_id = ?`；行上转账与还款本就展示两侧渠道，与关键词匹配 spm.name 同口径。落 TASK-001 / TASK-002 |
| 2 | 类型与分类/标签未正交联动，存在恒空组合 | 采纳 | `validateTransactionInput` 自动绑定系统分类，支出只关联支出分类、收入只关联收入分类，跨类组合在服务端恒为空。落 TASK-007，原型同步 |
| 3 | 筛选入口应纯图标；未选分类不应渲染标签空组与提示文案 | 采纳 | 用户原始指令「能用 SVG Icon 就不用文字展示」「无需任何提示」；同时为 320dp + 2x 搜索态释放宽度。落 TASK-007 / TASK-008 与原型 |
| 4 | 中栏维持单行仍会截断长标签与时间 | 采纳 | 右列占用后中栏更窄，单行无法保证标签完整；行高断言限定为短元信息行。落 TASK-006 |
| 5 | 复用 showLedgerPicker 时内容左缘需补 12dp | 采纳 | `ledger_widgets.dart` 标题与 footer 内边距为 20dp，滚动区为 8dp（`LedgerPickerOption` 自带 12dp）。落 TASK-007 |
| 6a | 搜索清空分支未取消防抖定时器 | 采纳 | 输入后 300ms 内清空会让挂起定时器回填旧关键词。落 TASK-008 |
| 6b | 增加 didUpdateWidget 同步外部关键词变化 | 驳回 | `app.dart` 的 `_SessionGate` 在未认证时返回 `LoginScreen`，`AppShell` 及其子 State 被销毁并由 dispose 释放控制器；关键词只由列表头自身写入，配置剪枝不改关键词。无可达的外部改写路径，加同步属防御性膨胀 |
