# Tasks：客户端复审吸收与残留收敛（Quick）

**关联 Plan**：无（Quick 模式跳过 Plan，故本归档仅含 Tasks.md）  
**状态**：DONE（2026-10-21 完成；`dart format` 0 变更，`flutter analyze` No issues found，`flutter test` 114 项通过）  
**日期**：2026-10-21  
**总计 Task**：4 个  
**执行主体**：主线

## 背景

上一轮交付 `.docs/10-21-v1`（`920883e`）的 Review 报告给出 92 分与 6 条问题。逐条对照代码核实：

- **缓存信封版本契约无测试**：成立。`_version` 是"版本不匹配整体失效"的唯一实现，`fromJson` 宽容解析会让旧结构静默读成全零，测试却仍全绿。补用例。
- **写盘时读取服务器地址存在串服竞态**：不成立。`_write` 在首个 `await` 之前同步读取 `_serverUrl()`，与加载器的代际检查处于同一同步执行段；单线程事件循环下 `updateServer` 无法插入两者之间。撤销该条。
- **成功通知等待缓存写盘**：属实但收益不足。写入是一次偏好存储调用；改为不等待会引入后台写乱序与测试不确定性，换取数毫秒的提前通知，违背最小差分。驳回。
- **后台鉴权只校验一次**：成立。离线冷启动校验失败后没有再次校验的触发点，被动浏览时已吊销的 token 会长期保留。在应用回到前台时补一次校验，保持既有 401/网络失败语义。
- **Project.md 术语表仍写"品牌启动态"**：成立。品牌启动页已删除，`booting` 仅剩最小进度指示。修正文档。
- **归档 Plan 版本记录为 `0.2.0+4`**：归档是历史快照，版本由后续发布提交改为 `0.1.5+4`，Project.md 已记录；不改写归档，避免篡改历史。

范围限定为 2 个源码文件、2 个测试文件与 `.docs/Project.md`。

## TASK-001：补缓存版本失效用例

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / 无
- **Description**：在 `app/test/core/ledger_cache_test.dart` 增加 `version: 2` 的三域条目，断言读取均返回 null。
- **Details**：三个键分别写入合法数据形状（配置对象、流水数组、统计对象），仅版本号为 2，确保 null 只能来自版本校验；沿用 `SharedPreferences.setMockInitialValues`。
- **Acceptance Criteria**：新用例通过；把 `_version` 校验从实现中删除时该用例失败。

## TASK-002：应用回到前台时复检会话

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P1 / 无
- **Description**：`SessionController` 增加 `revalidate()`，`LedgerApp` 监听 `AppLifecycleState.resumed` 并调用；新增 Widget 用例覆盖"复检 401 回登录"。
- **Details**：`revalidate()` 仅在 authenticated 时调用 `_verifySession(_generation)`，网络/超时保持会话，401 走既有 `expire()`；`_LedgerAppState` 混入 `WidgetsBindingObserver`，`initState` 注册、`dispose` 注销。用例用可切换的 `reject` 标志让首次校验返回 200、恢复后返回 401，断言回到登录页且 token 清除。不改动冷启动路径与缓存语义。
- **Acceptance Criteria**：新用例通过；恢复后 `checkAuth` 请求数 +1；401 后 `session.phase == locked` 且登录页可见；网络失败用例不回归。

## TASK-003：校正 Project.md 并记录复审取舍

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P1 / TASK-001、TASK-002
- **Description**：修正会话门术语，补充前台复检、测试项数与复审吸收条目。
- **Details**：术语由"启动校验中显示品牌启动态"改为"本地有 Token 即进入 Shell 并后台校验，启动恢复期间仅最小进度指示"；会话段补"回到前台重新校验"；测试段 112 项改为实际项数并列出新增用例；新增 2026-10-21 复审吸收条目，记录采纳与驳回理由。
- **Acceptance Criteria**：Project.md 与代码一致；无"品牌启动态"残留；测试项数与本地输出一致。

## TASK-004：门禁、归档与按路径提交

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-001 ~ TASK-003
- **Description**：执行格式、分析、全量测试，标注完成记录，归档至 `.docs/10-21-v2/`，按路径提交。
- **Details**：`dart format`、`flutter analyze`、`flutter test` 逐条取退出码；归档前确认同日目录无 `10-21-v2`；提交前 `git diff --cached --stat` 确认范围，使用路径限定提交，不触碰工作区既有的技能文件暂存与 `temp/` 未跟踪文件。
- **Acceptance Criteria**：三项门禁通过；`.docs/10-21-v2/Tasks.md` 存在且根目录无残留；`git show --name-only HEAD` 仅含本轮路径；既有暂存文件未被一并提交。

## 完成记录

- 完成日期：2026-10-21。
- 门禁：`dart format --output=none --set-exit-if-changed lib test` 0 变更（51 文件）；`flutter analyze` No issues found；`flutter test` 114 项通过（新增缓存版本失效 1 项、回到前台复检并 401 回登录 1 项）。
- 变更：`app/lib/features/auth/session_controller.dart`（新增 `revalidate`）、`app/lib/app.dart`（前台生命周期复检）、`app/test/app_cold_start_test.dart`、`app/test/core/ledger_cache_test.dart`、`.docs/Project.md`。
- 驳回项与依据见 `.docs/Project.md` 2026-10-21 复审吸收条目。
- 归档：`.docs/10-21-v2/`。
