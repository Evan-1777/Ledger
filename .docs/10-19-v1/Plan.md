# Plan：Ledger Android（Flutter + Material 3）

- **状态**：DONE（2026-10-19 完成）
- **日期**：2026-10-19
- **版本**：v1.2（用户决策记录）
- **交接状态**：已执行完成并归档。
- **回归测试结论**：Flutter 格式检查、静态分析、77 项测试与 Web 构建全部通过；Go 全量测试与构建通过；Web 端已完成真实后端自检；Android 安装包由 CI 产出（run 39260066449，`ledger-debug`，159,049,275 bytes），本机未构建。

---

## 1. 背景与目标

现有 Ledger 是 Go + SQLite 后端内嵌 React Web 前端的单二进制应用，业务已覆盖流水、记账、统计、资产负债、分类标签与渠道管理。本次在不改后端业务契约的前提下，新增一个 Flutter/Dart Android 客户端，复用现有 HTTP API、HMAC 会话与 SQLite 数据模型。

交付目标：

- Android 为主交付面，Web 为开发与自检面，两端均可编译；Android 安装包由 GitHub CI 产出。
- 覆盖现有核心业务：登录、流水、记账与编辑、删除、统计、资产负债、分类标签、渠道账户、主题与服务设置。
- UI/UX 采用 Material Design 3：色调表面、Material 组件、必要的过渡动效、Android 原生交互习惯。
- 工程结构为后续维护服务：API 契约集中、状态单一来源、组件复用、测试可运行、CI 可重复构建。
- 不引入无法同时运行于 Android 与 Web 的运行时依赖。

### 1.1 非目标

- 不改后端业务 API、数据库 schema、鉴权模型与统计口径。
- 不做离线数据库、后台同步、推送、生物识别、相机、文件导入导出。
- 不做多用户、多账本、iOS、桌面端、应用商店上架。
- 不引入代码生成、路由框架、图表库或重型状态管理框架。
- 不在本轮补充分页；流水沿用现有 100 条窗口，与 Web 一致。
- 不实现 Android 动态取色插件；以品牌蓝为种子生成固定 MD3 色板，保证 Web/Android 视觉一致。
- 不支持把服务部署在反向代理子路径下；服务器地址只填 origin，API 固定从 `/api/...` 访问。

### 1.2 完成定义

- `flutter analyze`、`dart format --set-exit-if-changed`、`flutter test` 全部通过。
- `flutter build web` 成功；本地可通过 Web 连接 Go 后端完成核心路径自检。
- GitHub Actions 成功产出可安装 APK；未配置签名密钥时明确产出 debug 验收包，配置后产出 release 签名包。
- 手机宽度 320–430dp、Android 15 edge-to-edge、浅色/深色、系统字体放大场景无溢出或不可点击控件。
- 用户可在 Windows x86_64 模拟器或真机通过 adb 安装并完成验收清单。

---

## 2. 现状与约束

### 2.1 可复用的后端能力

| 领域 | 端点 | 客户端用途 |
|---|---|---|
| 健康检查 | GET /api/health | 服务器地址连通性检查 |
| 鉴权 | POST /api/auth/login、GET /api/auth/check | 密码登录、启动时校验 30 天 Token |
| 渠道 | GET/POST/PUT/DELETE /api/payment-methods | 资产/负债账户的读取与 CRUD |
| 分类 | GET/POST/PUT/DELETE /api/categories | 支出/收入/系统分类的读取与 CRUD |
| 标签 | GET/POST/PUT/DELETE /api/tags | 分类下细分标签的读取与 CRUD |
| 流水 | GET/POST/PUT/DELETE /api/transactions | 流水筛选、记账、编辑、删除 |
| 统计 | GET /api/stats/summary | 收支、趋势、渠道分布与资产负债汇总 |

关键契约：

- 鉴权使用 Authorization: Bearer <token>，Token 为无刷新 HMAC 凭证，有效期 30 天。登录接口的 401 表示密码错误；启动 check 或受保护请求的 401 才表示会话过期并清 Token；网络/超时不视为会话失效。
- 流水金额在 API 中同时提供 amount/amount_cents 与 fee/fee_cents；统计与资产汇总只提供元单位浮点。流水列表/详情用分展示与校验，创建/更新请求仍按后端契约发送 amount/fee 浮点；统计/资产在模型边界统一舍入并展示，不为不存在的 cents 字段造适配层。流水金额带符号，支出为负，收入为正；还款与转账为正数。
- 转账必须指定转出与转入两个不同资产渠道，可带手续费；还款的目标是负债渠道，来源可为资产渠道或外部资金。
- 系统分类「债务偿还」「账户转账」及其系统标签不可修改、不可删除。
- 删除被账单引用的渠道、分类或标签返回 409；客户端需保留确认对话框并展示可理解的中文提示。
- 统计按服务端本地时区自然周/自然月计算；客户端只消费结果，不自行重算服务端口径。

### 2.2 现有 Web 交互基线

- 四段一级导航：流水、统计、资产、设置。
- 流水：当月支出/收入/结余，5 档筛选，按本地日期分组，行内编辑/删除。
- 记账：支出/收入/转账/还款四类，金额为主视觉，分类+标签、渠道、时间、转账手续费。
- 统计：当月结余 Hero、四项指标、构成图与趋势图两张并列 Panel、支付途径分布。
- 资产：净资产 Hero、资产分布条、资产/负债账户列表、金额隐藏。
- 设置：分类与标签、渠道与账户两个分区；分类调序、重命名、删除；细分标签抽屉；渠道新建/编辑/删除。

现有 UI 是 Fluent 2 + 玻璃材质；Android 版不复制该材质语言，保留信息架构与业务语义，视觉按 MD3 重建。

### 2.3 环境事实

- Flutter SDK 位于 /home/dev/flutter，版本 3.44.6，Dart 3.12.2；当前 shell 的 PATH 未包含它。
- 本机没有 JDK、Android SDK、Gradle 或 adb；按 SCOPE，本地不构建 Android 产物、不连接设备、不跑 Android 集成测试。
- Android 安装包由 GitHub Actions 构建；本地只做静态分析、单元/Widget 测试、Web 构建与 Web 浏览器自检。
- Flutter 启动时会尝试写入 SDK cache；当前 DSH 文件沙箱下该目录只读。执行阶段如遇此错误，需在获得授权后对 Flutter 命令开放 SDK cache 写入，不复制或重装 SDK。
- pub cache 位于 ~/.pub-cache，当前沙箱下不可写且未缓存 flutter_secure_storage；执行 `flutter create` / `pub get` 前导出 `PUB_CACHE=$PWD/.pub-cache`，并将 `.pub-cache/` 加入 `.gitignore` 与 `.dockerignore`。SDK cache 与 pub cache 是两处独立写入，不能只授权其一。
- 现有仓库没有 Flutter 工程；新增代码放在 app/，不改变 web/ 的运行方式。

---

## 3. 架构决策

| 决策项 | 选择 | 理由 | 未选方案与原因 |
|---|---|---|---|
| 工程位置 | 独立 app/ Flutter 工程 | 与 React Web 物理隔离，各自依赖与构建互不污染 | 在 web/ 内混放 Flutter（构建链冲突） |
| 应用标识 | com.evan1777.ledger | 与现有 GHCR 命名空间一致，可在首次发布前调整 | 临时随机包名（后续迁移成本高） |
| 设计系统 | Material 3，品牌蓝 #0078D4 作为 seed | 保留品牌识别，使用 MD3 角色与色调表面 | 复制 Web 的 Fluent 玻璃材质（与 Android 习惯冲突） |
| 色彩 | ColorScheme.fromSeed + 自定义金融语义 ThemeExtension | 组件颜色全部来自主题角色，支出/收入/转账/还款保持既有语义 | 页面内硬编码色值（破坏深浅主题与维护性） |
| 状态管理 | provider + ChangeNotifier，会话、账本、偏好三个控制器 | 依赖轻、边界清晰、易测试；账本数据保持单一来源 | Riverpod/Bloc（当前规模引入额外概念与样板） |
| 路由 | 单 Shell + IndexedStack，模态用 bottom sheet/dialog | 四段一级导航无需 URL 路由；保留滚动和表单状态 | go_router（无深链需求，属未证实抽象） |
| 网络 | 官方 http + 自建薄 API 客户端 | 双端支持，无平台特定代码；错误统一映射，401 按登录/会话场景分流 | Dio（功能过剩）、生成 SDK（无 OpenAPI 源） |
| 本地存储 | Token 用 flutter_secure_storage；服务器地址、主题、金额隐藏用 shared_preferences | 密钥材料与普通偏好分离；两端均有支持 | 全部用 SharedPreferences（Token 明文） |
| 服务器地址 | 运行时配置，首次登录输入，设置内可更换；不预置默认地址 | 同一 APK 可连接不同 VPS/局域网，无需重编；避免真实地址进入仓库与截图 | 编译期写死 URL（每次部署重构建） |
| 主题 | 浅色/深色/跟随系统，固定品牌色板 | 维护成本低，跨端一致 | 动态取色插件（Web 支持不完整） |
| 图表 | CustomPainter 自绘环形图与趋势图 | 复用 Web 的零图表依赖策略，完全受主题控制 | fl_chart（额外依赖与样式约束） |
| 数据刷新 | 登录后并行加载配置/流水/统计；变更后按域刷新 | 避免多份镜像状态与整页重载 | 每次操作全量刷新（请求与闪烁成本高） |
| 流水月度头条 | 消费统计接口的当月收支 | 与统计口径一致，避免第二次未筛选流水请求和 100 条截断 | 客户端从未筛选流水中重算（重复且可能漏数） |
| 列表分页 | 保持 100 条窗口 | 与 Web 行为一致，控制本轮范围 | 新增无限滚动（需扩展状态与交互，非本轮目标） |
| 网络传输 | release 仅 HTTPS，debug 允许本地明文 | Bearer Token 不应在正式包走明文；模拟器本地调试需要 HTTP | release 全局允许明文（安全边界失守） |
| Web 开发跨域 | 后端增加可选的单一开发 Origin CORS | Flutter Web dev server 无 Vite 式代理；不影响业务 API | 关闭浏览器安全策略（不可接受） |
| Android 构建 | GitHub Actions，Flutter 版本固定 | 本机无 Android 工具链；固定版本保证可重复 | 本地安装 JDK/Android SDK（违反 SCOPE） |
| 签名 | CI Secrets 注入；缺失时只产 debug 验收包 | 不提交密钥；首次验收不被签名配置阻塞 | 提交 debug keystore（不可接受） |
| 测试 | flutter_test + http/testing 假客户端 | 无额外测试框架；覆盖纯逻辑、表单与关键状态 | 依赖模拟器做集成测试（本机不可行） |

### 3.1 分层与依赖方向

- UI 层只依赖控制器暴露的只读状态与命令，不直接发 HTTP。
- 控制器依赖 API 客户端与本地存储接口，不依赖 Widget。
- API 模型集中定义，JSON 解析与序列化在同一层完成；页面不拼装请求体。
- 主题、格式化、语义色、共享组件位于 core 层，被各 feature 复用。
- 依赖方向：feature UI → controller → API/storage；core 不反向依赖 feature。

### 3.2 安全边界

- Token 不写入日志、不进入异常消息、不出现在界面。
- 服务器地址仅接受 http/https；release 模式拒绝 http。真实地址不写入仓库、CI、日志、文档或验收截图，只保存在用户设备的本地偏好中。
- Android 关闭自动备份，避免 Token 被系统云备份。
- 仅声明 INTERNET 权限；不申请相机、存储、通知等未使用权限。
- CI 只通过 Secrets 读取 keystore 与密码，构建结束删除临时文件；仓库不出现 key.properties、.jks、密码。

---

## 4. 信息架构与 MD3 设计方向

### 4.1 一级结构

| 优先级 | 区域 | 内容 | 容器 |
|---|---|---|---|
| P0 | 流水 | 月度收支、筛选、按日流水、记一笔 | 一级主画布 + 常驻 FAB |
| P1 | 记账 | 四类账单表单、分类/标签、渠道、时间、手续费 | 全高 bottom sheet |
| P1 | 统计 | 结余、指标、构成、趋势、支付分布 | 一级画布 |
| P1 | 资产 | 净资产、分布、账户与额度 | 一级画布 |
| P2 | 设置 | 分类标签、渠道账户、主题、服务器、退出 | 一级画布 + 二级 bottom sheet/dialog |

导航：

- 手机紧凑宽度（320–430dp）：底部 NavigationBar，四项；本轮不实现 NavigationRail 或平板断点。
- 记账 FAB 在四个一级页均可用；表单以 showModalBottomSheet 全高呈现。
- 资产页「管理」跳到设置页渠道分区，返回后保留数据状态。

### 4.2 视觉规则

- 背景使用 surface；内容卡片使用 surfaceContainerLow/surfaceContainer；浮动层与对话框使用更高层级色调，不依赖重阴影。
- Hero 使用 surfaceContainer 或 primaryContainer，是页面唯一的大号金额锚点；行内金额使用紧凑符号，不与 Hero 争夺层级。
- 支出、收入、转账、还款使用独立语义色与容器色，同时保留符号与文字，不依赖颜色单独传达状态。
- 主按钮使用全圆角；FAB 使用 MD3 默认 16dp 圆角；卡片 16dp，Hero 28dp，对话框 28dp。
- 字体使用 Roboto/系统中文回退，金额启用等宽数字；不引入网络字体。
- 间距按 4/8dp 刻度；可点击目标不小于 48dp；系统字体放大 2 倍仍可操作。Demo 的 CSS 尺寸只用于视觉比例；Flutter 实现通过 MaterialTapTargetSize.padded 或透明命中区保证 48dp，不照抄 32–44px 的图标/Chip 视觉尺寸。
- 动效使用 MD3 标准/强调曲线，底部弹层与页面切换使用 Material 默认过渡；不添加装饰性持续动画。
- 空态给出直接动作；加载用骨架；错误给重试；所有破坏性操作使用应用内确认。
- 不在界面放置教学、功能解释、演示标注或占位文案。

### 4.3 关键交互

- 启动：读取 Token 与服务器地址 → 调用鉴权检查 → 成功进入 Shell；check 401 进入连接/解锁页；网络失败显示重试并保留 Token。
- 登录：服务器地址 + 管理员密码；401 显示内联错误；网络错误区分「无法连接服务器」。
- 记账类型：四段 SegmentedButton；编辑已有账单时锁定类型。
- 分类与标签：记账表单内点击字段，在原 sheet 内联展开分类网格与标签行；不打开第二层 modal。
- 转账：转出/转入资产账户互斥选择；手续费默认折叠，选择后展开。
- 还款：还入负债账户；资金来源为资产账户或「外部/未记录资金」。
- 删除：确认对话框，显示摘要；409 或失败使用 SnackBar，不丢失列表上下文。
- 资产金额隐藏：眼睛图标切换，持久化，仅作用于资产页。
- 设置：分类类型分段、行尾溢出菜单、系统分类单独面板；渠道按资产/负债分组；表单使用底部弹层。
- 主题：设置内三档选择（跟随系统/浅色/深色），立即生效并持久化。
- 统计图表：分类构成与近 6 月趋势共用一张图表卡，以「构成 / 趋势」二段切换，避免单屏纵向堆叠与图表标题被截断。

---

## 5. 阶段划分

### Phase 1：工程基础、鉴权与 Shell

| 项目 | 内容 |
|---|---|
| **输入** | 现有 API 契约、Flutter 3.44.6、无 Android 工具链的环境 |
| **输出** | app/ 工程、MD3 主题与语义色、API 模型与客户端、安全会话、连接/解锁页、四段 Shell、开发 CORS、Android 清单与 CI 骨架 |
| **验收标准** | 静态分析与基础测试通过；Web 构建成功；可用本地 Go 服务完成登录/鉴权检查；Android 工作流配置可解析且本地命令通过；真实 APK 留到 Phase 5 推送后验证；release 清单不允许明文 HTTP |

### Phase 2：流水与记账闭环

| 项目 | 内容 |
|---|---|
| **输入** | Phase 1 的 API 客户端、会话与主题 |
| **输出** | 流水月度头条、5 档筛选、按日分组、编辑/删除；四类记账表单、手续费、时间、校验与失败保留草稿 |
| **验收标准** | 四类账单均可创建并刷新列表与统计；编辑锁定类型；删除有确认；金额符号与渠道约束正确；错误有可理解提示 |

### Phase 3：统计与资产

| 项目 | 内容 |
|---|---|
| **输入** | Phase 1 的统计模型、Phase 2 的刷新链路 |
| **输出** | 统计 Hero、四项指标、构成/趋势切换图表卡、支付分布；资产负债 Hero、分布条、账户列表、额度、金额隐藏、管理跳转 |
| **验收标准** | 数值与后端/Web 一致；零分母与负余额不产生 NaN/负占比；空态、加载态、错误态完整；图表有语义标签与文字图例 |

### Phase 4：设置、平台细节与可访问性

| 项目 | 内容 |
|---|---|
| **输入** | Phase 1–3 的页面与控制器 |
| **输出** | 分类/标签 CRUD 与调序、渠道 CRUD、系统项保护、主题与服务器设置、退出；图标与启动背景、edge-to-edge、返回键、适配与无障碍 |
| **验收标准** | 设置全部操作可用；409 正确呈现；系统项无修改/删除入口；320dp、深色、字体放大均无溢出；TalkBack 语义完整 |

### Phase 5：验证、CI 与文档

| 项目 | 内容 |
|---|---|
| **输入** | 完整客户端与既有文档 |
| **输出** | 单元/Widget 测试补齐、Web 自检记录、Android CI 发布链路、签名说明、Project.md 同步、Plan/Tasks 归档与提交 |
| **验收标准** | 本地检查全绿；Web 核心路径通过；推送后 CI APK 可下载（无法推送时明确记录未运行边界）；用户模拟器验收清单明确；文档与代码一致；无密钥入库 |

### 5.1 阶段依赖

```
Phase 1 ──→ Phase 2 ──→ Phase 3 ──→ Phase 4 ──→ Phase 5
                  └──────────────┘
```

Phase 2 与 Phase 3 都依赖 Phase 1 的模型与控制器；Phase 3 的资产页需要 Phase 2 的刷新链路；Phase 4 依赖前三阶段的数据操作；Phase 5 最后执行。

---

## 6. 风险与应对

| 风险 | 等级 | 应对 |
|---|---|---|
| 本机无法运行 Android，CI 构建通过不等于运行时正确 | 高 | CI 产出 debug APK 供用户 adb 验收；交付时列出权限、HTTPS、Insets、字体、不同 API 版本的待验证项 |
| 现有部署只有 HTTP，release 包无法连接 | 高 | 将 HTTPS 作为正式包前置条件；本地/模拟器用 debug 包连接 HTTP；在 Project.md 记录部署要求 |
| Flutter SDK cache 与默认 pub cache 在当前沙箱不可写 | 中 | SDK cache 申请一次命令级授权；`PUB_CACHE` 指向仓库根 `.pub-cache`；不复制/重装 SDK；遇到权限失败立即说明 |
| 签名 Secrets 未配置，无法产出正式包 | 中 | CI 自动降级为 debug 验收包并明确命名；配置 Secrets 后同一工作流产出 release |
| Flutter Web 与 Go 服务跨域 | 中 | 增加可选单 Origin CORS，默认关闭；仅开发时设置；生产不使用 |
| 记账弹层内容较长，键盘弹出时底部保存按钮被遮挡 | 中 | 表单使用可滚动区域与 `MediaQuery.viewInsets` 避让；保存栏固定在安全区上方；测试 320dp 与 2.0 字体缩放 |
| API 模型双端手工同步漂移 | 中 | 模型集中、JSON fixture 测试、契约变更时同步 Web/Flutter；Project.md 记录 API 变更 |
| 图表自绘在窄屏/大字体下标签碰撞 | 中 | 环形图配文字图例；趋势图仅保留月份标签与图例；用 LayoutBuilder 限宽并测试 320dp |
| 依赖插件不支持 Web 或 Android | 中 | 引入前核对两端支持；Token 与偏好存储均通过接口注入，测试用内存实现 |
| 流水仅 100 条导致历史不可见 | 低 | 与 Web 保持一致，记录为已知限制，后续单独设计分页 |
| 全局状态过大导致维护困难 | 低 | 会话、账本、偏好三分；账本控制器按领域方法组织；页面不自行维护业务数据副本 |

### 6.1 外部依赖

- Android 签名 Secrets：用户当前未配置；首轮仅验收 debug APK，release 分支保留到 Secrets 补齐后启用。
- 服务器地址：由用户在登录页自行填写；release 验收使用 HTTPS，不在仓库、CI、日志或截图中记录真实地址。
- 用户在 Windows x86_64 模拟器或真机完成 adb 安装与运行验收；本机不执行。
- 浏览器自检优先连接用户提供的 9222 实例；不可用时仅做本地无头截图/静态检查，不启动长期服务。

---

## 7. Subagent 协同规划

| 阶段 | 上下文关联 | 并行收益 | 执行主体 | 判定 |
|---|---|---|---|---|
| Phase 1 基础/鉴权/Shell | 强（全局契约、主题、状态边界） | 无（后续全部依赖） | 主线 | 隔离会话需重复装载全部契约，收益不足 |
| Phase 2 流水/记账 | 强（依赖 Phase 1 状态与刷新链路） | 可与 Phase 3 并行，但共享控制器与模型 | 主线 | 并行会产生共享文件写冲突与 UI 不一致风险 |
| Phase 3 统计/资产 | 强（依赖统计模型与主题） | 中等 | 主线 | 图表与语义色需与主线同步推演 |
| Phase 4 设置/平台 | 强（依赖全部数据操作与系统保护规则） | 低 | 主线 | 跨模块交互密集，主线处理更稳 |
| Phase 5 测试/CI/文档 | 中（前序产物已定型） | 中 | 主线 | 需要根据真实失败修正代码，委托会拉长反馈链 |

**结论**：本轮不派发 Subagent。Greenfield 工程从主题、模型、状态到页面强耦合，隔离会话重新建立上下文的成本高于并行收益；待应用稳定后，独立的可访问性审计或测试补强再按三维模型评估。所有 Task 执行主体为主线。

---

## 8. 测试与验收策略

### 8.1 自动化

- 纯函数单元测试：金额格式化、日期分组、月度头条、资产派生、统计派生、类型到渠道规则。
- API 客户端测试：URL 规范化、Bearer 头、登录 401 / 会话 401 / 网络超时的分流、JSON 解析、409 错误映射。
- Widget 测试：连接/解锁、流水空态、记账校验、转账渠道互斥、编辑类型锁定、系统分类保护、删除确认。
- 控制器测试：快速切换流水筛选时，旧请求响应不得覆盖新筛选结果。
- Web 构建：flutter build web。
- 本地静态检查：dart format、flutter analyze、flutter test。
- CI：同套检查 + APK 构建；不跑 Android 模拟器集成测试。

### 8.2 用户侧 Android 验收清单

- 安装包能安装并启动，状态栏/导航栏不遮挡内容。
- 首次连接 HTTPS 服务器，地址由用户自行填写；登录成功；错误密码与不可达地址有提示，交付物不记录真实地址。
- 创建支出、收入、转账、还款各一笔；流水金额、元信息、日小计与月度头条正确。
- 编辑与删除账单；删除后统计与资产同步刷新。
- 资产页隐藏金额、切换账户管理；设置内新增/编辑/删除分类、标签、渠道；系统分类不可编辑。
- 浅色/深色/跟随系统切换；系统字体放大；返回键关闭记账弹层并回到当前页。
- 应用重启后 Token 仍有效；退出后回到连接页。

### 8.3 待验证项（本地不可完成）

- Android 真机/模拟器的明文 HTTP 限制。
- 系统返回键、输入法避让、edge-to-edge Insets。
- Android 12+ 启动画面与图标裁切。
- 不同屏幕尺寸、字体缩放、TalkBack。
- CI 签名产物的升级安装与签名一致性。
- Flutter Web 在真实 Chrome 下的 CORS 与安全上下文行为。

---

## 9. 交付物

- 新增 app/ Flutter 工程与 Android/Web 构建配置。
- 新增 Android CI 工作流与 debug 产物；release 构建配置保留，待签名 Secrets 补齐后启用。
- 后端仅新增可选的开发 CORS 配置与测试，无业务 API 变更。
- 根 Makefile 增加 Flutter 分析/测试/Web 构建入口。
- .docs/Project.md 同步架构、依赖、运行方式、环境变量与决策记录。
- 规划期 Demo：`temp/android-md3-demo.html`（浅色/深色、连接、流水、支出录入、统计、资产、设置）；转账/还款表单的字段与约束由 TASK-012 在 Flutter 中实现，Demo 不重复展开这两个状态；服务器地址使用 `ledger.example.com` 占位，不代表真实服务。交付完成后 Demo 已清理，最终实现见 `app/`。
- Plan.md / Tasks.md 按执行日归档到 `.docs/MM-DD-vN/`。

---

## 10. 执行结果（2026-10-19）

**状态**：DONE；26 个 Task 全部完成。

| 检查 | 命令 | 结果 |
|---|---|---|
| Dart 格式 | `cd app && dart format --output=none --set-exit-if-changed lib test` | 47 个文件，0 个变更 |
| 静态分析 | `cd app && flutter analyze` | No issues found |
| Flutter 测试 | `cd app && flutter test` | 77 项通过（API、会话、控制器、纯函数、登录/流水/统计/资产/设置/Shell/记账弹层 Widget、320dp + 2 倍字体） |
| Web 构建 | `cd app && flutter build web` | `app/build/web` 构建成功 |
| Go 测试 | `go test ./...` | `internal/db`、`internal/server`、`web` 通过；CORS 4 项测试通过 |
| Go 构建 | `go build -o /tmp/ledger-build ./cmd/server` | 通过 |
| Web 自检 | 临时 DB + `LEDGER_CORS_ORIGIN=http://localhost:5174` + Chrome 390×844 | 登录、记账、流水、统计、资产、设置可用；刷新后会话恢复；控制台无错误 |
| 生产构建加载 | 静态服务 `build/web`，Chrome 加载 | 页面加载成功，控制台无错误 |
| CI | 推送 master 触发 Android 与 Docker 工作流 | Android run [39260066449](https://github.com/Evan-1777/Ledger/actions/runs/39260066449) 成功，`ledger-debug` artifact 可下载；Docker run 39260066609 成功 |

**未在本机完成**：Android APK 构建、安装、启动画面、edge-to-edge、输入法与系统返回键、TalkBack 与真机字体缩放。本机无 JDK、Android SDK、Gradle 与 adb，按用户确认的边界交由 CI 与 Windows x86_64 模拟器/真机验收。CI 已运行：Android 工作流 run 39260066449 成功，产出 `ledger-debug`（`app-debug.apk`，159,049,275 bytes，含 arm64-v8a、armeabi-v7a、x86_64）；Docker 工作流 run 39260066609 成功。签名 Secrets 未配置，故本轮仅产出 debug 验收包；配置后同一工作流产出 release。APK 安装与真机交互仍待用户验收。

**实现补充**：流水筛选使用自绘 MD3 胶囊替代 `FilterChip`，修复 Flutter Web 中文标签被裁切为单字的问题；统一 `VisualDensity.standard` 与 48dp 触控目标；日小计按“支出/收入”分组换行，避免 390dp 下金额被裁切。

---

## 11. 用户已确认决策（2026-10-19）

- 应用标识：`com.evan1777.ledger`，不再变更。
- 服务器地址：不预置、不写入仓库、CI、日志、文档或验收截图；由用户在登录页自行填写。release 仅 HTTPS，debug 可按需使用本地 HTTP。
- Android 签名 Secrets：当前未配置；首轮交付仅验收 debug APK，不声称 release 已产出；Secrets 补齐后再启用 release 构建。
