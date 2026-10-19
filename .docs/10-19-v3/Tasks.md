# Tasks：修复 Android Release 版本启动卡在启动画面

**关联 Plan**：`Plan.md` —— Android Release 启动修复 v1.1  
**总计 Task**：10 个（含 1 个已完成的取证 Task、1 个外部验收 Task）  
**评审修订**：已吸收 2026-10-19 Review 的构建期证据、失败分流、ADB 健壮性与归档重开口径

## 验证环境（本轮专用）

- ADB 端点：`127.0.0.1:16416`（MuMu 模拟器，Android 12 / API 32 / x86_64 / V2241A）；备用端点 `127.0.0.1:5557` 或 `emulator-5556`。
- `adb` 位于临时目录 `.tmp-tools/platform-tools/adb`，不纳入版本控制。
- 每次 bash 调用都是独立 shell，adb daemon 不会跨调用保留：必须在**同一个 shell** 内完成 `start-server`、`connect` 与设备命令。
- `/home/dev/.android` 位于只读文件系统：导出 `HOME` 与 `ANDROID_USER_HOME` 到可写临时目录。
- 包名 `com.evan1777.ledger`；当前模拟器上安装的是取证用的 debug 包，安装 release 前先卸载。

---

## TASK-000：复现并确认根因

- **Status**：DONE
- **Executor**：主线
- **Description**：在 Android 12 模拟器安装 release APK，启动并抓取 logcat；再用同机 debug APK 对照，确认问题只在 R8 收缩后的 release 构建出现。
- **Details**：
  - release APK：`ledger-0.1.0.apk`，启动后进程存活，窗口只剩启动背景（用户设备上表现为放大的启动图标）。
  - logcat 关键行：`Unhandled Exception: PlatformException(... NoSuchMethodError ... SharedPreferencesApiRegistrar.getAll(...) ...)`。
  - debug APK：模拟器正常进入登录页，无上述异常。
  - 上游结论一致：[flutter/flutter#194649](https://github.com/flutter/flutter/issues/194649)；修复 PR [flutter/packages#13311](https://github.com/flutter/packages/pull/13311) 尚未发布。
- **Acceptance Criteria**：
  - release 复现日志已保存并定位到 `SharedPreferences.getInstance()`。
  - debug/release 对照成立，排除启动主题、APK 缺件与系统版本因素。

---

## Phase 1：release 构建保留 Kotlin JNI 依赖类

### TASK-001：新增 app 级 ProGuard keep 规则

- **Status**：PENDING
- **Executor**：主线
- **Description**：新增 `app/android/app/proguard-rules.pro`，保留 `shared_preferences_android 2.5.0` 的 Pigeon JNI 依赖的六个 Kotlin 运行时类。
- **Details**：
  - 文件内容：
    ```proguard
    # shared_preferences_android 2.5.0 calls Kotlin through Pigeon JNI. Its bindings
    # resolve kotlin.coroutines.Continuation and related classes by name, but R8
    # renames them in release builds. The descriptor used by the Dart side then no
    # longer matches, so SharedPreferences.getInstance() throws NoSuchMethodError
    # before runApp() and the app stays on the launch screen.
    # Keep these classes until the plugin ships consumer rules:
    # https://github.com/flutter/flutter/issues/194649
    # https://github.com/flutter/packages/pull/13311
    -keep class kotlin.Unit { *; }
    -keep class kotlin.Result { *; }
    -keep class kotlin.Result$Failure { *; }
    -keep class kotlin.coroutines.Continuation { *; }
    -keep class kotlin.coroutines.intrinsics.CoroutineSingletons { *; }
    -keep class kotlin.coroutines.intrinsics.IntrinsicsKt { *; }
    ```
  - 不修改 `app/android/app/build.gradle.kts`：Flutter Gradle 插件在 release build type 中会自动加入 `projectDir/proguard-rules.pro`。
  - 自动纳入行为已核实：`/home/dev/flutter/packages/flutter_tools/gradle/src/main/kotlin/FlutterPlugin.kt:219-225` 在 release 开启收缩时依次加入默认规则、`flutter_proguard_rules.pro` 与 `projectDir/proguard-rules.pro`。`app/android/local.properties` 的 `.flutter-sdk` 旧路径只影响本地 Gradle，CI 使用 setup-flutter 的 SDK，不影响该结论。
  - 不新增依赖、不改版本锁、不关闭 R8。
- **Acceptance Criteria**：
  - 文件存在，`grep -c '^-keep class' app/android/app/proguard-rules.pro` 输出 `6`。
  - `git diff --check` 无输出。
  - 未修改 `build.gradle.kts` 与 `pubspec.lock`。

### TASK-002：执行本地静态检查

- **Status**：PENDING
- **Executor**：主线
- **Description**：在提交前核对规则内容与工作区差异，确认没有混入无关文件。
- **Details**：
  - `git diff --check`
  - `grep -n '^-keep class' app/android/app/proguard-rules.pro`
  - `git status --short`：确认本轮只新增 `app/android/app/proguard-rules.pro`、`Plan.md`、`Tasks.md`，不触碰工作区既有的暂存技能文件。
  - Flutter 格式、分析、测试由 Android CI 执行；本机 Flutter SDK 为只读挂载，不强制本地运行。
- **Acceptance Criteria**：
  - 规则行数与内容符合 TASK-001。
  - 无空白错误、无意外文件变更。

---

## Phase 2：CI release 构建与 ADB 运行验证

### TASK-003：提交修复并运行 CI 签名 release 构建

- **Status**：DONE
- **Executor**：主线
- **Description**：在临时验证分支提交 keep 规则，推送触发 Android 工作流，等待签名 release 构建完成并下载 artifact。
- **Details**：
  - 创建分支：`git checkout -b fix/android-release-splash`。
  - 只提交规则文件，避免带出工作区既有暂存内容：
    ```bash
    git commit -- app/android/app/proguard-rules.pro \
      -m "fix(app): 保留 shared_preferences JNI 依赖的 Kotlin 运行时类" \
      -m "R8 在 release 构建中重命名 kotlin.coroutines.Continuation 等类，导致 shared_preferences_android 2.5.0 的 Pigeon JNI 描述符失配，main() 在 SharedPreferences.getInstance() 处抛出 NoSuchMethodError，runApp 未执行，启动画面持续停留。Refs: flutter/flutter#194649"
    ```
  - 推送：`git push -u origin fix/android-release-splash`；推送会按 `app/**` 路径触发 `Android` 工作流。
  - 查询运行：`gh run list --repo Evan-1777/Ledger --branch fix/android-release-splash --workflow Android --limit 3`。
  - 等待完成：`gh run watch <run-id> --repo Evan-1777/Ledger --exit-status`（耗时约 9–10 分钟；必要时用后台 job）。
  - 下载产物：`gh run download <run-id> --repo Evan-1777/Ledger -n ledger-release -D .tmp-tools/ci-release`。
- **Acceptance Criteria**：
  - 工作流结论为 `success`。
  - artifact 名称为 `ledger-release`，内部为 `ledger-release.apk`（不是 `ledger-debug` / `ledger-debug.apk`）。
  - 构建日志包含签名 release 构建，未退化到 debug 分支。
  - 构建期辅助证据：`unzip -p ci-release/ledger-release.apk 'classes*.dex' | strings | grep -c 'kotlin/coroutines/Continuation'` 与 `... | grep -c 'SharedPreferencesApiRegistrar'` 均至少为 1；该证据只证明类名未被重命名，最终以 TASK-004 运行结果为准。
  - 若 Secrets 缺失、产物为 debug 或上述证据缺失：停止并报告，不进入运行验证；不进入 Phase 3，回规划段修订 Plan/Tasks。
- **完成记录**：2026-10-19 分支 `fix/android-release-splash` 提交 c4f1a80；CI run [39280755463](https://github.com/Evan-1777/Ledger/actions/runs/39280755463) 完成签名 release 构建并上传 `ledger-release`（zip SHA-256 `0fba804e…ab06`，APK 56,418,150 bytes）。GitHub Actions 状态接口在该时段降级，run/job 的 `status` 一度停留在 `queued`，随后恢复为 `success`；job 日志显示 `HAS_KEYSTORE=true`、87 项测试通过、`Built app-release.apk` 与 artifact 上传完成，APK 内 `CoroutineSingletons` 类描述符计数由 0 增至 2。

### TASK-004：在 Android 12 模拟器验证 release APK

- **Status**：DONE
- **Executor**：主线
- **Description**：卸载取证用 debug 包，安装 CI 签名 release APK，冷启动并抓取 logcat、窗口焦点与截图。
- **Details**：
  - 连接与安装（同一个 shell 内执行）：
    ```bash
    cd /home/dev/projects/Ledger/.tmp-tools
    export HOME=$PWD ANDROID_USER_HOME=$PWD/.android
    ./platform-tools/adb start-server
    ./platform-tools/adb connect 127.0.0.1:16416
    ./platform-tools/adb -s 127.0.0.1:16416 uninstall com.evan1777.ledger || true
    ./platform-tools/adb -s 127.0.0.1:16416 install -r ci-release/ledger-release.apk
    ```
  - 冷启动与取证：
    ```bash
    ./platform-tools/adb -s 127.0.0.1:16416 logcat -c
    ./platform-tools/adb -s 127.0.0.1:16416 shell am force-stop com.evan1777.ledger
    ./platform-tools/adb -s 127.0.0.1:16416 shell am start -W -n com.evan1777.ledger/.MainActivity
    sleep 10
    ./platform-tools/adb -s 127.0.0.1:16416 shell pidof com.evan1777.ledger
    ./platform-tools/adb -s 127.0.0.1:16416 exec-out screencap -p > screen_release_fixed.png
    ./platform-tools/adb -s 127.0.0.1:16416 logcat -d -v threadtime > logcat_release_fixed.txt
    ```
  - 登录页标签已核对：`app/lib/features/auth/login_screen.dart:108/130/144` 分别为“登录”“服务器地址”“管理员密码”；截图判定以这三个可见文本为准。
  - 判定：
    ```bash
    grep -c 'NoSuchMethodError' logcat_release_fixed.txt   # 期望 0
    grep -c 'Unhandled Exception' logcat_release_fixed.txt # 期望 0
    grep -c 'Fully drawn' logcat_release_fixed.txt         # 辅助判据，期望 >= 1
    ```
- **Acceptance Criteria**：
  - 主判据：截图显示登录页（“登录”“服务器地址”“管理员密码”），且 logcat 中 `NoSuchMethodError` 与 `Unhandled Exception` 均为 0。
  - 辅助判据：process id 存在，窗口焦点为 `com.evan1777.ledger/.MainActivity`，`Fully drawn` 至少 1 条。
  - 任一失败即停，不进入 Phase 3；回规划段修订 Plan/Tasks 后再执行，不在执行中自行扩散修复。
- **完成记录**：2026-10-19 安装同一 artifact；冷启动 `LaunchState: COLD`，PID 2773，`NoSuchMethodError` 0、`Unhandled Exception` 0、`Fully drawn` 1，焦点 `com.evan1777.ledger/.MainActivity`，截图显示“登录 / 服务器地址 / 管理员密码”。

### TASK-005：冷启动回归与偏好读取验证

- **Status**：DONE
- **Executor**：主线
- **Description**：再次强制停止并冷启动，确认 `SharedPreferences` 在第二次启动仍可正常读取，应用稳定进入登录页。
- **Details**：
  - 重复 `am force-stop` → `am start -W` → `sleep 8` → 截图 → logcat。
  - 确认第二次启动仍进入登录页，无 `NoSuchMethodError` / `Unhandled Exception`。
- **Acceptance Criteria**：
  - 两次冷启动均到达登录页。
  - 无启动异常；进程存活。
  - debug APK 的既有启动结论不变（本轮不改 Dart 代码，无需重复安装 debug）。
- **完成记录**：2026-10-19 第二次冷启动 PID 2896，同为 0 异常、`Fully drawn` 1，截图仍为登录页。

---

## Phase 3：文档、清理与归档

### TASK-006：更新 Project.md

- **Status**：PENDING
- **Executor**：主线
- **Description**：将根因、keep 规则、验证结果与移除条件写入 `.docs/Project.md`，保持单一事实来源。
- **Details**：
  - 在“约束与决策”追加 2026-10-19 条目：release R8 重命名 Kotlin 运行时类 → Pigeon JNI 描述符失配；新增 `app/android/app/proguard-rules.pro` 六个 keep 规则；Flutter Gradle 插件自动纳入；Android 12 模拟器验证结果；上游 issue/PR；插件发布 consumer rules 后移除。
  - 在“Android 客户端”的发布/测试段补充：release APK 已在 Android 12（API 32，x86_64）冷启动进入登录页；Android 16 由用户安装同一 APK 复核。
  - 不复制完整规则清单到 Project.md，指向规则文件即可。
- **Acceptance Criteria**：
  - Project.md 与实际代码、CI 运行、ADB 验证一致。
  - 明确记录移除条件，避免规则永久滞留。
  - 无过期或推测性表述。

### TASK-007：清理临时文件

- **Status**：PENDING
- **Executor**：主线
- **Description**：删除取证与验证产生的临时目录与产物，保持工作区干净。
- **Details**：
  - 删除 `.tmp-tools/`（adb、platform-tools.zip、debug/release APK、截图、logcat、dex 解析脚本）。
  - 删除任何临时 APK、日志、截图；确认 `git status` 不显示临时文件。
  - 清理前检查暂存区：`git diff --cached --name-only` 不得包含 `.tmp-tools`、`platform-tools` 或 `.apk`；不新增 `.gitignore` 规则，临时目录最终删除。
  - 不删除工作区既有的与本轮无关的暂存技能文件。
- **Acceptance Criteria**：
  - `git status --short` 中无 `.tmp-tools` 或本轮临时产物。
  - 仓库根目录仅保留本轮应提交的文档与代码变更。

### TASK-008：标记完成、归档并提交

- **Status**：PENDING
- **Executor**：主线
- **Description**：在 Plan/Tasks 标注完成状态与回归结论，归档到 `.docs/10-19-v3/`，提交本轮文档。
- **Details**：
  - Plan.md / Tasks.md 顶部状态改为 `DONE`，补充完成日期、CI run ID、Android 12 验证结论与 Android 16 外部待验项。
  - `mkdir -p .docs/10-19-v3 && mv Plan.md Tasks.md .docs/10-19-v3/`。
  - 将修复分支合并到 master：`git checkout master && git merge --ff-only fix/android-release-splash`。
  - 只提交本轮路径：
    ```bash
    git commit -- .docs/Project.md .docs/10-19-v3/Plan.md .docs/10-19-v3/Tasks.md \
      -m "docs(app): 记录 Android release 启动修复与验证结论"
    ```
  - Android 16 复核失败的重开口径：若 TASK-009 未通过，将 `.docs/10-19-v3/Plan.md` 与 `Tasks.md` 移回根目录，状态改回 `PENDING`，回到 Phase 1 重新定位；归档目录内不直接修改代码。
  - 推送 master 前向用户确认（会触发 Docker 发布链路）；若用户要求暂缓，保留本地提交与验证分支并说明。
- **Acceptance Criteria**：
  - `.docs/10-19-v3/` 同时含 `Plan.md` 与 `Tasks.md`，根目录无残留。
  - 提交只含本轮路径，未混入既有暂存文件。
  - 修复提交与文档提交均存在；master 指向包含修复的提交。
  - 若要推送，推送后 Android 工作流在 master 上再次通过。

### TASK-009：Android 16 外部复核

- **Status**：PENDING
- **Executor**：用户（外部验收）
- **Description**：用户在同一版本 Android 16 设备安装 CI 签名 release APK，确认启动进入登录页。
- **Details**：
  - 使用 TASK-003 的 `ledger-release` artifact 或发布 APK。
  - 冷启动，观察是否仍停留在启动画面。
  - 若仍复现，提供 logcat（`adb logcat -d`）与设备 Android 版本。
- **Acceptance Criteria**：
  - Android 16 冷启动进入登录页。
  - 无 `NoSuchMethodError` / `Unhandled Exception`。
  - 若未通过，回到 Phase 1 重新定位，不标记 Task DONE；若已归档，按 TASK-008 的重开口径解档。
