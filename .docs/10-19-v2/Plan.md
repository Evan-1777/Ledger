# Plan：Android 客户端复审吸收与 0.1.0 发布

- **状态**：DONE（2026-10-19）
- **开始日期**：2026-10-19
- **完成日期**：2026-10-19
- **输入**：`.docs/10-19-v1` 归档交付、Review 报告（85/100）、提交 `efb0d52` 与 `9d7a9d8`
- **范围**：`app/`、`.github/workflows/`、`Makefile`、`app/README.md`、`.docs/Project.md`
- **不纳入**：工作区中未提交的技能包迁移改动；不改后端业务 API 与数据库结构

## 1. 背景

Review 认定核心业务链路完整、架构分层与安全边界清楚，未发现阻断级缺陷或凭据泄露路径；扣分集中在四处可复现的可靠性与竞态问题，以及若干未使用 API 面、可访问性细节和验收证据缺口。

本轮按 Main 工作流批判性吸收：逐条对照代码核实，只修复确属真实风险的问题；对超出项目规模或与既有取舍冲突的建议予以驳回；同时完成 Android 0.1.0 Release 的一次性签名与发布工作流。

## 2. 审阅意见吸收决策

| 意见 | 决策 | 依据与做法 |
|---|---|---|
| 中-1 `loadConfig` 无代际守卫，旧会话响应污染新会话 | 采纳 | 配置加载与流水/统计统一为“每次请求递增代际、仅最新代际写回”的并发模型；401 分支也在代际校验之后；`clear()` 递增配置代际 |
| 中-2 有缓存时刷新失败完全静默 | 采纳 | 在 Shell 层监听控制器错误，已有缓存时用一次 SnackBar 提示；同一条错误去重，不把提示复制到四个页面 |
| 中-3 记账弹层不订阅配置 | 采纳 | 弹层 build 订阅账本控制器；配置由空变非空时补一次缺失默认值，只填未选择项，不覆盖用户已输入内容 |
| 中低-4 分类调序半失败无回滚 | 采纳 | 第二次 PUT 失败时用原 `sort_order` 回写第一次更新，再刷新配置；不为两次 PUT 新增后端批量接口 |
| 图例点击区 44dp | 采纳 | 最小高度改为 48dp |
| 分布条 `flex` 可为 0 | 采纳 | 以 `max(1, ...)` 保证正整数 flex |
| 后端英文错误直出 | 采纳 | 在 `ApiException.fromStatus` 统一映射渠道/分类/标签三类已知重名错误，避免各表单重复翻译 |
| 验收证据缺口 | 采纳 | 补“换服务器后下一次请求命中新 host”“返回键关闭记账弹层”“横屏无溢出”三项测试 |
| README 命令描述不准 | 采纳 | 校正文案；新增 `make app-format`，与 CI 的格式检查对齐 |
| 未使用 API 面与重复实现 | 选择性采纳 | 删除无消费的 `formatCents`、`totalCredit`、`ConfirmDialog.busy`、`AmountText` 冗余参数、`hidden` 字段、`LoginResult.expiresAt`、`cardTheme`、重复的系统栏样式、`refreshAll` 与重复的 `source_payment_method_id` 分支；`transferReady` 不删除，改为 UI 校验的实际入口，消除测试与生产规则漂移 |
| 记账弹层“前往设置”误导 | 采纳 | 由配置订阅与默认值回填根除；不在弹层增加额外解释文案 |
| 为调序新增后端批量接口 | 驳回 | 后端契约变更的收益低于一次回滚写入；当前单用户场景下回滚已覆盖主要失败模式 |
| 各页面分别渲染刷新错误 | 驳回 | 会产生四套重复 UI；Shell 单监听器即可覆盖 |
| 工作流自动写入仓库 Secrets | 驳回（技术不可行） | `GITHUB_TOKEN` 没有 Secrets 写权限。一次性工作流生成签名材料并构建 0.1.0 Release，同时把材料放入仅保留 1 天的私有 artifact；由仓库所有者执行四条 `gh secret set` 完成落库 |

## 3. 阶段划分

### Phase 1：数据一致性与会话边界

- 输入：现有 `LedgerController`、`AppShell`、控制器测试
- 输出：配置代际守卫、分类调序回滚、刷新失败统一提示及对应测试
- 验收：旧配置响应不写回、不误触发会话过期；有缓存时刷新失败可见且只提示一次；调序第二次失败后第一次写入被回滚

### Phase 2：弹层配置、可访问性与清理

- 输入：`RecordSheet`、`StatsScreen`、`AssetsScreen`、`ApiException`、共享构件
- 输出：配置晚到自动补默认值、48dp 图例、flex 下限、错误本地化、未使用 API 面清理
- 验收：空配置打开弹层后配置到达可显示渠道并补默认值；`flutter analyze` 无未使用告警；已有测试同步调整

### Phase 3：0.1.0 发布工作流与文档

- 输入：`app/pubspec.yaml`、`.github/workflows/android.yml`、`app/README.md`
- 输出：版本 0.1.0；一次性 `android-release-0.1.0.yml`；签名材料 artifact；Release 创建；README 与 Project.md 更新
- 验收：工作流 YAML 可解析；仅 `workflow_dispatch`；已存在 v0.1.0 Release 或 tag 时拒绝重跑；release APK 由本次生成的密钥签名；artifact 保留 1 天

### Phase 4：验证、归档与提交

- 输入：全部变更
- 输出：格式/分析/测试结果、`10-19-v2` 归档、单个聚焦提交
- 验收：`dart format` 0 变更；`flutter analyze` 无问题；`flutter test` 全绿；归档目录含 Plan/Tasks；提交不包含技能包迁移改动

## 4. 风险与应对

- **配置晚到覆盖用户输入**：只补 `null` 或已失效的选项，保留用户已选分类、标签与渠道；测试覆盖空配置打开后再加载。
- **SnackBar 重复或掩盖首次错误**：仅在已有缓存数据时提示；同一条错误去重；首次加载失败仍由页面 `ErrorState` 承担。
- **回滚请求自身失败**：忽略回滚异常并保留原始错误；`finally` 的 `loadConfig` 暴露服务端实际状态。
- **签名材料泄露**：仅私有仓库可运行；artifact 保留 1 天；工作流结束后删除 runner 临时文件；文档明确要求落库后删除 artifact。
- **本地 Flutter SDK 只读**：测试使用工作区内的临时 SDK 副本（`.flutter-sdk`），验证后删除，不进入提交。

## 5. Subagent 协同结论

本轮不派发 Subagent。改动集中在同一条控制器/UI 调用链上，任务之间强依赖且需要连续对照测试结果；拆分会重复加载上下文并引入合并风险，收益低于主线直接执行。

## 6. 完成定义

- Review 中四项中风险与三项低风险问题全部有代码或文档落点。
- 新增测试能分别复现修复前的缺陷。
- 0.1.0 工作流可在私有仓库手动触发一次，生成签名 APK 与 Release，并给出 Secrets 落库路径。
- Project.md 与代码实际状态一致；Plan/Tasks 归档为 `.docs/10-19-v2/`。

## 7. 执行结果（2026-10-19）

| 检查 | 命令 | 结果 |
|---|---|---|
| Dart 格式 | `cd app && dart format --output=none --set-exit-if-changed lib test` | 47 个文件，0 变更 |
| 静态分析 | `cd app && flutter analyze` | No issues found |
| Flutter 测试 | `cd app && flutter test` | 87 项通过（原 77 + 新增 10） |
| Web 构建 | `cd app && flutter build web` | 成功 |
| Go 测试 | `go test ./...` | 通过（未改后端） |
| 工作流 YAML | `python3 -c "yaml.safe_load(...)"` | 解析通过；仅 `workflow_dispatch` |

本地 Flutter SDK 位于只读挂载，测试使用工作区内临时副本 `.flutter-sdk`；验证后已删除，未进入提交。0.1.0 工作流于 2026-10-19 推送后执行 run 39268947628 成功：Release [v0.1.0](https://github.com/Evan-1777/Ledger/releases/tag/v0.1.0) 已发布，资产 `ledger-0.1.0.apk`（56,418,150 bytes，APK V2 签名证书 SHA-256 `46881101aed6f17e5cc98e2879b8d0475d22394cba082309d7f39cc8c372c6ba`）；四个 Secrets 已落库，`android-signing-0.1.0` artifact 已删除；常规 Android CI run 39270836546 已验证签名 release 分支成功。
