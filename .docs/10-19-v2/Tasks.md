# Tasks：Android 客户端复审吸收与 0.1.0 发布

- **状态**：DONE（2026-10-19，11/11）
- **开始日期**：2026-10-19
- **依据**：`.docs/10-19-v1` Review 报告与 `.docs/10-19-v1/Tasks.md` 验收项
- **完成日期**：2026-10-19

## Phase 1：数据一致性与会话边界

### TASK-001：为配置加载增加请求代际守卫

- **Status**：DONE
- **Executor**：主线
- **Description**：让 `loadConfig` 与流水/统计使用同一种“仅最新代际写回”的并发模型，并在 `clear()` 中使旧配置请求失效。
- **Details**：
  - `ledger_controller.dart` 新增 `_configGeneration`；`loadConfig` 每次调用递增，不再用 `configLoading` 提前返回。
  - 成功、`ApiException`、未知异常与 `finally` 均先校验代际；401 的代际校验位于 `_expire()` 之前。
  - `clear()` 递增配置代际并重置配置加载/错误状态。
- **Acceptance Criteria**：
  - 配置请求未完成时调用 `clear()`，旧响应不写入 `categories`/`channels`，不调用会话过期回调。
  - 并发两次配置刷新时，只有后发起的响应可写回。
  - 既有 401 清空业务数据测试仍通过。
- **Dependencies**：无
- **Priority**：P0

### TASK-002：分类调序失败回滚第一次写入

- **Status**：DONE
- **Executor**：主线
- **Description**：相邻分类调序在第二次 PUT 失败时恢复第一个分类的原 `sort_order`，再刷新配置。
- **Details**：
  - `moveCategory` 把两次 PUT 分开处理；仅第二次失败触发回滚，回滚请求不经过会话守卫。
  - 回滚失败不覆盖原始异常；`finally` 仍执行 `loadConfig()`。
- **Acceptance Criteria**：
  - 第二次 PUT 返回 500 时产生第三次 PUT，请求体为第一个分类的原 `sort_order`。
  - 原始异常继续抛给设置页，保持既有错误提示。
- **Dependencies**：TASK-001
- **Priority**：P0

### TASK-003：Shell 统一提示有缓存时的刷新失败

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `AppShell` 监听账本控制器，已有缓存数据时用一次 SnackBar 暴露刷新失败。
- **Details**：
  - 监听 `configError`/`transactionsError`/`statsError` 的首个非空值；同一条错误只提示一次，错误清空后重置。
  - 仅当 `transactions`、`stats`、`categories` 或 `channels` 至少一项非空时提示；首次加载失败继续由页面 `ErrorState` 承担。
  - 使用 `showLedgerSnackBar(..., isError: true)`，不在各页面复制提示逻辑。
- **Acceptance Criteria**：
  - 已有数据时刷新全失败，界面保留旧数据并出现一个 SnackBar。
  - 三个请求返回同一条错误时不叠加多个 SnackBar。
  - 无缓存数据时刷新失败不弹 SnackBar，页面错误态仍可重试。
- **Dependencies**：TASK-001
- **Priority**：P0

## Phase 2：弹层配置、可访问性与清理

### TASK-004：记账弹层订阅配置并补缺失默认值

- **Status**：DONE
- **Executor**：主线
- **Description**：弹层在配置晚到时重建，并只补齐尚未选择的分类、标签与渠道。
- **Details**：
  - build 顶部 `context.watch<LedgerController>()`；用 post-frame 回调触发一次 `setState`，避免 build 期间修改状态。
  - 新增“是否缺少默认值”判断与 `_adoptMissingDefaults`；支出/收入保留已有分类和标签，转账/还款保留已有渠道。
  - 转账来源与目标在配置到达后仍必须不同；系统分类仅在未设置时回填。
- **Acceptance Criteria**：
  - 空配置时打开弹层显示空态；配置随后加载完成，弹层自动显示渠道与分类并选中默认值。
  - 用户已选择的分类、标签、渠道不被覆盖。
  - 编辑已有账单时不改写初始选择。
- **Dependencies**：TASK-003
- **Priority**：P0

### TASK-005：可访问性、分布条与错误本地化

- **Status**：DONE
- **Executor**：主线
- **Description**：修复图例命中区、极小余额 flex 与后端英文重名错误直出。
- **Details**：
  - `stats_screen.dart` 图例行最小高度改为 48dp。
  - `assets_screen.dart` 分布条 flex 使用 `math.max(1, ...)`，保证正整数。
  - `api_exception.dart` 集中映射 `payment method already exists`、`category already exists`、`tag already exists in this category`、`duplicate tag name or invalid update`。
- **Acceptance Criteria**：
  - 极小正余额资产不会触发 `Expanded` 的 flex 断言。
  - 渠道、分类、标签重名时界面显示中文提示。
  - 既有 409 中文消息保持原样。
- **Dependencies**：TASK-004
- **Priority**：P1

### TASK-006：清理未使用 API 面与重复实现

- **Status**：DONE
- **Executor**：主线
- **Description**：删除无生产消费的接口与重复分支，并让 `transferReady` 成为 UI 实际校验入口。
- **Details**：
  - `record_sheet.dart` 的转账校验调用 `RecordRules.transferReady`，保留“至少两个资产账户”的专用提示。
  - 删除 `formatCents`、`DerivedAssets.totalCredit`、`ConfirmDialog.busy`、`AmountText` 的 `signed`/`withCurrency` 参数、`_AssetRow.hidden`/`_LiabilityRow.hidden`、`LoginResult.expiresAt`、`cardTheme`、`AppBarTheme.systemOverlayStyle`、`refreshAll`。
  - `TransactionInput.toJson` 合并重复的 `source_payment_method_id` 条件。
  - 同步删除或调整对应测试断言。
- **Acceptance Criteria**：
  - `flutter analyze` 无 unused 告警。
  - 转账校验测试仍覆盖“少于两个账户、未选择、同账户”三种情况。
  - 记账请求体字段与响应模型既有契约不变。
- **Dependencies**：TASK-004
- **Priority**：P1

### TASK-007：补齐三项验收测试与 README/Makefile 校正

- **Status**：DONE
- **Executor**：主线
- **Description**：补齐换服务器、返回键、横屏的验收证据，并校正本地命令说明。
- **Details**：
  - `session_controller_test.dart`：换服务器后调用受保护请求，断言命中新 host。
  - `shell_test.dart`：打开记账弹层后调用系统返回，断言弹层关闭且 Shell 仍在流水页。
  - `shell_test.dart`：640×360 横屏 pump，断言无 overflow 异常。
  - `Makefile` 增加 `app-format`（`DART ?= dart`）；`app/README.md` 分别描述 format/analyze/test/web 四个目标。
- **Acceptance Criteria**：
  - 三项测试可在本地通过。
  - README 不再声称 `app-analyze` 封装前三项检查。
- **Dependencies**：TASK-006
- **Priority**：P1

## Phase 3：0.1.0 发布工作流与文档

### TASK-008：版本号调整为 0.1.0

- **Status**：DONE
- **Executor**：主线
- **Description**：让 Android 版本名、Flutter 构建版本与设置页显示一致为 0.1.0。
- **Details**：
  - `app/pubspec.yaml` 改为 `0.1.0+1`。
  - `settings_screen.dart` 的 `APP_VERSION` 默认值改为 `0.1.0`。
- **Acceptance Criteria**：
  - 本地 Web 构建与 CI APK 的 `versionName` 均为 0.1.0，`versionCode` 为 1。
  - 设置页底部显示 0.1.0。
- **Dependencies**：TASK-007
- **Priority**：P0

### TASK-009：新增一次性签名与 Release 工作流

- **Status**：DONE
- **Executor**：主线
- **Description**：新增仅 `workflow_dispatch` 的 `.github/workflows/android-release-0.1.0.yml`，生成新签名密钥、构建 0.1.0 APK、创建 Release，并输出待落库的 Secrets 材料。
- **Details**：
  - 私有仓库守卫；Release `v0.1.0` 或同名 tag 已存在时失败，保证只运行一次。
  - JDK 17 + Flutter 3.44.6；format/analyze/test 通过后生成 JKS；`key.properties` 仅在 runner 临时目录。
  - `flutter build apk --release --build-name=0.1.0 --build-number=1 --dart-define=APP_VERSION=0.1.0`；`apksigner` 校验签名。
  - 上传 `android-signing-0.1.0` artifact（保留 1 天），其中含 Base64 keystore、密码、别名与 `gh secret set` 说明；job summary 给出命令，不打印密钥值。
  - `gh release create v0.1.0` 上传 `ledger-0.1.0.apk`；`if: always()` 清理临时密钥与 `key.properties`。
- **Acceptance Criteria**：
  - YAML 可解析；触发方式只有 `workflow_dispatch`。
  - 已存在 Release/tag 时在生成密钥前退出。
  - Release 资产名为 `ledger-0.1.0.apk`，签名证书由本次生成的 keystore 签发。
  - artifact 保留 1 天且仅私有仓库可运行。
- **Dependencies**：TASK-008
- **Priority**：P0

### TASK-010：更新发布与复审吸收文档

- **Status**：DONE
- **Executor**：主线
- **Description**：同步 `app/README.md`、`.docs/Project.md` 与归档文档，记录 0.1.0 工作流、Secrets 落库方式和本轮修复决策。
- **Details**：
  - README 增加一次性工作流说明、artifact 下载与四条 `gh secret set` 命令、运行后删除 artifact 的要求。
  - Project.md 更新版本、发布链路、测试证据与 2026-10-19 复审吸收决策。
  - 归档时将 Plan/Tasks 状态改为 DONE，记录测试命令与结果。
- **Acceptance Criteria**：
  - 文档不包含真实服务器地址、密码或密钥值。
  - Project.md 的发布描述与工作流实际行为一致。
- **Dependencies**：TASK-009
- **Priority**：P1

## Phase 4：验证与归档

### TASK-011：执行本地验证并归档提交

- **Status**：DONE
- **Executor**：主线
- **Description**：完成格式、分析、测试、文档归档与聚焦提交。
- **Details**：
  - 使用工作区临时 Flutter SDK 副本执行 `dart format --output=none --set-exit-if-changed lib test`、`flutter analyze`、`flutter test`。
  - 删除临时 SDK 副本与构建产物；检查 `git status` 不包含技能包迁移改动。
  - Plan/Tasks 移入 `.docs/10-19-v2/` 并标注 DONE；提交只包含本轮相关文件。
- **Acceptance Criteria**：
  - 三项 Flutter 检查全部通过并记录数量。
  - 根目录无残留 Plan.md/Tasks.md；归档目录同时含两份文档。
  - 提交信息使用中文 Conventional Commits，未包含 `.agents/`、`.codebuddy/`、`.dsh/` 等技能迁移改动。
- **Dependencies**：TASK-010
- **Priority**：P0

## 完成记录

- **Task 状态**：DONE 11/11（2026-10-19）
- **格式检查**：`cd app && dart format --output=none --set-exit-if-changed lib test` → 47 个文件，0 变更
- **静态分析**：`cd app && flutter analyze` → No issues found
- **Flutter 测试**：`cd app && flutter test` → 87 项通过（原 77 项 + 新增 10 项：配置代际 2、调序回滚 1、换服务器 host 1、刷新提示 1、返回键 1、横屏 1、配置晚到 1、极小余额 1、重名错误本地化 1）
- **Web 构建**：`cd app && flutter build web` → 成功
- **Go 测试**：`go test ./...` → 通过（本轮未改后端）
- **发布工作流**：`.github/workflows/android-release-0.1.0.yml` 已加入并通过 YAML/Shell 语法检查；仅 `workflow_dispatch`，已有 `v0.1.0` Release/tag 时拒绝重跑。2026-10-19 推送后执行 run [39268947628](https://github.com/Evan-1777/Ledger/actions/runs/39268947628) 成功：Release [v0.1.0](https://github.com/Evan-1777/Ledger/releases/tag/v0.1.0) 发布 `ledger-0.1.0.apk`（56,418,150 bytes，APK V2 签名证书 SHA-256 `46881101aed6f17e5cc98e2879b8d0475d22394cba082309d7f39cc8c372c6ba`）；四个 Secrets 已落库，签名材料 artifact 已删除。
