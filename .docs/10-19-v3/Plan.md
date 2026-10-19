# Plan：修复 Android Release 版本启动卡在启动画面

**状态**：DONE  
**日期**：2026-10-19  
**完成**：2026-10-19；release 修复已由 CI run 39280755463 构建并在 Android 12（API 32，x86_64）两次冷启动验证进入登录页；Android 16 待用户外部复核（TASK-009）。  
**版本**：v1.1（吸收 2026-10-19 Review：构建期证据、失败分流、归档重开口径与文档边界）  
**依据**：用户缺陷报告（Android 12 与 Android 16 均复现）；本机 ADB 复现、日志取证与 debug/release 对照

---

## 1. 背景与目标

用户安装 Android 版本后，启动只停留在系统启动画面，持续不展示实际内容；手机本身没有卡死。该问题在 Android 12 与 Android 16 上均能复现。

本轮目标：

- release APK 在 Android 12 上正常画出 Flutter 首帧并进入登录页。
- 不改变依赖版本、不关闭 R8、不重构应用启动流程。
- debug 构建、既有业务功能、CI 签名发布链路不回归。
- 同一构建产物交由用户在 Android 16 上复核。

## 2. 根因结论

release 构建默认启用 R8。`shared_preferences_android 2.5.0` 通过 Pigeon JNI 调用 Kotlin 端 `SharedPreferencesApiRegistrar`，JNI 按 Kotlin 类名与方法描述符查找目标方法。R8 重命名了 `kotlin.coroutines.Continuation` 等 Kotlin 运行时类，导致 `getAll` 的实际描述符与 Dart 侧使用的描述符不再一致。

`main()` 在 `SharedPreferences.getInstance()` 处收到 `NoSuchMethodError`，异常未被捕获，`runApp` 永远不会执行。Flutter 不产生首帧，Android 启动画面因此持续停留；进程仍然存活，所以表现为“停在启动页”而不是闪退。本项目使用 legacy `SharedPreferences` API，日志中的注册器是 `SharedPreferencesApiRegistrar`；上游复现使用 async API（`SharedPreferencesAsyncApiRegistrar`），两者共用同一 Pigeon JNI 与 `Continuation` 描述符机制，修复规则相同。

<div style="display:flex;flex-wrap:wrap;gap:6px;align-items:center;font-size:12px;line-height:1.6;margin:12px 0">
  <span style="border:1px solid #d6dbe4;border-radius:8px;padding:7px 10px">main() 读取偏好</span>
  <span style="color:#8a94a6">→</span>
  <span style="border:1px solid #d6dbe4;border-radius:8px;padding:7px 10px">Pigeon JNI 查找 getAll</span>
  <span style="color:#8a94a6">→</span>
  <span style="border:1px solid #d9a7a7;border-radius:8px;padding:7px 10px;background:#fdf4f4;color:#8a1f1f">R8 重命名 Continuation<br>描述符失配</span>
  <span style="color:#8a94a6">→</span>
  <span style="border:1px solid #d9a7a7;border-radius:8px;padding:7px 10px;background:#fdf4f4;color:#8a1f1f">NoSuchMethodError<br>main() 中断</span>
  <span style="color:#8a94a6">→</span>
  <span style="border:1px solid #d6dbe4;border-radius:8px;padding:7px 10px">runApp 未执行<br>无首帧</span>
  <span style="color:#8a94a6">→</span>
  <span style="border:1px solid #d6dbe4;border-radius:8px;padding:7px 10px">启动画面停留</span>
</div>

已取得的证据：

- release APK `ledger-0.1.0.apk` 安装到 Android 12（API 32，x86_64）模拟器后，logcat 出现 `Unhandled Exception: PlatformException(... NoSuchMethodError ... SharedPreferencesApiRegistrar.getAll(...)) `；进程存活，窗口只剩启动背景（用户设备上表现为放大的启动图标）。
- 同一设备改装 CI 产出的 debug APK，正常进入登录页，无上述异常。
- 两者唯一的关键差异是 release 启用 R8；上游同类问题 [flutter/flutter#194649](https://github.com/flutter/flutter/issues/194649) 给出相同结论，并给出 app 级 keep 规则 workaround；上游修复 [flutter/packages#13311](https://github.com/flutter/packages/pull/13311) 尚未发布到 2.5.0。

## 3. 阶段划分

### Phase 1：release 构建保留 Kotlin JNI 依赖类

| 项目 | 内容 |
|------|------|
| **输入** | 现有 release 构建配置与 `shared_preferences_android 2.5.0` 的 JNI 依赖 |
| **输出** | app 级 ProGuard keep 规则，覆盖上游确认的 Kotlin 运行时类 |
| **验收标准** | 规则文件存在且内容完整；Flutter Gradle 插件在 release build type 中自动纳入该文件；不新增 Gradle 配置 |

### Phase 2：CI release 构建与 ADB 运行验证

| 项目 | 内容 |
|------|------|
| **输入** | Phase 1 的修复提交 |
| **输出** | 签名 release APK；启动日志与登录页截图；验证结论 |
| **验收标准** | Android 12 模拟器安装后进入登录页；logcat 无 `NoSuchMethodError`；Activity 记录 `Fully drawn`；进程存活；debug 构建不回归 |

### Phase 3：文档、清理与归档

| 项目 | 内容 |
|------|------|
| **输入** | Phase 2 的验证结果 |
| **输出** | `.docs/Project.md` 决策记录；归档的 Plan/Tasks；只含本轮路径的提交 |
| **验收标准** | Project.md 与代码实际状态一致；根目录无 Plan.md/Tasks.md 残留；临时工具与 APK 已清理；提交未混入工作区既有暂存文件；Android 16 复核失败时可按重开口径解档回 Phase 1 |

## 4. 关键决策

| 决策项 | 选择 | 理由 | 替代方案（为何不选） |
|--------|------|------|----------------------|
| 修复方式 | app 级 ProGuard keep 规则 | 最小差分；不改变依赖版本；直接针对 R8 描述符重写 | 降级 `shared_preferences_android`（改动锁定版本，升级后复发）；关闭 R8（放弃收缩，包体增大） |
| 规则放置 | app 级 ProGuard 规则文件 | Flutter Gradle 插件会在 release build type 自动加入该文件，无需改构建脚本 | 显式添加 `proguardFiles`（额外配置，无收益） |
| 规则范围 | 仅上游确认的六个 Kotlin 类 | registrar 自身由 `@Keep` 保留，只有 Kotlin 运行时类需要 keep | 宽泛 keep 整个插件包（增大包体，掩盖真实边界） |
| 验证方式 | CI 签名 release APK + 用户提供的 ADB 设备 | 本机无 JDK/Android SDK/Gradle，按项目边界由 CI 构建；ADB 能拿到运行期证据 | 本地构建（违反项目边界）；只做静态检查（无法证明 release 运行） |
| 启动流程 | 本轮不重构 `main()` | 根因在 release 构建的 JNI 描述符，不在启动顺序；保持最小差分 | 将插件初始化移到首帧之后（额外行为变更，缺少必要性证据） |

## 5. 风险清单

| 风险 | 等级 | 缓解措施 |
|------|------|----------|
| keep 规则未被 Gradle 采纳 | 中 | 以 CI release 构建、APK dex 辅助证据与真机启动为准；若未生效，回规划段修订后再改为显式 `proguardFiles` |
| CI Secrets 缺失，产物退化为 debug | 中 | 检查构建日志与 artifact 名称；Secrets 已在此前发布链路配置 |
| 本机只有 Android 12 模拟器 | 中 | 修复属于构建期 R8 问题，与系统版本无关；Android 16 由用户安装同一 APK 复核 |
| 工作区存在与本轮无关的已暂存技能文件 | 高 | 提交一律按路径执行，禁止 `git add -A` 与不带路径的 `git commit` |
| 上游后续发布 consumer rules | 低 | 在 Project.md 记录移除条件；插件升级后再删除 app 级规则 |

## 6. Phase 依赖关系

```
Phase 1 ──→ Phase 2 ──→ Phase 3
```

三个阶段严格串行：没有 release 构建与运行验证，不能进入文档收尾。

## 7. Subagent 协同规划

| 阶段 | 上下文依赖 | 并行收益 | 执行主体 | 决策理由 |
|------|-----------|---------|----------|----------|
| Phase 1 | 强（R8/JNI 诊断链） | 无 | 主线 | 单文件修改，隔离会话需重新装载全部证据 |
| Phase 2 | 强（CI 与 ADB 实时日志） | 低 | 主线 | 依赖本机 ADB 连接与日志判读，无法拆成并行子任务 |
| Phase 3 | 中 | 低 | 主线 | 文档必须与验证结果严格一致 |

**结论**：本轮不派发 Subagent。任务规模小、诊断上下文强、验证链路必须串行，委托的上下文重建成本高于收益。

## 8. 测试与验收策略

- **CI**：Android 工作流执行 `dart format --output=none --set-exit-if-changed lib test`、`flutter analyze`、`flutter test`，并构建签名 release APK；全部通过才进入运行验证。
- **运行验证**：ADB 安装签名 release APK，清空 logcat，冷启动，以登录页截图与无 `NoSuchMethodError` / `Unhandled Exception` 为主判据，`Fully drawn` 为辅助判据。
- **回归**：debug APK 已在本轮取证阶段确认可正常启动；release 修复后能进入登录页，说明 `SharedPreferences` 读取已成功。
- **外部验收**：用户在同一版本 Android 16 设备安装同一 APK 复核；若失败，按重开口径解档并回到 Phase 1。
- **本轮结果**：格式检查、静态分析与 87 项测试通过；签名 release APK 安装到 Android 12 模拟器，两次冷启动均进入登录页，logcat 无 `NoSuchMethodError` / `Unhandled Exception`，`Fully drawn` 各 1 条；Android 16 复核待用户执行。
