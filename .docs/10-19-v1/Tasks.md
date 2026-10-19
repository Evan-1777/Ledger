# Tasks：Ledger Android（Flutter + Material 3）

**关联 Plan**：Plan.md —— Ledger Android v1.2
**总计 Task**：26 个
**状态**：DONE（2026-10-19 完成，26/26）
**完成日期**：2026-10-19
**回归测试结论**：Dart 格式 0 变更；`flutter analyze` 零 issue；`flutter test` 77 项通过；`flutter build web` 成功；`go test ./...` 与 Go 构建通过；Web 真实后端自检通过；CI 未推送运行，Android 待 CI/真机验收。

> 所有 Task 的 Executor 均为主线；本轮不派发 Subagent。任务依赖未满足时不得开始。

---

## Phase 1：工程基础、鉴权与 Shell

### TASK-001：初始化 Flutter 工程与依赖锁定

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `app/` 创建仅含 Android 与 Web 平台的 Flutter 工程，搭建双端依赖与测试基线；模板页面保留到 TASK-002 再替换。
- **Details**：
  - 本地 Flutter 位于 `/home/dev/flutter/bin/flutter`，当前 PATH 未包含；执行前导出 `PATH=/home/dev/flutter/bin:$PATH`，并在仓库根导出 `PUB_CACHE="$PWD/.pub-cache"`。当前 `~/.pub-cache` 不可写且未缓存 flutter_secure_storage；SDK cache 与 pub cache 是两处独立写入。SDK cache 被拒绝时申请一次命令级授权，不复制或重装 SDK。
  - `flutter create --platforms=android,web --org com.evan1777 --project-name ledger_app app`。
  - 应用显示名 `Ledger`，applicationId 与 Android namespace 均为 `com.evan1777.ledger`，MainActivity 包名同步迁移，版本 `1.0.0+1`，minSdk 24（Flutter 3.44 默认，flutter_secure_storage 11 要求 ≥24）。
  - 依赖：`flutter_localizations`（SDK）、`intl`、`http`、`provider`、`shared_preferences`、`flutter_secure_storage`；dev 依赖保留 `flutter_test`、`flutter_lints`。版本以解析结果为准并提交 `pubspec.lock`。
  - 保留模板计数器与默认测试至 TASK-002，避免 TASK-001 出现空测试；TASK-002 再用 LedgerApp smoke test 替换。删除无消费的注释；不添加路由、图表、代码生成依赖。
  - 启用 `flutter_lints`，保留默认推荐规则。
- **Acceptance Criteria**：
  - `cd app && flutter pub get` 成功。
  - `flutter analyze` 零 issue。
  - `flutter test` 通过（使用模板默认测试；TASK-002 替换为 LedgerApp smoke test）。
  - `flutter build web` 成功。
  - `app/pubspec.lock` 已提交。
- **Dependencies**：无
- **Priority**：P0

### TASK-002：建立 MD3 主题、金融语义色与本地化

- **Status**：DONE
- **Executor**：主线
- **Description**：以品牌蓝为 seed 建立 Material 3 浅/深色主题、金融语义 ThemeExtension、组件主题和中文 Material 本地化。
- **Details**：
  - `lib/core/theme/app_theme.dart`：`ColorScheme.fromSeed(seedColor: Color(0xFF0078D4))` 生成浅色与深色方案；`useMaterial3: true`。
  - `lib/core/theme/finance_colors.dart`：`ThemeExtension` 定义支出、收入、转账、还款的主色/容器色/文字色，以及 5 档图表色；深浅各一套，对比度满足正文 4.5:1。
  - 组件主题：Card 16dp、Hero 28dp、Dialog/BottomSheet 28dp、主按钮全圆角、FAB 16dp；NavigationBar、FilledButton、OutlinedButton、Chip、TextField、SnackBar、AppBar、Dialog、BottomSheet 统一由主题驱动。
  - 字体：默认 Roboto/系统中文字体回退，不加载网络字体；金额文本启用 `FontFeature.tabularFigures()`；不全局强制字体。
  - `main()` 在 `runApp` 前调用 `initializeDateFormatting('zh_CN')`，避免 `DateFormat` 在中文 locale 抛 `LocaleDataException`。
  - 将模板 `main.dart` 替换为 `runApp(const LedgerApp())`；`lib/app.dart` 提供最小 `LedgerApp`（`MaterialApp` + 占位 Scaffold），TASK-005 再接入 Gate。
  - `MaterialApp` 注入 `GlobalMaterialLocalizations`、`GlobalWidgetsLocalizations`、`GlobalCupertinoLocalizations`，`supportedLocales: [Locale('zh', 'CN')]`，`locale: Locale('zh', 'CN')`；`themeMode` 先固定 `ThemeMode.system`，TASK-004 接入 `PreferencesController` 后再改为监听。
  - 将 `test/widget_test.dart` 替换为 `test/app_smoke_test.dart`，pump `LedgerApp` 并断言无异常；不保留无断言空测试。
  - 按浅/深主题设置状态栏与导航栏图标亮度；不修改系统栏颜色为硬编码。
- **Acceptance Criteria**：
  - `grep -R "Color(0x" app/lib` 仅命中主题文件。
  - 浅色/深色各有一个 Widget 测试可 pump，无异常。
  - 文案显示中文 Material 组件标签（日期选择器、对话框按钮）。
  - 文本缩放 2.0 下基础 Shell 无 RenderFlex overflow。
- **Dependencies**：TASK-001
- **Priority**：P0

### TASK-003：定义 API 模型与集中式 HTTP 客户端

- **Status**：DONE
- **Executor**：主线
- **Description**：实现与 Go 后端一致的 Dart 模型、请求序列化、统一错误映射和按场景分流的 401 处理。
- **Details**：
  - `lib/core/api/models.dart`：PaymentMethod、Category、Tag、Transaction、StatsSummary、AssetSummary、各分布与趋势模型；枚举覆盖 expense/income/repayment/transfer 与 asset/liability/system；提供 `fromJson` 与按需 `toJson`。
  - `lib/core/api/api_client.dart`：方法覆盖登录、鉴权检查、渠道/分类/标签 CRUD、流水 CRUD、统计汇总；统一 `Content-Type: application/json`、Bearer Token、15 秒超时。
  - `lib/core/api/api_exception.dart`：区分 400/401/409/500、网络不可达、超时、JSON 解析失败；401 映射为 `ApiException.unauthorized`，由调用方按登录/启动检查/受保护请求分流，不在客户端注册全局清 Token 回调；不把 Token 写入异常或日志。
  - 服务器地址规范化：去首尾空白、去尾部 `/`、仅接受 http/https、拒绝 query/fragment 与非根路径；请求 URL 固定为 `origin + /api/...`，与现有 Web 客户端一致。
  - 流水列表固定 `limit=100`，筛选映射为 `type`；统计与配置接口不接受未知参数。
  - 请求体仅发送后端已声明字段；编辑时保留类型锁定语义所需字段。
- **Acceptance Criteria**：
  - 使用 `http/testing` 的 MockClient 覆盖每个端点、登录 401、受保护请求 401、409、超时与非法 JSON。
  - 断言 Authorization 头、Content-Type、查询参数与请求体。
  - 服务器地址 `https://host/` 生成 `https://host/api/...`；带路径的地址被拒绝并提示只填协议、域名与端口。
  - 登录调用方将 401 映射密码错误；启动 check/受保护请求将 401 映射会话过期；网络/超时不映射为会话过期；异常消息不含 Token。
- **Dependencies**：TASK-001
- **Priority**：P0

### TASK-004：实现安全会话、偏好存储与三个控制器

- **Status**：DONE
- **Executor**：主线
- **Description**：建立 Token/服务器地址持久化、偏好持久化、会话状态机与账本数据控制器，供 UI 注入。
- **Details**：
  - `lib/core/storage/session_store.dart`：Token 使用 `flutter_secure_storage`；服务器地址使用 `shared_preferences`；定义接口并在测试中提供内存实现。
  - `lib/core/storage/preferences_store.dart`：themeMode、hideAmounts 的读写；默认跟随系统、金额显示。
  - Web 端 secure storage 仅在 HTTPS/localhost 安全上下文可用；非安全上下文在连接页提示，不降级为明文存储。
  - `lib/features/auth/session_controller.dart`：状态为 booting/locked/authenticated；`restore` 读取地址与 Token 后调用 `/api/auth/check`；`login` 先写入规范化后的服务器地址，再调用登录接口，401 只返回密码错误，不清除已有 Token，失败保留地址供重试；restore/check 的 401 清 Token 并回到 locked；网络/超时保留 Token 并暴露可重试错误；`logout`、`updateServer`。
  - `ApiClient` 通过构造注入的 `String Function() baseUrl` 与 `Future<String?> Function() tokenProvider` 读取当前会话；SessionController 更新 SessionStore，下一次请求自然命中新地址；ApiClient 实例保持稳定，不重建，不直接读 secure storage。
  - `lib/core/state/ledger_controller.dart`：持有 categories、paymentMethods、transactions、stats、filter、各加载/错误状态；登录后并行加载配置、流水、统计；受保护请求遇到 401 时调用 `SessionController.expire()` 并清空业务数据；不自行维护 Token。
  - `lib/core/state/preferences_controller.dart`：主题、金额隐藏、持久化；服务器地址不放这里。
  - 在 `lib/app.dart` 根部监听 `PreferencesController`，把 `themeMode` 接到 `MaterialApp`；TASK-002 的固定 `ThemeMode.system` 仅作过渡。
  - release 模式校验服务器地址必须为 HTTPS；debug 允许 http。
- **Acceptance Criteria**：
  - 单元测试覆盖 restore 成功/失败（401 vs 网络）、登录成功/密码错误、登出清空、更换服务器清 Token 且下一次请求命中新 host。
  - 偏好控制器切换主题与隐藏金额后写回并通知监听者。
  - 账本控制器在 401 后清空业务数据，不把旧数据带到下一次登录。
- **Dependencies**：TASK-003
- **Priority**：P0

### TASK-005：实现连接/解锁页与启动 Gate

- **Status**：DONE
- **Executor**：主线
- **Description**：新增可连接任意 Ledger 服务器的登录页，以及启动时的会话检查与错误重试。
- **Details**：
  - `lib/features/auth/login_screen.dart`：服务器地址、管理员密码、显示/隐藏密码、提交按钮、内联错误；服务器地址预填已保存值；首次启动为空；不内置默认地址。
  - 密码错误显示「密码错误」；网络错误显示「无法连接服务器，请检查地址与网络」；release 下 http 地址直接提示「正式版仅支持 HTTPS」。
  - 错误提示与日志不回显完整服务器地址；真实地址不进入仓库或验收截图。
  - 提交期间按钮进入加载态并禁用重复提交；失败保留服务器地址与已填内容，便于直接重试。
  - 启动时显示品牌化的启动态；check 401 进入登录页，网络/超时显示重试并保留 Token，不闪现业务页面。
  - `lib/app.dart` 的 Gate 根据会话状态切换启动页/登录页/Shell；不使用命名路由。
  - 不添加欢迎语、引导步骤或功能解释。
- **Acceptance Criteria**：
  - Widget 测试覆盖空地址、非法地址、错误密码、网络错误与成功回调。
  - 首次启动无预置服务器地址；网络错误提示不含完整地址。
  - 成功登录后只触发一次配置/流水/统计加载。
  - 启动时已有有效 Token 直接进入 Shell，过期 Token 回登录页；网络失败保留 Token 并可重试。
  - 320dp 宽与文本缩放 2.0 无溢出。
- **Dependencies**：TASK-002、TASK-004
- **Priority**：P0

### TASK-006：实现 App Shell、主导航与共享构件

- **Status**：DONE
- **Executor**：主线
- **Description**：建立四段主导航、FAB、页面容器与可复用的 MD3 原子构件。
- **Details**：
  - `lib/features/shell/app_shell.dart`：手机宽度使用 `NavigationBar`，四项为流水/统计/资产/设置；`IndexedStack` 保持页面状态；本轮不做 `NavigationRail` 或平板断点。
  - 常驻 `FloatingActionButton.extended`（记账），位于导航栏上方，不遮挡列表最后一项；按当前 tab 保持可见。
  - 暴露 `openSettings(section)` 回调，供资产页「管理」跳转；切换设置分区时重置滚动/菜单状态。
  - `lib/core/widgets/`：`LedgerCard`、`AmountText`、`TypeIcon`、`SectionHeader`、`EmptyState`、`ErrorState`、`SkeletonList`、`ConfirmDialog`、`showLedgerSnackBar`。
  - 所有图标按钮提供语义标签；可点击目标至少 48dp；不使用装饰性 emoji 或占位文案。
  - 页面使用 `SafeArea` 与 `MediaQuery.viewPadding`，为 edge-to-edge 留出空间。
- **Acceptance Criteria**：
  - Widget 测试在 360×800 与 320×800 下导航可用且无溢出。
  - 四个 tab 切换保留各自滚动位置（占位页可验证状态）。
  - FAB 点击打开占位记录弹层回调；语义树包含四个导航标签与 FAB 标签。
  - 共享构件均有独立 Widget 测试或 golden-free pump 测试。
- **Dependencies**：TASK-002、TASK-005
- **Priority**：P0

### TASK-007：为后端增加可选的开发 CORS

- **Status**：DONE
- **Executor**：主线
- **Description**：增加默认关闭的单 Origin CORS 支持，使 Flutter Web 开发服务器可访问 Go API，不改变业务端点。
- **Details**：
  - `internal/config/config.go` 新增 `CORSOrigin`，读取 `LEDGER_CORS_ORIGIN`，默认空。
  - `internal/server/cors.go` 提供 `CORS(origin string, next http.Handler) http.Handler`：精确匹配 Origin，返回 `Access-Control-Allow-Origin`、`Vary: Origin`、`Access-Control-Allow-Headers: Content-Type, Authorization`、`Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS`；OPTIONS 返回 204；未配置时不添加头。
  - `cmd/server/main.go` 在配置非空时包裹 handler；默认生产行为不变。
  - `internal/server/cors_test.go` 覆盖允许、拒绝、预检、未配置四种情况。
- **Acceptance Criteria**：
  - `go test ./...` 通过。
  - 未设置环境变量时响应头不含 CORS 字段。
  - 允许的 Origin 收到完整头，OPTIONS 204。
  - 不修改任何业务 API 路径或响应体。
- **Dependencies**：无
- **Priority**：P0

### TASK-008：配置 Android 清单、签名骨架与 Android CI

- **Status**：DONE
- **Executor**：主线
- **Description**：配置 Android 网络/备份/返回键策略、条件签名与 GitHub Actions APK 构建。
- **Details**：
  - `AndroidManifest.xml`：仅声明 INTERNET；`android:allowBackup="false"`；`android:enableOnBackInvokedCallback="true"`；应用标签 Ledger；debug manifest 允许明文 HTTP，release 不允许。
  - `android/app/build.gradle.kts`：minSdk 24（Flutter 3.44 默认，flutter_secure_storage 11 要求 ≥24）、applicationId、从 `key.properties` 读取 release signingConfig；文件不存在时不使用 debug 签名冒充 release。
  - `.github/workflows/android.yml`：路径过滤 `app/**` 与工作流文件；`workflow_dispatch`；JDK 17；固定 Flutter 3.44.6；执行 format check、analyze、test；有 keystore secrets 时构建 release，否则构建 debug；上传 APK artifact，命名区分 debug/release。
  - `.gitignore` 增加 `key.properties`、`*.jks`、`*.keystore`、`.pub-cache/`、Flutter 构建产物；`.dockerignore` 增加 `app/` 与 `.pub-cache/`，避免 Flutter 构建上下文进入单二进制 Docker 构建；不生成或提交任何密钥。
  - 根 `Makefile` 增加 `app-analyze`、`app-test`、`app-web`、`app-dev` 目标，使用 `FLUTTER ?= flutter`；设置并导出 `PUB_CACHE ?= $(CURDIR)/.pub-cache`，与 TASK-001 的环境约定一致。
- **Acceptance Criteria**：
  - release 模式清单不含明文 HTTP 许可；debug 模式允许。
  - 工作流 YAML 可解析，步骤顺序正确；无 Secrets 时构建 debug，有 Secrets 时构建 release。
  - `make app-analyze FLUTTER=/home/dev/flutter/bin/flutter`、`make app-test FLUTTER=/home/dev/flutter/bin/flutter` 可执行；`FLUTTER ?= flutter` 保持可覆盖。
  - 仓库中无密钥文件；工作流配置可解析，真实 APK 下载留到 TASK-026 推送后验证。
- **Dependencies**：TASK-001
- **Priority**：P0

---

## Phase 2：流水与记账闭环

### TASK-009：实现流水纯逻辑与账本控制器

- **Status**：DONE
- **Executor**：主线
- **Description**：完成本地日期分组、日小计、元信息、金额符号与流水/统计加载和变更刷新。
- **Details**：
  - `lib/features/stream/stream_utils.dart`：本地日期 key、今天/昨天/跨年日期头、星期、日小计（排除转账/还款）、元信息（分类、标签、渠道箭头、手续费、时间）、金额符号。
  - 月度头条直接消费 `stats.monthExpense`、`stats.monthIncome`、`stats.monthBalance`，不再拉取第二份未筛选流水。
  - `LedgerController` 增加 filter（all/expense/income/transfer/repayment）、`loadTransactions`、`refreshAll`、`refreshStats`、`refreshConfig`；筛选切换只重拉列表。
  - 流水加载使用请求序号守卫：每次筛选/刷新递增 generation，只有最新请求的响应可写回，旧响应直接丢弃。
  - 交易增删改后刷新流水与统计；分类/标签/渠道变更后刷新配置，渠道变更额外刷新统计。
  - 请求失败保留旧数据并暴露可重试错误；受保护请求 401 交由会话控制器 expire，登录 401 不进入此处。
  - 交易列表的 `amount_cents`/`fee_cents` 用于展示与校验；表单输入解析为整数分后，提交时按后端契约换算为 `amount`/`fee` 浮点；统计与资产接口只有浮点字段，模型保留 double 并在格式化层统一舍入，不假设不存在的 cents 字段。
- **Acceptance Criteria**：
  - 纯函数测试覆盖今天/昨天/跨年、空列表、转账/还款排除、手续费元信息。
  - 筛选切换请求参数正确，列表与头条解耦；快速切换时旧响应不覆盖新结果。
  - 交易变更后流水与统计均刷新一次；失败不白屏。
- **Dependencies**：TASK-003、TASK-004、TASK-006
- **Priority**：P0

### TASK-010：实现流水页

- **Status**：DONE
- **Executor**：主线
- **Description**：构建 MD3 流水主画布，包含月度头条、筛选、按日分组列表、行操作与完整状态。
- **Details**：
  - `lib/features/stream/stream_screen.dart`：`CustomScrollView` + `SliverAppBar.large` 标题「流水」。
  - 月度头条：当月支出、收入、结余；Hero 使用大号 `¥`，行内金额保留紧凑符号；收入/支出比例条在分母为 0 时不渲染。
  - `FilterChip` 五档：全部/支出/收入/转账/还款；选中态使用 MD3 样式；切换触发加载。
  - 按日 `LedgerCard`：日期头、星期、日支出/收入小计、行列表；行内类型图标、描述、元信息、带符号金额、溢出菜单（编辑/删除）。
  - 空态「本月还没有记账」+「记一笔」；加载骨架保持头条节奏；错误态提供重试；支持下拉刷新。
  - 删除入口只触发回调，确认由 TASK-013 的共享对话框完成。
- **Acceptance Criteria**：
  - Widget 测试覆盖空态、加载态、分组顺序、金额颜色/符号、筛选点击。
  - 320dp 与 2.0 文本缩放无溢出；长描述可截断不撑破行。
  - 行菜单的编辑/删除回调携带正确交易对象。
- **Dependencies**：TASK-006、TASK-009
- **Priority**：P0

### TASK-011：实现记账弹层与支出/收入录入

- **Status**：DONE
- **Executor**：主线
- **Description**：实现全高 MD3 bottom sheet，完成支出与收入的新建、编辑、分类标签选择和基础校验。
- **Details**：
  - `lib/features/record/record_sheet.dart`：`showModalBottomSheet`，`isScrollControlled`、`useSafeArea`、drag handle、固定底部操作栏。
  - 四段 `SegmentedButton` 类型；编辑已有交易时禁用类型切换。
  - 金额输入为大号 `TextField`，`prefixText: '¥'`，decimal 键盘，仅允许数字与一个小数点；提交金额必须 >0。
  - 用途说明必填；分类/标签字段在原 sheet 内联展开，按收入/支出过滤，选中分类后展示其标签；不新增 `category_picker_sheet.dart`，不叠第二层 modal。
  - 渠道选择使用 `ChoiceChip` 网格；收入只显示资产渠道，支出显示全部；日期时间使用 `showDatePicker` + `showTimePicker`，默认当前时间。
  - 保存调用控制器创建/更新；失败保留全部草稿并在表单内或 SnackBar 显示错误；成功后关闭并刷新。
- **Acceptance Criteria**：
  - Widget 测试覆盖空金额、空说明、未选分类、成功创建、服务端失败保留草稿。
  - 支出提交金额为负数，收入为正数；时间以 UTC ISO 发送。
  - 编辑时类型控件禁用，字段预填正确。
  - 键盘遮挡时底部按钮仍可滚动到达；分类/标签展开与收起不创建新路由，返回键只关闭记账 sheet。
- **Dependencies**：TASK-009
- **Priority**：P0

### TASK-012：实现转账、还款与手续费

- **Status**：DONE
- **Executor**：主线
- **Description**：扩展记账弹层，覆盖双向资产转账、负债还款、手续费和系统分类约束。
- **Details**：
  - 转账：转出/转入仅列资产渠道，互斥选择，不得相同；少于 2 个资产渠道时禁用提交并提示先添加渠道；手续费默认折叠，展开后仅接受非负数，收起时按 0 处理。
  - 还款：还入仅列负债渠道；转出列资产渠道并提供「外部/未记录资金」选项；无负债渠道时禁用提交并提供跳转设置。
  - 系统分类/标签按 `type=system` 与固定名称匹配并自动带入；用户不可编辑这两类记录的分类。
  - 提交体：转账 `type=transfer`、`payment_method_id=转入`、`source_payment_method_id=转出`、`fee`；还款 `type=repayment`、目标负债、来源可空。
  - 类型切换时重置不兼容的渠道与分类，避免残留非法组合。
- **Acceptance Criteria**：
  - 纯规则测试覆盖四类目标渠道、同账户拦截、无渠道禁用、手续费为 0/正数/非法。
  - Widget 测试验证转账互斥、手续费展开与收起、还款外部资金来源。
  - 请求体字段与后端契约一致，不发送无关的 source/fee。
- **Dependencies**：TASK-011
- **Priority**：P0

### TASK-013：接通编辑、删除确认与刷新链路

- **Status**：DONE
- **Executor**：主线
- **Description**：将流水行操作接入编辑弹层、删除确认、错误提示和数据刷新。
- **Details**：
  - 编辑：点击行或菜单「编辑」打开已预填的记账弹层；保存调用更新接口。
  - 删除：共享 `ConfirmDialog` 显示「删除账单」「删除后该笔记录不可恢复。」与交易摘要；确认后调用删除接口。
  - 成功后 SnackBar「账单已删除」/「账单修改成功」/「记账成功」；刷新流水与统计。
  - 失败保留当前页面与数据，显示后端可读错误；引用冲突 409 由设置页删除流程处理。
  - 删除请求期间确认按钮加载并禁止重复提交。
- **Acceptance Criteria**：
  - Widget 测试覆盖确认、取消、失败、成功四种路径。
  - 删除成功后列表与统计刷新各一次；取消不产生请求。
  - 请求期间重复点击只发送一次。
- **Dependencies**：TASK-010、TASK-012
- **Priority**：P0

---

## Phase 3：统计与资产

### TASK-014：实现统计派生与自绘图表

- **Status**：DONE
- **Executor**：主线
- **Description**：完成统计页所需的纯派生逻辑，以及环形图、趋势图的 CustomPainter 和文字图例。
- **Details**：
  - `lib/features/stats/stats_utils.dart`：日均花费（当月天数或已过天数口径与 Web 一致，取 `max(1, 当前日)`）、环比（上月为 0 时返回 null）、结余符号、收支比例分母为 0 的处理。
  - `lib/features/stats/charts.dart`：环形图按分类金额分段，中心显示支出合计；图例可点击选中分类并显示标签明细；趋势图绘制近 6 月支出/收入双线、网格、月份标签与末端强调点。
  - 图表颜色来自 `FinanceColors`，不在 painter 内硬编码。
  - 图表外层提供 `Semantics` 标签；图例以文字列出金额与百分比，不依赖颜色单独传达。
  - 数据为空或总额为 0 时不绘制 NaN/Infinity，退回空态。
- **Acceptance Criteria**：
  - 纯函数测试覆盖零分母、负结余、上月为 0、空趋势。
  - Widget 测试 pump 环形图/趋势图，320dp 与 2.0 文本缩放无异常。
  - 选中图例后显示对应分类标签明细；再次点击取消。
- **Dependencies**：TASK-002、TASK-003
- **Priority**：P1

### TASK-015：实现统计页

- **Status**：DONE
- **Executor**：主线
- **Description**：构建 MD3 统计看板，串联结余 Hero、指标、构成、趋势与支付分布。
- **Details**：
  - `lib/features/stats/stats_screen.dart`：`SliverAppBar.large` 标题「统计」。
  - Hero：当月结余、收入、支出、收支比例条、储蓄率 Chip；余额正负使用语义色与符号。
  - 四项指标：本周花费、当月花费（较上月注脚，环比不可计算时不显示百分比）、上月花费、日均花费；2×2 网格在窄屏不溢出。
  - 单张图表卡，顶部以「构成 / 趋势」二段切换：
    - 构成面板：环形图 + 图例 + 选中分类标签明细；空态「当月暂无分类支出」。
    - 趋势面板：近 6 个月收支折线、月份标签与文字图例；空态「暂无趋势数据」。
  - 切换时保留当前月份数据；默认显示构成；图表卡高度稳定，切换不引发布局跳动。
  - 支付途径分布：按金额降序，带比例导轨与百分比；空态「当月暂无渠道支出」。
  - 加载骨架、错误重试、下拉刷新。
- **Acceptance Criteria**：
  - Widget 测试验证 Hero 金额、四项指标、环比零分母降级、空态、构成/趋势切换。
  - 数据与 Go 接口 fixture 一致，不在客户端伪造历史快照。
  - 320dp、深色、2.0 文本缩放无溢出。
- **Dependencies**：TASK-006、TASK-009、TASK-014
- **Priority**：P1

### TASK-016：实现资产派生与资产页

- **Status**：DONE
- **Executor**：主线
- **Description**：构建净资产 Hero、资产分布、资产/负债账户与金额隐藏。
- **Details**：
  - `lib/features/assets/assets_utils.dart`：资产按余额降序，占比分母仅计正余额之和；负债按欠款降序；资产负债率在总资产 ≤0 时为 null；总额度、已用、使用率、可用额度对负欠款与超额使用做夹取。
  - `lib/features/assets/assets_screen.dart`：`SliverAppBar.large` 标题「资产」。
  - Hero：净资产（可为负）、眼睛切换、资产总计、负债总计、资产负债率；下方 10dp 堆叠分布条；负余额账户不驱动分布段。
  - 资产账户卡：图标、名称、占比点、余额、负余额语义色；空态「暂无资产账户」+ 添加。
  - 负债账户卡：欠款、额度、可用、使用率导轨；≥80% 使用警示色；无额度显示「不设额度」。
  - 金额隐藏持久化，仅作用于资产页；金额显示时页面只锚定一次 `¥`。
  - 面板头「管理」调用 Shell 的 `openSettings('channels')`。
- **Acceptance Criteria**：
  - 纯函数测试覆盖负余额、零资产、零额度、超额欠款、空列表。
  - Widget 测试验证隐藏/显示、管理跳转、空态与 320dp 布局。
  - 分布条仅对正余额账户生成分段。
- **Dependencies**：TASK-006、TASK-009
- **Priority**：P1

### TASK-017：接通跨页刷新与设置分区跳转

- **Status**：DONE
- **Executor**：主线
- **Description**：保证交易、渠道与页面导航之间的数据一致性和分区定位。
- **Details**：
  - 交易新增/编辑/删除后刷新流水与统计；统计与资产页读取同一份 `stats`，不各自缓存。
  - 渠道新增/编辑/删除后刷新配置与统计；分类/标签变更只刷新配置。
  - 资产页「管理」→ Shell 设置 tab → 渠道分区；从设置返回资产页时数据不重置。
  - 设置页外部进入时显式设置分区；普通点击设置 tab 重置为分类分区。
  - tab 切换不主动发起请求；数据由登录、业务变更与下拉刷新驱动。
- **Acceptance Criteria**：
  - 控制器测试验证每种变更触发的刷新域。
  - Widget 测试验证资产页到设置渠道分区的跳转与分区重置。
  - 同一份统计对象同时驱动统计与资产，不在页面内二次请求。
- **Dependencies**：TASK-013、TASK-015、TASK-016
- **Priority**：P1

---

## Phase 4：设置、平台细节与可访问性

### TASK-018：实现分类与标签管理

- **Status**：DONE
- **Executor**：主线
- **Description**：完成设置页分类/标签分区、CRUD、调序与系统项保护。
- **Details**：
  - `lib/features/settings/settings_screen.dart`：分区选择「分类与标签 / 渠道与账户」；分类分段「支出 / 收入」。
  - 分类列表：行点击打开标签管理；行尾 `PopupMenuButton` 提供重命名、上移、下移、删除；系统分类单独面板且无修改/删除入口。
  - 新建分类：内联或底部弹层输入，类型继承当前分段；重名在前端预检并展示提示，后端 409/400 同样映射。
  - 重命名支持切换支出/收入类型；调序使用相邻 `sort_order` 交换，失败回滚并刷新。
  - `lib/features/settings/tag_sheet.dart`：全高/半高 bottom sheet，列出当前分类标签，支持新增、重命名、删除；失败保留输入；系统标签只读。
  - 重命名标签的 PUT 请求必须携带当前 `sort_order`；后端 `handleUpdateTag` 将 Name 与 SortOrder 都作为非指针字段解码，省略 `sort_order` 会归零并把标签移到列表最前。
  - 删除统一走 `ConfirmDialog`；被引用返回 409 时提示不可删除。
- **Acceptance Criteria**：
  - Widget 测试覆盖新建、重命名、类型切换、调序、删除确认、系统项保护。
  - 标签重命名请求体包含 `name` 与当前 `sort_order`，列表顺序不变。
  - 重名/409 错误不崩溃且保留编辑状态。
  - 320dp 与 2.0 文本缩放无溢出。
- **Dependencies**：TASK-017
- **Priority**：P1

### TASK-019：实现渠道与账户管理

- **Status**：DONE
- **Executor**：主线
- **Description**：完成资产/负债渠道分组、创建、编辑、删除与额度字段。
- **Details**：
  - `lib/features/settings/channel_sheet.dart`：新建/编辑底部弹层；字段为名称、类型（资产/负债）、资产初始余额或负债初始欠款、授信额度；金额输入 decimal，禁止负数；负债才显示额度字段。
  - 渠道列表按资产/负债分组；行显示名称与额度摘要；菜单提供编辑/删除；删除确认后调用 API，409 映射为引用冲突。
  - 新建时类型由所在分区预选；编辑时保留 `sort_order`；初始余额字段仅在表单显示，不在列表前台展示。
  - 创建/更新成功后刷新配置与统计；删除成功后关闭菜单并刷新。
  - 资产页「管理」进入时默认显示渠道分区。
- **Acceptance Criteria**：
  - Widget 测试覆盖新建资产/负债、编辑、负数校验、删除确认、409 提示。
  - 请求字段与后端一致；类型切换时额度字段显隐正确。
  - 渠道变更后资产页金额刷新。
- **Dependencies**：TASK-018
- **Priority**：P1

### TASK-020：实现主题、服务器与退出设置

- **Status**：DONE
- **Executor**：主线
- **Description**：补齐设置页的低频系统操作，保持界面去噪。
- **Details**：
  - 主题三档：跟随系统/浅色/深色；选择后立即生效并持久化，重启保持。
  - 服务器区显示当前地址；点击修改打开弹层，校验 URL，确认后清除 Token 与业务数据并返回登录页。
  - 不预置默认地址；真实地址不写入构建产物、日志、文档或验收截图。
  - 退出登录：清除 Token、业务数据、当前 tab 回到流水、关闭所有弹层；不删除服务器地址与主题偏好。
  - 设置页底部显示版本号，使用编译常量 `String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0')`；不引入 `package_info_plus`，不添加说明性文案。
  - 不加入关于页、隐私政策、教程等未要求入口。
- **Acceptance Criteria**：
  - Widget 测试覆盖主题切换、服务器更换、退出登录。
  - 更换服务器或退出后不残留旧账本数据。
  - 服务器地址仅保存在用户设备本地偏好；日志与构建产物不包含真实地址。
  - 主题选择在重建 App 后保持。
- **Dependencies**：TASK-019
- **Priority**：P1

### TASK-021：补齐 Android 平台配置、图标与启动体验

- **Status**：DONE
- **Executor**：主线
- **Description**：完善 Android 外观与系统集成，不引入 Android 专属 Dart 代码到 Web 共用层。
- **Details**：
  - 生成自适应启动图标：品牌蓝背景 + 简洁账本/账页前景，提供 `mipmap-anydpi-v26` XML 与必要 PNG fallback；不使用外部图标包。
  - Android 12+ 启动背景使用 `surface` 对应色，避免白闪；应用标签 Ledger。
  - 配置 edge-to-edge 系统栏、状态栏/导航栏图标亮度随主题变化；输入法 `adjustResize`。
  - Android 返回键：优先关闭当前 bottom sheet/dialog，其次从非流水 tab 回到流水，最后退出应用；使用 `PopScope`，不使用 `WillPopScope`。
  - 检查手机横屏与 320dp 窄屏布局；不在 Web 代码中引用 `dart:io`；本轮不实现平板断点。
  - 仅保留 INTERNET 权限；检查 release manifest 不包含明文许可。
- **Acceptance Criteria**：
  - `flutter analyze` 无平台条件编译告警。
  - 图标资源在 Android 8+ 自适应裁切下不变形；启动背景与主题一致。
  - Widget 测试模拟返回键关闭记账弹层并回到流水。
  - 静态检查 release manifest 无 `usesCleartextTraffic="true"`。
- **Dependencies**：TASK-006、TASK-008、TASK-020
- **Priority**：P2

### TASK-022：完成可访问性与窄屏/大字体巡检

- **Status**：DONE
- **Executor**：主线
- **Description**：逐页修复语义、触控目标、对比度与文本缩放问题。
- **Details**：
  - 为图标按钮、图表、分布条、开关补齐 `Semantics`/`tooltip`；装饰图标 `excludeFromSemantics`。
  - 检查 48dp 最小命中区（Flutter 使用 `MaterialTapTargetSize.padded` 或透明命中区）；图标按钮、菜单与 Chip 的视觉尺寸可小于 48dp，但命中区不得小于 48dp；金额、日期、账户名在 2.0 文本缩放下不溢出。
  - 支出/收入/转账/还款语义色与背景对比度满足 WCAG；不仅靠颜色区分类型。
  - 320dp 宽度逐页测试：流水、统计、资产、设置、记账弹层。
  - 深色模式下检查所有表面、分隔线、图表与禁用态。
  - 清理无响应按钮、占位入口、TODO/示例/说明性文案。
- **Acceptance Criteria**：
  - 五个核心页面在 320dp、2.0 文本缩放下无 overflow。
  - 关键操作在语义树中可被定位；TalkBack 顺序符合视觉顺序。
  - 深色模式无硬编码浅色背景或低对比文字。
  - 界面上不出现 TODO、示例数据标签、功能解释或未实现入口。
- **Dependencies**：TASK-021
- **Priority**：P2

---

## Phase 5：验证、CI 与文档

### TASK-023：补齐单元与 Widget 测试

- **Status**：DONE
- **Executor**：主线
- **Description**：形成可在本地与 CI 重复执行的核心测试集，覆盖业务规则与关键交互。
- **Details**：
  - 单元测试：金额格式化、日期分组、流水元信息、统计派生、资产派生、渠道规则、服务器 URL 规范化。
  - API 测试：MockClient 覆盖成功、登录 401、check/受保护请求 401、网络失败、409、超时、非法 JSON、带路径的服务器地址被拒绝。
  - 控制器测试：登录恢复、登出清空、更换服务器后的 host、筛选切换与陈旧响应丢弃、变更刷新域。
  - Widget 测试：连接页、流水空态/筛选、记账支出/转账/还款、编辑锁定、删除确认、系统分类保护、资产隐藏、主题切换。
  - 使用内存存储与假 API，不依赖真实网络、时间或设备；日期测试注入 `Clock` 或固定 now。
  - 不引入 golden 测试或第三方测试框架。
- **Acceptance Criteria**：
  - `flutter test` 全部通过，无 skipped 用例。
  - 核心纯函数分支覆盖：零分母、负余额、空列表、登录/会话 401、网络失败、409、超时。
  - 覆盖标签重命名请求体保留 `sort_order`、换服务器后下一次请求命中新 host。
  - 测试不写入真实 SharedPreferences、Secure Storage 或网络。
- **Dependencies**：TASK-013、TASK-015、TASK-017、TASK-022
- **Priority**：P1

### TASK-024：执行 Flutter Web 与本地后端联调自检

- **Status**：DONE
- **Executor**：主线
- **Description**：在本机用临时数据库启动 Go 服务与 Flutter Web，验证真实 API 链路与 CORS。
- **Details**：
  - 使用临时 `LEDGER_DB_PATH` 与测试管理员密码启动后端；设置 `LEDGER_CORS_ORIGIN=http://localhost:5174`；不使用生产数据库。
  - 用 `flutter run -d web-server --web-port 5174` 固定端口，连接用户提供的 9222 Chrome 实例；不可用时仅用一次性无头 Chrome 做页面加载与截图，不启动长期浏览器。
  - 走通：登录 → 创建支出/收入/转账/还款 → 编辑 → 删除 → 统计 → 资产 → 设置分类/标签/渠道 → 主题切换 → 退出。
  - 执行 `flutter build web` 并确认 `app/build/web/index.html` 生成；用生产构建而非仅 dev server 做一次加载检查。
  - 检查浏览器控制台无 CORS/异常；关闭 Flutter、Go 与浏览器，删除临时数据库与构建缓存（按 SCOPE 最小占用）。
  - 将实际结果、限制与 Android 待验证项回填 Plan/Tasks 测试结论。
- **Acceptance Criteria**：
  - 核心路径在 Web 真实 API 下可用；`flutter build web` 成功且产物可加载。
  - CORS 仅对配置的 Origin 生效；未配置时请求被浏览器拦截。
  - 无遗留进程、临时数据库或一次性产物。
  - 记录不能在本机验证的 Android 项。
- **Dependencies**：TASK-023
- **Priority**：P1

### TASK-025：完成 Android CI 发布链路与构建说明

- **Status**：DONE
- **Executor**：主线
- **Description**：完成 GitHub Actions 的 debug/release APK 构建链路与签名配置说明，实际运行由 TASK-026 在推送后触发。
- **Details**：
  - 检查工作流路径过滤、Flutter 版本、JDK、缓存、测试、APK 上传与 artifact 命名。
  - 当前用户未配置 Secrets：首轮只走 debug 分支并验收 `ledger-debug.apk`；release 分支保留，TASK-025 不声称产出 release。
  - 无 Secrets：产出 `ledger-debug.apk`，用于模拟器验收。
  - 有 Secrets：解码 `ANDROID_KEYSTORE_BASE64` 到临时路径，写入 `key.properties`，构建 release，上传 `ledger-release.apk`，结束后删除临时文件。
  - 在 `app/README.md` 写明本地 Web 开发、测试、CI 构建、签名 Secrets 名称与生成步骤；不写任何真实密钥。
  - 在 Project.md 记录 Android 构建入口、artifact 名称与签名边界。
- **Acceptance Criteria**：
  - 工作流 YAML 可解析，debug/release 条件分支与测试步骤正确。
  - 推送后的运行路径明确；实际运行由 TASK-026 在提交后触发，TASK-025 不声称已产出 APK。
  - 未配置 Secrets 时仅上传 debug；不生成或声称 release APK。
  - debug 与 release artifact 命名可区分。
  - 日志不打印 keystore、密码或 Token。
  - README 步骤可由无 Android 工具链的维护者执行。
- **Dependencies**：TASK-024
- **Priority**：P1

### TASK-026：同步文档、归档与提交

- **Status**：DONE
- **Executor**：主线
- **Description**：按工作流完成 Document Maintenance、Archive 与 Git Commit。
- **Details**：
  - 更新 `.docs/Project.md`：定位/阶段、技术栈、目录结构、运行与测试命令、环境变量（`LEDGER_CORS_ORIGIN`）、依赖、API 复用、Android CI、HTTPS 要求、已知限制。
  - 将 Plan.md/Tasks.md 状态改为 DONE，写入完成日期、测试命令与结果、Web 自检结论、Android 待验证项。
  - 按执行日归档到 `.docs/MM-DD-vN/`（同日已有目录则取递增版本），确认根目录无残留。
  - 清理临时文件、一次性构建产物与无效配置；确认无密钥文件。
  - `git status`、`git diff`、`git log` 后提交；使用中文描述与 Conventional Commits 前缀，例如 `feat(app): 新增 Flutter Android 客户端与 MD3 界面`；不提交无关的既有修改。
  - 提交后若远程可写，普通 push 当前分支触发 `android.yml`，用 `gh run watch` 等待并记录 artifact；不 force push。远程不可写时保留「CI 未运行」说明。
- **Acceptance Criteria**：
  - Project.md 与代码实际状态一致。
  - Plan/Tasks 已归档且状态 DONE，含测试结论。
  - 根目录无 Plan.md/Tasks.md 残留。
  - 提交不包含密钥、临时数据库、构建产物或无关文件。
  - 完成推送时 CI artifact 可下载；未推送时最终报告明确标注验证边界。
- **Dependencies**：TASK-025
- **Priority**：P1

---

## 完成记录

- **完成日期**：2026-10-19
- **Task 状态**：DONE 26/26
- **代码检查**：`dart format --output=none --set-exit-if-changed lib test`（47 文件 0 变更）、`flutter analyze`（零 issue）
- **Flutter 测试**：`flutter test` 77 项通过
- **构建**：`flutter build web` 成功；Go `go test ./...` 与 `go build` 成功
- **Web 自检**：临时 DB + `LEDGER_CORS_ORIGIN=http://localhost:5174`，Chrome 390×844 完成登录、记账、流水、统计、资产、设置；生产构建加载无控制台错误
- **未完成**：Android APK 构建/安装与真机交互未在本机执行；CI 工作流已配置但本轮未推送，故未产出 artifact
