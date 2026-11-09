# Tasks：Android 账单流水的信息展示、筛选与搜索

**关联 Plan**：Plan.md —— Android 账单流水的信息展示、筛选与搜索 v1.0
**状态**：DONE（2026-11-09 交付完成，已归档 .docs/11-09-v1/）
**日期**：2026-11-09
**完成日期**：2026-11-09
**回归结论**：同 Plan.md —— `go test ./...` 通过；`dart format` 0 变更；`flutter analyze` No issues；`flutter test` 211 项 / 209 通过（2 项既有订阅失败，与改动前基线一致）；`flutter build web` 成功。
**总计 Task**：12 个
**执行主体**：主线

---

## 前置约定

- 设计基线为 Material 3：颜色只取 ColorScheme / FinanceColors 角色，复用 app/lib/core/widgets 下的 LedgerCard、EmptyState、ErrorState、SkeletonList、LedgerSliverAppBar、showLedgerPicker；不新增硬编码色值、圆角或阴影，不新增依赖。
- 本轮只改 Android 客户端流水相关代码、Go 服务端账单列表端点与对应测试；不改 Web 端、数据库 schema、Flutter SDK 与依赖版本、Android 版本号。
- 查询契约（服务端与客户端一致，参数名冻结）：GET /api/transactions 支持 type、category_id、tag_id、payment_method_id、q、limit、offset；未上送的维度不过滤；q 去空白后为空则不过滤。
- 既有 API 兼容：不带新参数的请求行为不变（Web 端 /api/transactions?limit=100 不受影响）。
- 冷启动快照：仅当查询无任何条件（无类型、无维度、无关键词）时写入流水快照。
- 每个 Task 完成后代码须可编译可运行；跨 Task 的中间态允许保留临时实现（如类型单选 picker），由后续 Task 替换。
- 测试基线：执行前先跑 go test ./...、make app-format、make app-analyze、make app-test，记录实际基线项数（Project.md 记录 2026-11-01 为 Flutter 193 项），不把既有失败算入本轮。
- 工作区已有暂存的技能与规则文件、.pi 删除、temp 截图与未采纳原型（ledger-ui-variant-a.html）；以实时 git status 为准，不 reset、不恢复、不纳入本轮提交；提交使用 git commit --only -- 白名单路径。本轮采纳原型 temp/stream-filter-search-demo.html 按仓库既有约定纳入提交（对照 91fc9cc 的 temp/ledger-ui-variant-b.html、57256b9 的 temp/subscriptions-page-demo.html）。
- 根目录 Plan.md / Tasks.md 在交付完成后按 Archive 流程移入按执行日计算的 .docs/MM-DD-vN/。

---

## Phase 1：服务端查询维度

### TASK-001：列表端点支持分类/标签/渠道维度与关键词检索

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / 无
- **Description**：在 handleListTransactions 中把单条 WHERE 拼接改为条件数组拼装，并新增 category_id、tag_id、payment_method_id、q 四个查询参数。
- **Details**：
  - internal/server/transactions.go：handleListTransactions 改用 conditions []string 与 args []any；typeFilter 保留既有 strings.ToLower 与「未知值不过滤」语义，命中已知类型时追加 t.type = ? 条件。
  - 用既有 parseOptionalPositiveID 解析 category_id、tag_id、payment_method_id；解析失败返回 400，error 文案分别为 category_id must be a positive integer、tag_id must be a positive integer、payment_method_id must be a positive integer。
  - payment_method_id 命中时追加双边条件 (t.payment_method_id = ? OR t.source_payment_method_id = ?)，同一参数绑定两次；与 settings.go 的渠道引用检查（payment_method_id = ? OR source_payment_method_id = ?）以及本 Task 关键词匹配 spm.name 保持同一口径。
  - q 经 strings.TrimSpace 后非空时构造 `"%"+escapeLike(q)+"%"` 模式，追加对 t.description、c.name、tg.name、pm.name、spm.name 五列 LIKE 的 OR 组（每个 LIKE 后接 ESCAPE 子句，反斜杠作为转义符），同一模式绑定五次。
  - 新增包内私有函数 escapeLike(raw string) string：用 strings.NewReplacer 转义反斜杠、百分号与下划线。
  - 条件非空时拼接 " WHERE " 与 strings.Join(conditions, " AND ")；ORDER BY t.transacted_at DESC, t.id DESC 与 LIMIT / OFFSET 顺序、limit 默认 100 与上限 500 不变。
  - 不改 getTransactionByID、创建/更新/删除与 validateTransactionInput。
- **Acceptance Criteria**：
  - 四个新参数单独使用与任意组合（含与 type 组合）均按交集过滤，且仍按时间倒序。
  - 以转账的转出渠道或还款的来源渠道请求 payment_method_id 时，对应转账与还款同样返回。
  - 不带新参数时结果与改动前一致；limit 与 offset 行为不变。
  - category_id=abc、tag_id=0、payment_method_id=-1 返回 400，error 文案以参数名开头。
  - q=100% 只匹配描述或名称中字面包含 100% 的记录（百分号不退化为通配）。
  - go build ./... 通过，gofmt -l internal/server 无输出。

### TASK-002：列表查询维度契约用例

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-001
- **Description**：在 internal/server/server_test.go 新增 TestListTransactionsFilters，覆盖四维过滤、关键词检索、组合过滤与非法参数。
- **Details**：
  - 复用既有测试服务器与登录辅助（参照 TestTransactionsCRUD、TestTransferFullFlowAndInvariants 的建库与鉴权写法），播种：两条支出（不同分类、标签、渠道，描述分别含「午餐 · 牛肉面」与「地铁通勤」）、一条收入、一条转账（转出渠道与目标渠道均区别于支出渠道）、一条还款（来源渠道区别于上述渠道）。
  - 断言 category_id、tag_id 各自只返回命中记录；type=expense 与 category_id 组合返回交集且不含其它类型。
  - 断言 payment_method_id 双边匹配：以支出渠道请求返回该渠道的支出记录，以转账转出渠道请求返回该笔转账，以还款来源渠道请求返回该笔还款。
  - 断言 q 分别命中描述片段、分类名、标签名、目标渠道名、转账转出渠道名；不存在的片段返回空数组（非 null）。
  - 断言 q=% 与 q=_ 在无字面通配字符的数据上返回空。
  - 断言 category_id=abc、tag_id=0、payment_method_id=-1 返回 400。
  - 复用既有 httptest 与 JSON 解析写法，不新增测试依赖。
- **Acceptance Criteria**：
  - go test ./internal/server/ -run TestListTransactionsFilters -v 全部子断言通过。
  - go test ./... 全绿，既有账单、还款、转账用例不回归。

---

## Phase 2：客户端查询模型与数据流

### TASK-003：TransactionQuery 值对象与 ApiClient 参数拼装

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-002
- **Description**：在 models.dart 新增不可变 TransactionQuery，并让 ApiClient.getTransactions 按查询拼装参数。
- **Details**：
  - app/lib/core/api/models.dart 新增 class TransactionQuery：const 构造参数为 type、categoryId、tagId、paymentMethodId、keyword（默认空串）；字段类型为 TransactionType?、int?、int?、int?、String。
  - 派生成员：bool get hasDimensions（type 或三个 id 任一非空）、bool get isActive（hasDimensions 或关键词去空白后非空）、TransactionQuery withKeyword(String value)。
  - 覆盖 == 与 hashCode（全部字段）。不实现 copyWith，避免「null 表示保持原值」导致维度无法清空的歧义；需要改维度时直接构造新实例。
  - app/lib/core/api/api_client.dart：getTransactions 签名改为 Future<List<Transaction>> getTransactions(TransactionQuery query, {int limit = 100})，query 参数按「limit 恒有；type、category_id、tag_id、payment_method_id 仅在非空时上送；q 仅在关键词去空白后非空时上送」拼装。
- **Acceptance Criteria**：
  - 五维参数拼装均有断言；未设置的维度不出现在 queryString 中；关键词前后空白被裁剪，空串不上送。
  - TransactionQuery 相等性：同字段相等、任一字段不同即不等；hasDimensions 与 isActive 对「仅关键词」「仅维度」「全空」判定正确。
  - app/test/core/api_client_test.dart 既有 getTransactions 用例迁移到新签名后通过；flutter analyze 对该文件无告警。

### TASK-004：控制器查询状态、失效维度剪枝与快照口径

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-003
- **Description**：以 TransactionQuery query 取代 TransactionFilter filter，补齐相等去重、失效维度剪枝与快照写入条件，并同步页面调用点保持可编译。
- **Details**：
  - app/lib/core/state/ledger_controller.dart：删除 enum TransactionFilter；字段改为 TransactionQuery query（默认 const TransactionQuery()）。
  - 新增 Future<void> setQuery(TransactionQuery next)：next 与 query 相等直接返回；否则赋值后 await loadTransactions()；删除 setFilter。
  - loadTransactions()：调用 _api.getTransactions(query)；快照写入条件由「filter 等于全部」改为「query 非活跃」，注释同步为「只有无条件的全量结果才适合作为冷启动快照」。
  - loadConfig() 内在 _pruneStatsQuery() 之后新增 _pruneTransactionQuery()：分类已不存在则清 categoryId 与 tagId；标签不属于该分类或已不存在则清 tagId；渠道已不存在则清 paymentMethodId；关键词保持不变；仅在有变化时重新 loadTransactions()。
  - clear() 中 filter 复位改为 query 复位为 const TransactionQuery()。
  - app/lib/features/stream/stream_screen.dart：把 ledger.filter 与 ledger.setFilter 调用点改接 ledger.query 与 ledger.setQuery，空态判定改用 query.isActive；筛选入口暂以类型单选 picker 承接（key 保持 stream-filter-menu，选项由 TransactionType.values 加「全部」构成），保证本 Task 结束时页面可编译可交互。
- **Acceptance Criteria**：
  - 五维查询均可经 setQuery 上送；相同查询重复调用不发起请求。
  - 有条件请求不写快照（MemoryLedgerCache.transactionWrites 不增长），无条件请求写快照。
  - 删除被选中的分类后 categoryId 与 tagId 被清空且触发一次流水请求；只删标签只清 tagId；只删渠道只清 paymentMethodId；无失效项时不额外发请求。
  - clear() 后 query.isActive 为 false。
  - app/test/core/ledger_controller_test.dart 迁移 setFilter 与 filter 用法后通过；flutter analyze 无 TransactionFilter 残留引用。

---

## Phase 3：行信息分槽与条件摘要

### TASK-005：行信息派生函数与条件摘要

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-004
- **Description**：在 stream_utils.dart 拆分中栏与右栏两段行信息，并新增查询条件摘要纯函数。
- **Details**：
  - transactionMeta(Transaction)（中栏，保持函数名与文件位置）：支出与收入为「分类」加（标签非空时）「 · 标签」加「 · HH:mm」；转账为「转出 → 目标 · HH:mm」；还款为「来源（空则外部/未记录资金）→ 目标 · HH:mm」。时间统一置于中栏末尾。
  - 新增 transactionNote(Transaction)（右栏）：支出与收入返回 paymentMethodName；转账在 feeCents 大于 0 时返回「手续费」加格式化金额，否则返回空串；还款返回空串。
  - 新增 transactionQuerySummary(TransactionQuery query, {required List<Category> categories, required List<PaymentMethod> channels})：按 类型 → 分类 → 标签 → 渠道 → 关键词 顺序以「 · 」拼接已选项；类型段用 TransactionType.label；关键词段为「搜索「关键词」」；全空返回 null。
  - 不改 groupTransactions、dayHeader、daySubtotalParts、daySubtotal、transactionColor。
- **Acceptance Criteria**：
  - app/test/features/stream_utils_test.dart 更新 transactionMeta 期望并新增断言：支出 meta 为「餐饮美食 · 午餐 · 08:42」且 note 为「招商银行卡」；无标签时 meta 无空段；转账 meta 为「招商银行卡 → 支付宝 · 09:05」且 note 为「手续费 ¥1.50」；无手续费转账 note 为空串；还款 meta 为「外部/未记录资金 → 招商信用卡 · 10:00」且 note 为空串。
  - 摘要：全空返回 null；仅关键词返回「搜索「x」」；多维度按固定顺序拼接；分类或渠道被删除时不产生空段。
  - dart format 与 flutter analyze 无问题。

### TASK-006：行双槽布局与列表头条件摘要

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-005
- **Description**：把 _TransactionRow 改为「文本列吃剩余宽度 + 右列有界（金额/渠道）」，并让列表头在条件生效时显示摘要。
- **Details**：
  - _TransactionRow 外层用 LayoutBuilder 取行宽；结构为 TypeIcon(36)、间距 12、Expanded(描述 bodyLarge 单行省略 + 中栏 transactionMeta bodySmall 最多两行，即 maxLines 2 加省略)、间距 8、右列 ConstrainedBox(maxWidth 为行宽 0.42) 内含 FittedBox(scaleDown) 包裹的 AmountText 与（note 非空时）单行省略且右对齐的 labelSmall note、行尾 PopupMenuButton（保留 48dp 点击区与既有菜单项）。
  - 行内 key：stream-row-<id>、stream-row-meta-<id>、stream-row-note-<id>、stream-row-amount-<id>；金额继续使用 AmountText 与 transactionColor。
  - _ListHeader 增加 query、categories、channels 入参：左槽渲染 transactionQuerySummary(...)，为 null 时回退 formatMonth(DateTime.now())，单行省略。
  - 筛选入口胶囊保留 key stream-filter-menu；TASK-007 落地前沿用类型单选 picker，不新建第二套入口。
  - 空态：query 非活跃时保留「本月还没有记账」加「记一笔」；query 活跃时改为「没有符合条件的账单」且不渲染动作按钮。
- **Acceptance Criteria**：
  - 长分类加长标签的行中，渠道名以独立 Text 渲染（stream-row-note-1）且其矩形右缘不超过行右缘。
  - 390dp 下描述保持单行省略；短元信息行的行高与改动前持平（±4dp），长分类加长标签的行折为两行且标签与时间完整显示（不出现省略号）；320dp 加 2 倍字体无 RenderFlex 溢出。
  - 条件生效时列表头出现摘要文案且不再是月份文案；清空条件后恢复月份文案。
  - 空态文案随 query.isActive 切换；既有日小计、删除确认、编辑跳转用例不回归。

---

## Phase 4：筛选面板与搜索入口

### TASK-007：四维筛选面板（类型/分类/标签/支付渠道）

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-006
- **Description**：用底部草稿面板替换类型单选 picker，提供类型、分类、标签、支付渠道四个维度与「重置/应用」。
- **Details**：
  - 在 stream_screen.dart 内新增 _openFilter：先建 ValueNotifier<TransactionQuery> draft（初值为 ledger.query），再调用 showLedgerPicker<TransactionQuery>，title 为「筛选」，children 为 Padding(padding: EdgeInsets.symmetric(horizontal: 12)) 包裹的 _StreamFilterBody（传 draft、ledger.categories、ledger.channels；showLedgerPicker 滚动区自带 8dp 水平内边距，补 12dp 后与标题「筛选」及底部按钮共同对齐在 20dp），footer 用 ValueListenableBuilder 监听 draft 渲染「重置」TextButton（key stream-filter-reset，点击后 draft 变为仅保留关键词的新查询）与「应用」FilledButton（key stream-filter-apply，点击后 pop 当前草稿）；await 返回后 dispose draft，非空结果则 await ledger.setQuery(applied)。
  - _StreamFilterBody：分组标签（沿用统计页 _FilterSectionLabel 的 labelLarge 加 w600 样式）与 ChoiceChip(showCheckmark: false) 的 Wrap，间距 8；分组顺序为 类型 → 分类 → 标签 → 支付渠道。
  - 类型：全部（key stream-filter-type-all）加 TransactionType.values（key 为 stream-filter-type- 加枚举名，label 取 TransactionType.label）。
  - 分类：随草稿类型收敛——type 为空时列 全部分类（key stream-filter-category-all）加支出分类再加收入分类（先支出后收入）；type 为支出只列支出分类；type 为收入只列收入分类；type 为转账或还款时整组不渲染；key 为 stream-filter-category- 加 id（全部为 all）；改选分类时清空 tagId。
  - 类型与分类/标签的联动：切换类型后若草稿 categoryId 不在收敛后的可选列表内（含类型变为转账或还款），一并清空 categoryId 与 tagId，避免构造出 type 与 category_id 恒空的组合（支出仅关联支出分类、收入仅关联收入分类、转账与还款固定绑定系统分类）。
  - 标签：仅在已选分类且该分类 tags 非空时渲染本组与标题（全部标签 key stream-filter-tag-all，加该分类标签 key 为 stream-filter-tag- 加 id）；未选分类或该分类无标签时整组与标题都不渲染，不使用任何引导文案。
  - 支付渠道：全部渠道（key stream-filter-channel-all）加 channels 接口顺序（key 为 stream-filter-channel- 加 id）。
  - 筛选入口：纯图标按钮（仅 Icons.filter_alt_outlined，48dp 触达，tooltip 为「筛选」，不渲染文字与下拉箭头）；query.hasDimensions 为真时底色 secondaryContainer、前景 onSecondaryContainer，否则 surfaceContainerHigh 与 onSurface；key 保持 stream-filter-menu。
- **Acceptance Criteria**：
  - 面板可打开；未选分类时只有 类型 / 分类 / 支付渠道 三组，不出现任何引导文案；选中某分类后标签组出现，未选分类时不出现「全部标签」。
  - 类型选「转账」或「还款」时分类与标签两组整体隐藏，若此前已选分类与标签则草稿同步清空；类型选「支出」时分类组不含收入分类，选「收入」时不含支出分类。
  - 分组标题与 ChoiceChip 的左缘 x 坐标与面板标题「筛选」及底部「重置」按钮一致（20dp，±0.5）。
  - 选择「支出 + 某分类 + 某标签 + 某渠道」后点「应用」：面板关闭、列表头摘要按固定顺序呈现、只发起一次带全部参数的流水请求。
  - 「重置」后四个维度回到未选状态且关键词保留；点遮罩关闭不改变已应用的查询。
  - 入口按钮只渲染 filter_alt_outlined 图标（无文字与下拉箭头）且触达高度不小于 48dp；条件生效时使用 secondaryContainer 底色，条件清空后恢复默认底色；320dp 加 2 倍字体下面板可滚动到底部按钮。

### TASK-008：搜索入口（防抖内联搜索框）

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-007
- **Description**：在列表头提供搜索图标与同行内联搜索框，关键词作为查询的一维，300ms 防抖后上送。
- **Details**：
  - _ListHeader 改为 StatefulWidget：状态为 bool _searching、TextEditingController 控制器、Timer? _debounce；dispose 释放控制器与定时器。
  - 收起态左槽为摘要或月份文本加 IconButton（key stream-search-toggle，图标 Icons.search，tooltip「搜索」）；点击后 _searching 置真并 requestFocus。
  - 展开态左槽换成 TextField（key stream-search-field，autofocus，textInputAction 为 search，decoration 的 hintText 为「搜索账单」、prefixIcon 为 Icons.search、suffixIcon 为 IconButton（key stream-search-clear，图标 Icons.close_rounded））。
  - onChanged：先 cancel 上一个定时器，再起 300ms 定时器提交 query.withKeyword(输入文本)；onSubmitted 立即提交并取消定时器。
  - stream-search-clear 行为：两个分支都先 _debounce?.cancel()，再分派——控制器文本非空时清空并立即提交空关键词且保持展开；文本为空时收起搜索并 unfocus。取消挂起定时器避免清空后旧关键词被回填。
  - 搜索不改动其它维度；筛选面板的「重置」不清空关键词。
- **Acceptance Criteria**：
  - 300ms 内连续输入多次只发起一次流水请求，q 参数为最后一次输入（已去空白）。
  - 回车提交立即生效；清空后列表回到无条件结果；空输入点击后缀按钮收起搜索且列表头恢复摘要或月份。
  - 输入后 300ms 内立即点击清空：不发起携带旧关键词的请求，列表回到无条件结果。
  - 搜索展开时筛选胶囊仍可见可点；搜索态下筛选生效后，收起搜索可见完整摘要。
  - 320dp 加 2 倍字体下搜索框与筛选胶囊同行不溢出。

### TASK-009：流水页筛选与搜索用例补齐

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-008
- **Description**：改写既有筛选用例并补齐新的筛选与搜索交互、窄屏与深色用例。
- **Details**：
  - app/test/features/stream_screen_test.dart：把 filter-menu 与 filter-expense 相关断言迁移为 stream-filter-menu 与 stream-filter-type-expense 契约；新增分组渲染与类型收敛（转账与还款隐藏分类和标签、支出不含收入分类、未选分类无标签组与引导文案）、分组左缘与标题及底部按钮对齐、应用后请求参数与摘要、重置保留关键词、搜索展开与清空与收起、300ms 防抖、清空时取消挂起定时器、筛选态空态文案、行右栏 note 的存在与矩形、长标签元信息折行且不省略、320dp 加 2 倍字体打开面板滚动到底部按钮、深色主题渲染无异常。
  - app/test/core/api_client_test.dart：getTransactions 新签名的参数拼装用例（含未设置维度不上送、关键词裁剪）。
  - app/test/core/ledger_controller_test.dart：setQuery 去重、条件不写快照、三类维度剪枝、clear() 复位。
  - 使用 harness 的 MockClient 与固定时间，不依赖真实网络与系统时间；用例不残留 pumpAndSettle 超时。
- **Acceptance Criteria**：
  - 新增与改写用例全部通过，flutter test 无失败、无挂起；总项数记录在 Project.md。
  - 防抖用例断言「三次输入只发一次 /api/transactions 请求」。
  - 320dp 加 2 倍字体与深色用例 tester.takeException() 为 null，关键文本与按钮矩形在视口内。

---

## Phase 5：门禁、文档、归档与提交

### TASK-010：Go 与 Flutter 全量门禁

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-009
- **Description**：执行全量构建与测试门禁并记录结论。
- **Details**：
  - 依次执行：go test ./...、make app-format、make app-analyze、make app-test、make app-web（Makefile 已导出仓库内 .pub-cache）。
  - 记录每条命令的退出码、flutter analyze 输出与测试项数；app/build/web 若由本次生成，通过后删除；执行前已存在则保留原状。
  - 门禁失败时修复后重跑对应命令，并复跑受影响的相邻项，不跳过。
- **Acceptance Criteria**：
  - 五条命令退出码均为 0；flutter analyze 输出 No issues found。
  - 测试项数与实际一致，并记录在 Project.md。
  - 工作区不残留本轮构建产物（app/build/web）。

### TASK-011：Project.md 同步

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-010
- **Description**：把本轮落地事实写入 .docs/Project.md。
- **Details**：
  - 结构段：更新 internal/server/transactions.go、app/lib/core/api/models.dart、app/lib/core/api/api_client.dart、app/lib/core/state/ledger_controller.dart、app/lib/features/stream/ 的描述（列表查询五维与关键词、TransactionQuery、行信息双槽、搜索与筛选面板）。
  - Android 客户端数据段：补充查询五维、筛选草稿态、关键词防抖、快照仅写全量结果、配置刷新剪枝失效维度。
  - 测试段：追加本轮新增用例数与日期，保留既有历史记录。
  - 已知限制：流水仍为「最近 N 条」窗口（服务端先筛选后 LIMIT，不分页）；关键词 LIKE 无索引；查询状态不跨启动持久化。
  - 不改写历史决策记录的既有事实，不写计划口吻。
- **Acceptance Criteria**：Project.md 描述与代码实际状态一致，逐条可在源码中核对。

### TASK-012：归档与白名单提交

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-011
- **Description**：按工作流归档 Plan 与 Tasks，并只提交本轮相关文件。
- **Details**：
  - 归档目录按执行日计算 .docs/MM-DD-vN/：同日已有目录取最大 N 加 1；把根目录 Plan.md 与 Tasks.md 移入，并在两份文件中标注 DONE、补完成日期与回归结论。
  - git status、git diff、git log -5 核对；使用 git commit --only -- 白名单提交：internal/server/transactions.go、internal/server/server_test.go、app/lib/core/api/models.dart、app/lib/core/api/api_client.dart、app/lib/core/state/ledger_controller.dart、app/lib/features/stream/、app/test/、temp/stream-filter-search-demo.html、.docs/Project.md、.docs/MM-DD-vN/。
  - 提交信息使用 feat(app): 前缀加中文说明，聚焦「为什么」。
  - 提交本轮采纳原型 temp/stream-filter-search-demo.html；不提交既有暂存技能目录、.pi 删除、temp 截图与未采纳原型（ledger-ui-variant-a.html）、构建产物、临时数据库；不使用 git add -A、git reset、--no-verify。
- **Acceptance Criteria**：
  - .docs/MM-DD-vN/ 同时含 Plan.md 与 Tasks.md，且根目录无残留。
  - git show --stat HEAD 只含白名单文件；既有暂存技能文件状态未被改变。
  - 提交信息符合 Conventional Commits 中文约定。
