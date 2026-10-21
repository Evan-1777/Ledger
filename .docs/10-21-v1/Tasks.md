# Tasks：Android 客户端冷启动缓存优先渲染与会话乐观恢复

**关联 Plan**：`Plan.md` —— Android 客户端冷启动缓存优先渲染与会话乐观恢复 v1.2  
**总计 Task**：6 个（TASK-001 至 TASK-006）  
**执行主体**：主线  
**状态**：DONE（2026-10-21 完成）  
**已确认语义（2026-10-21）**：401 回登录；网络/超时保留会话并展示缓存快照，不强制回登录。

---

## 验证环境（本轮专用）

- 工作目录：`/home/dev/projects/Ledger`。
- Flutter 3.44.6 / Dart 3.12.2：`/home/dev/flutter/bin/flutter`、`/home/dev/flutter/bin/dart`；`flutter` 不在默认 PATH。
- 依赖缓存：`PUB_CACHE=/home/dev/projects/Ledger/.pub-cache`；首次运行如缺依赖，先执行 `cd app && /home/dev/flutter/bin/flutter pub get --offline`。
- 本机只做格式、静态分析与单元/Widget 测试；不构建 Android APK、不连接模拟器、不启动长期服务。
- 工作区已有与本轮无关的已暂存技能文件、`AGENTS.md` 变更，以及未跟踪的 `temp/image1.png` 至 `temp/image4.png`、`temp/uiux-fixes-demo.*`。提交必须按路径限定，禁止 `git add -A`。
- 基线：`flutter test` 93 项通过（2026-10-20 复审记录）；本轮新增用例后以实际输出更新 Project.md。
- 所有命令逐条读取退出码，禁止用 `| tail` 等管道末端退出码代替；优先重定向到日志后取 `$?`。

---

## Phase 1：可序列化的本地只读缓存层

### TASK-001：为缓存涉及的模型补齐 toJson

- **Status**：DONE
- **Executor**：主线
- **Priority**：P0
- **Depends**：无
- **Description**：在 `app/lib/core/api/models.dart` 中为缓存读取所需的模型添加与 `fromJson` 对称的 `toJson`，使缓存可无损往返。
- **Details**：
  - 文件：`app/lib/core/api/models.dart`。
  - 添加 `toJson` 的类与字段（键名与既有 `fromJson` 完全一致）：
    - `Tag`：`id`、`category_id`、`name`、`sort_order`。
    - `Category`：`id`、`name`、`sort_order`、`type`、`tags`。`type` 写 `type.name`（`expense`/`income`/`system`），不要复用返回 null 的 `CategoryType.api`，否则系统分类往返后退化为 expense。
    - `PaymentMethod`：`id`、`name`、`sort_order`、`type`（`type.name`）、`initial_balance`、`credit_limit`。
    - `Transaction`：`id`、`type`（`type.name`）、`amount_cents`、`fee_cents`、`description`、`payment_method_id`、`payment_method_name`、`source_payment_method_id`、`source_payment_method_name`、`category_id`、`category_name`、`tag_id`、`tag_name`、`transacted_at`（UTC ISO 8601）。字段齐全，避免缓存往返后名称/来源渠道丢失。
    - `TagStat`、`CategoryStat`、`PaymentMethodStat`、`MonthlyTrend`、`AssetChannelStat`、`LiabilityChannelStat`、`AssetSummary`、`StatsSummary`：按各自 `fromJson` 的蛇形键完整输出，含嵌套列表与 `asset_summary`。
  - 不修改任何 `fromJson`、API 请求体或 `TransactionInput.toJson`。
  - 文件：`app/test/core/ledger_cache_test.dart`（新建）。
  - 新建测试组 `model json round-trip`，使用 `app/test/support/harness.dart` 的 `transactionJson()`、`statsJson()` 与 `app/test/support/fakes.dart` 的 `category()`、`paymentMethod()`、`transactionModel()`：
    - `StatsSummary.fromJson(statsJson())` → `toJson()` → `jsonDecode(jsonEncode(...))` → `StatsSummary.fromJson(...).toJson()`，两次 map 用 `equals` 相等，确保数据可实际写入偏好存储。
    - `Transaction.fromJson(transactionJson()).toJson()` 往返后 map 相等。
    - `Category.fromJson({'type': 'system', ...})` 往返后 `type` 仍为 `CategoryType.system`；`PaymentMethod` 往返相等。
- **Acceptance Criteria**：
  - `cd app && /home/dev/flutter/bin/flutter test test/core/ledger_cache_test.dart` 中 `model json round-trip` 全部通过。
  - `/home/dev/flutter/bin/flutter analyze` 无新增 warning/error。
  - `fromJson`、`CategoryType.api`、`TransactionInput.toJson` 无改动（`git diff` 确认）。

---

### TASK-002：新增 LedgerCache 存储层与测试替身

- **Status**：DONE
- **Executor**：主线
- **Priority**：P0
- **Depends**：TASK-001
- **Description**：新建基于 `shared_preferences` 的三域只读缓存，读写时校验版本与服务器地址，损坏数据静默返回空。
- **Details**：
  - 文件：`app/lib/core/storage/ledger_cache.dart`（新建），沿用 `session_store.dart` 的「抽象接口 + 具体实现」写法：
    - `class CachedLedgerConfig { final List<Category> categories; final List<PaymentMethod> channels; }`。
    - `abstract class LedgerCache`：
      - `CachedLedgerConfig? readConfig();`
      - `Future<void> writeConfig(CachedLedgerConfig config);`
      - `List<Transaction>? readTransactions();`
      - `Future<void> writeTransactions(List<Transaction> transactions);`
      - `StatsSummary? readStats();`
      - `Future<void> writeStats(StatsSummary stats);`
    - `class SharedPreferencesLedgerCache implements LedgerCache`：构造函数 `({required SharedPreferences preferences, required String? Function() serverUrl})`。
    - 键：`ledger_cache_config`、`ledger_cache_transactions`、`ledger_cache_stats`；值为信封 `{'version': 1, 'server': server, 'data': ...}`。`version` 在读取时消费，模型字段语义变化时递增版本即可整体失效旧缓存。
    - 读取：`serverUrl()` 为空、键不存在、`jsonDecode` 失败、信封非 Map、版本不是 1、server 与当前地址不完全相等、`data` 顶层结构无法解析为预期形状时返回 null；字段级缺失沿用现有 `fromJson` 的宽容默认，不做逐字段强校验。
    - 写入：服务器地址为空时直接返回；`preferences.setString` 与编码异常在实现内吞掉（缓存是尽力而为，不影响业务加载）。
    - 类注释写明容量上限：单键 JSON 以 100 条流水窗口为界，超出该量级迁移到 SQLite/文件。
  - 文件：`app/test/support/fakes.dart`，新增 `class MemoryLedgerCache implements LedgerCache`：三个可空字段、三个写入计数器，`write*` 覆盖字段并自增计数。
  - 文件：`app/test/core/ledger_cache_test.dart`，新增 `setUpAll(initTestLocale);`（确保 Flutter 绑定已初始化）与 `setUp(() => SharedPreferences.setMockInitialValues({}));`，以及以下用例：
    - `round-trips configuration, transactions and stats`：用真实 `SharedPreferences.getInstance()` 与 `SharedPreferencesLedgerCache(serverUrl: () => 'https://ledger.test')` 写入三域，读回后逐字段断言（分类含 tags、系统分类类型、流水描述/金额/时间、统计结余/资产汇总）。
    - `ignores entries saved for another server`：用旧地址写入，换新地址读取，三域均为 null。
    - `ignores corrupt entries`：写入合法值后用相同键写入 `'not-json'`，读取返回 null 且不抛异常。
    - `ignores malformed payload shapes`：写入信封合法但 `data: 'not-a-list'` 的流水条目，`readTransactions()` 返回 null。
    - `skips writes without a server address`：`serverUrl: () => null` 写入后，改回合法地址读取仍为 null。
- **Acceptance Criteria**：
  - `flutter test test/core/ledger_cache_test.dart` 全部通过。
  - `flutter analyze` 无新增 warning/error。
  - `app/pubspec.yaml` 未新增依赖。
  - 缓存实现不向上抛解析/写入异常。

---

## Phase 2：控制器缓存恢复与成功写穿

### TASK-003：LedgerController 水合缓存并在成功后写回

- **Status**：DONE
- **Executor**：主线
- **Priority**：P0
- **Depends**：TASK-002
- **Description**：让控制器在首帧前读取三域缓存填充状态，并在每个域加载成功后写回对应缓存；失败与筛选态不覆盖全量缓存。
- **Details**：
  - 文件：`app/lib/core/state/ledger_controller.dart`。
  - 构造函数增加可选参数 `LedgerCache? cache`，赋值给私有字段 `_cache`；既有调用方无需修改。
  - 新增 `void hydrateFromCache()`：分别读取 config/transactions/stats，非空即覆盖对应字段；仅当至少一个域命中时调用一次 `notifyListeners()`；不修改 `*Loading`、`*Error`、`filter`。
  - 三个加载器在成功赋值之后、`finally` 之前写回：
    - `loadConfig`：`await _cache?.writeConfig(CachedLedgerConfig(categories: categories, channels: channels));`
    - `loadTransactions`：仅当 `filter == TransactionFilter.all` 时 `await _cache?.writeTransactions(transactions);`
    - `loadStats`：`await _cache?.writeStats(stats!);`（赋值后 stats 非空）。
  - 失败路径（`ApiException` 或通用 catch）不写缓存；401 走 `_expire()` 的路径同样不写。
  - `clear()` 只清内存，不删除磁盘缓存。
  - 文件：`app/test/support/harness.dart`：`testControllers` 与 `testControllersWithHandler` 增加可选参数 `LedgerCache? cache`，传给 `LedgerController`。
  - 文件：`app/test/core/ledger_controller_test.dart`，新增用例：
    - `hydrates cached data without entering loading`：`MemoryLedgerCache` 预置三类数据，调用 `hydrateFromCache()`；断言分类、渠道、流水、统计就位，三个 loading 均为 false。
    - `hydrate fills only the domains present in the cache`：`MemoryLedgerCache` 仅预置流水，调用 `hydrateFromCache()`；断言流水就位、`stats` 仍为 null、`categories`/`channels` 为空，三个 loading 均为 false。
    - `loadAll writes each domain back to the cache`：使用 `standardHandler` 与 `MemoryLedgerCache`，`await loadAll()`；断言三个写入计数均为 1，缓存内流水描述与统计结余与内存一致。
    - `a failed refresh keeps cached data and leaves the cache untouched`：先水合，再用全部返回 500 的 handler `await loadAll()`；断言内存数据不变、三域错误非空、三个写入计数仍为 0。
    - `filtered transaction refreshes do not replace the cached full list`：先 `loadAll` 写入全量，再切换 `TransactionFilter.expense` 并等待刷新完成；断言流水写入计数仍为 1，缓存流水仍为全量列表。
- **Acceptance Criteria**：
  - 上述五个用例通过，既有 `ledger_controller_test.dart` 用例不回归。
  - `flutter analyze` 无新增 warning/error。
  - 失败路径不产生缓存写入；`clear()` 不调用任何缓存删除。

---

## Phase 3：会话乐观恢复与后台校验

### TASK-004：SessionController 乐观恢复与启动入口调整

- **Status**：DONE
- **Executor**：主线
- **Priority**：P0
- **Depends**：TASK-003
- **Description**：本地 token 存在时立即进入已认证状态，后台校验 `/api/auth/check`；401 回登录，网络失败保留会话；入口在首帧前完成本地恢复。
- **Details**：
  - 文件：`app/lib/features/auth/session_controller.dart`：
    - 删除 `startupError` 字段与所有赋值。
    - 新增 `int _generation = 0`；`restore`、`login`、`logout`、`expire`、`updateServer` 各自在入口递增该值。
    - `restore()`：置 `booting` 并通知；读取地址与 token，代际不符直接返回；缺少地址或 token → `locked`；否则立即置 `authenticated` 并通知，随后 `unawaited(_verifySession(generation))`。
    - `_verifySession(int generation)`：调用 `_api.checkAuth()`；捕获 `ApiException`，仅当 `generation == _generation` 且 `error.isUnauthorized` 时 `await expire()`；网络/超时/服务端错误保持当前会话。
    - 需要 `import 'dart:async';` 使用 `unawaited`。
  - 文件：`app/lib/main.dart`：在 `sessionStore` 之后构造 `final cache = SharedPreferencesLedgerCache(preferences: preferences, serverUrl: () => sessionStore.serverUrl);`，并以 `cache: cache` 传入 `LedgerController`；补充 `ledger_cache.dart` import。构造 `SessionController` 后、`runApp` 前执行 `await session.restore();`，让首帧直接落在 Shell 或登录页。
  - 文件：`app/lib/app.dart`：删除 `_SplashScreen` 类；`_SessionGate` 的 `booting` 分支改为最小 `Scaffold` + 居中 `CircularProgressIndicator`，并删除 `session.startupError` 引用。本 Task 保留 `autoRestore` 参数（此时入口已恢复，分支通常不触发），由 TASK-005 删除。
  - 文件：`app/test/core/session_controller_test.dart`：
    - 改写 `restore network failure keeps the token and exposes retry` 为 `a background network failure keeps the optimistic session`：MockClient 抛 `http.ClientException`，`await restore()` 后断言 authenticated，`await pumpEventQueue()` 后仍 authenticated 且 token 保留。
    - 改写 `restore with an expired token clears it`：`/api/auth/check` 返回一个待完成的 `Completer<http.Response>`；`await restore()` 后断言 authenticated（乐观），再以 401 完成 completer，`await pumpEventQueue()` 后断言 locked 且 token 为 null。
    - 新增 `restore opens the shell before the network answers`：MockClient 使用 `Completer<http.Response>` 挂起，`await restore()` 后立即断言 authenticated；再完成 completer 并 `await pumpEventQueue()`，避免挂起计时器。
    - 保留并确认 `restore without a token locks the app`、登录、退出、切换服务器用例。
- **Acceptance Criteria**：
  - `flutter test test/core/session_controller_test.dart` 全部通过。
  - `grep -rnE '_SplashScreen|startupError' app/lib app/test` 无结果。
  - `grep -nE 'SharedPreferencesLedgerCache|cache: cache' app/lib/main.dart` 同时命中真实缓存构造与控制器传参。
  - 有 token 时 `restore` 返回耗时只包含本地读取；401 只在后台生效；网络失败不回登录。
  - `flutter analyze` 无新增 warning/error。

---

## Phase 4：首帧装配、冷启动回归与交付

### TASK-005：装配首帧水合并补齐冷启动 Widget 回归

- **Status**：DONE
- **Executor**：主线
- **Priority**：P0
- **Depends**：TASK-004
- **Description**：应用在构建首帧前水合缓存并启动刷新；登录后再次水合；用 Widget 测试锁定冷启动、断网、401 与无缓存四条路径。
- **Details**：
  - 文件：`app/lib/app.dart`：
    - 删除 `autoRestore` 参数、字段、initState 中的 post-frame `restore` 分支与 import 清理。
    - `initState`：若 `_wasAuthenticated`，先 `widget.ledger.hydrateFromCache()`，随后直接调用（不 await、不推迟到 post-frame）`widget.ledger.loadAll()`，让三个 loading 标志在首帧构建前同步置位；无缓存时首帧保持骨架，不出现假空态/错误态。
    - `_onSessionChanged` 的登录转换：先 `hydrateFromCache()`，再 `loadAll()`；会话失效分支继续 `ledger.clear()`。
  - 文件：`app/test/app_smoke_test.dart`：删除两处 `autoRestore: false`。
  - 文件：`app/test/support/harness.dart`：新增 `MemoryLedgerCache seededLedgerCache()`，用 `category()`、`paymentMethod()`、`transactionModel()`、`StatsSummary.fromJson(statsJson())` 组装三域数据，描述使用默认「午餐 · 牛肉面」。
  - 文件：`app/test/app_cold_start_test.dart`（新建），全部通过 `LedgerApp(session: ..., ledger: ..., preferences: ...)` 挂载：
    - `cold start paints cached data before the network answers`：`testControllers(token: 'token', cache: seededLedgerCache())`，MockClient 每个请求先 `await Future<void>.delayed(const Duration(milliseconds: 200))` 再 `defaultApi`；`await session.restore()`；`pumpWidget` 后立即断言 `find.descendant(of: find.byType(StreamScreen), matching: find.text('午餐 · 牛肉面'))` 存在、`find.byType(SkeletonList)`/`find.byType(EmptyState)`/`find.byType(ErrorState)` 均为零、`find.text('管理员密码')` 不存在；随后 `pump(300ms)` + `pumpAndSettle()`，数据仍在。
    - `cold start without cache keeps skeletons on the first frame`：`testControllers(token: 'token')`，MockClient 先 `await Future<void>.delayed(const Duration(milliseconds: 200))` 再 `defaultApi`；`await session.restore()`；`pumpWidget` 后立即断言 `find.byType(SkeletonList)` 存在、`find.byType(EmptyState)` 与 `find.byType(ErrorState)` 均为零；`pump(300ms)` + `pumpAndSettle()` 收尾。
    - `refresh failure keeps cached data and shows one snackbar`：`testControllers(token: 'token', cache: seededLedgerCache())`，MockClient 抛 `http.ClientException('offline')`；`await session.restore()` 后再挂载；用有限次 `pump()`（如 `pump()` + `pump(100ms)`）推进错误与 SnackBar，避免对可能未收敛的界面使用无界 `pumpAndSettle()`；断言缓存流水仍在、未出现登录页、`find.byType(SnackBar)` 为 1 且包含「无法连接服务器」。
    - `a rejected token returns to the login screen`：MockClient 对所有请求返回 401；`await session.restore()` 后挂载，`pumpAndSettle()`；断言 `find.text('管理员密码')` 存在、缓存流水不存在、`session.phase` 为 locked。
  - 不新增页面、不改四个一级页布局；320dp + 2x 用例继续由既有测试覆盖。
- **Acceptance Criteria**：
  - 四个新用例通过；`app_smoke_test.dart`、`shell_test.dart`、`stream_screen_test.dart`、`stats_test.dart`、`assets_test.dart`、`settings_test.dart` 不回归。
  - 有缓存用例首帧 Skeleton/Empty/Error 均为零；无缓存用例首帧 Skeleton 存在且 Empty/Error 为零；断网不出现登录页；401 不残留业务数据。
  - `grep -rn 'autoRestore' app/lib app/test` 无结果。
  - `flutter analyze` 无新增 warning/error。

---

### TASK-006：版本、文档、全量门禁、归档与提交

- **Status**：DONE
- **Executor**：主线
- **Priority**：P1
- **Depends**：TASK-005
- **Description**：更新版本与文档，执行全量门禁，归档 Plan/Tasks，并按路径提交本轮变更。
- **Details**：
  - 版本：`app/pubspec.yaml` → `version: 0.2.0+4`；`app/lib/features/settings/settings_screen.dart` 的 `APP_VERSION` 默认值 → `'0.2.0'`。
  - 文件：`app/README.md`：把「不做分页、离线库、后台同步或推送」改为「冷启动使用本地只读快照缓存；不做分页、离线写入、后台同步或推送」。
  - 文件：`.docs/Project.md`：
    - 概述「阶段」补充本轮交付；`app/` 结构补充 `core/storage/ledger_cache.dart`。
    - Android 客户端「会话」改为乐观恢复 + 后台校验；「数据」补充三域缓存与写穿/筛选守卫；「测试」更新用例数与新增覆盖；「发布」版本改 `0.2.0+4`。
    - 「已知限制」把「无离线库/同步」改为「冷启动只读缓存，无离线写入/后台同步」。
    - 「约束与决策」新增 2026-10-21 条目，记录：SharedPreferences 三域缓存及容量上限、乐观会话与 401/网络失败语义、服务器地址作用域、筛选态不写流水缓存、退出/过期保留缓存。
  - 门禁（逐条取退出码）：
    1. `cd app && /home/dev/flutter/bin/dart format --output=none --set-exit-if-changed lib test`
    2. `cd app && /home/dev/flutter/bin/flutter analyze`
    3. `cd app && /home/dev/flutter/bin/flutter test`
  - Plan/Tasks 标注 `状态：DONE`、完成日期、实际测试结果；用文件移动归档到 `.docs/10-21-v1/`（当前两份文件未跟踪，`git mv` 不适用；先确认同日目录不存在，存在则取下一个版本号），校验根目录无残留。
  - 提交：
    - `git status`、`git diff`、`git log -5` 检查范围与风格。
    - 归档后确认根目录 Plan.md/Tasks.md 已移入 `.docs/10-21-v1/`；按路径暂存本轮文件（`.docs/10-21-v1/Plan.md`、`.docs/10-21-v1/Tasks.md`、`app/lib/`、`app/test/`、`app/pubspec.yaml`、`app/README.md`、`.docs/Project.md`），禁止 `git add -A`。
    - 索引中已有与本轮无关的暂存文件（本轮开始时 24 个），提交必须使用路径限定形式：`git add -- <本轮路径>` → `git diff --cached --stat -- <本轮路径>` → `git commit -m "feat(app): 冷启动缓存优先渲染与会话乐观恢复" -- <本轮路径>`；禁止直接 `git commit -m` 提交整个索引。
    - 提交后 `git show --name-only --oneline HEAD` 与 `git diff --cached --stat` 复核：前者只含本轮路径，后者仍保留既有暂存文件，确认未被一并提交。
- **Acceptance Criteria**：
  - 格式无变更、分析与全量测试通过，实际项数写入 Project.md 与 Tasks。
  - `grep -rn '0\.1\.2' app/lib app/pubspec.yaml` 无版本残留。
  - `.docs/10-21-v1/` 同时含 Plan.md 与 Tasks.md，根目录无 Plan.md/Tasks.md。
  - `git show --name-only HEAD` 仅含本轮预期路径；`git diff --cached --stat` 仍显示既有暂存文件，确认未被一并提交。

---

## 完成记录

- 完成日期：2026-10-21。
- 门禁：`dart format --set-exit-if-changed lib test` 无变更；`flutter analyze` 无问题；`flutter test` 112 项通过（TASK-001 往返 4 项、TASK-002 缓存 5 项、TASK-003 控制器 5 项、TASK-004 会话 3 项改写/新增、TASK-005 冷启动 4 项）。
- 门禁执行补充：本机 Flutter SDK 所在分区只读，命令以 `FLUTTER_ALREADY_LOCKED=true` 直接调用 `flutter_tools.snapshot`；`dart format` 与 `flutter analyze` 需将 `HOME` 指向可写目录（本机用 `/tmp/dart_home`），否则 Dart 分析遥测写会话文件失败会中断命令。
- 版本 `0.2.0+4`；归档至 `.docs/10-21-v1/`。
