# Project

> 项目的单一事实来源，供 Agent 动手前建立全局认知。定位与设计原则见 `SCOPE.md`，工作流规则见 `AGENTS.md`。

## 概述

- **定位**：轻量高颜值个性化记账 Web 应用，基于 Go + React + Vite + Tailwind + SQLite，单二进制交付。
- **阶段**：核心记账业务闭环、基础设置（资产与负债渠道双列工作台及细分标签专属抽屉）、Fluent 2 宏观资产负债/收支统计看板、负债还款全链路闭环、移动端 100dvh 动态视口重塑、收支分类严格分流与双向账户转账全链路闭环、移动端通知提示 (Toast) 视口自适应修复、转账手续费可选纯资产调整闭环、Fluent 2 成品级 UI/UX 全站重构（四层材质令牌体系、共享原子构件层、自绘 SVG 图表、应用内确认对话框）、复审修复轮，以及金额双重焦点归位（@layer base 键盘轮廓可被 outline-none 覆盖）、细分标签抽屉与删除确认视口级 Portal 挂载（桌面贴右、遮罩全屏、移动端底部面板）、抽屉生命周期分层键盘仲裁与新增失败草稿保留已交付，支持单二进制独立运行与 Docker 部署。
- **非目标**：多租户账号管理体系、复杂云财务集成、重型商业账务核算

## 环境与运行

- **平台**：Linux x86_64（本地编译与测试），云端 CI 负责发布构建
- **运行时**：
  - 后端：Go 1.27
  - 前端：Node.js 24 + npm 11
  - 存储：SQLite（纯 Go 驱动 `modernc.org/sqlite`，无 CGO 依赖）
- **环境变量**：
  - `LEDGER_PORT`：HTTP 服务监听端口（默认 `8080`）
  - `LEDGER_DB_PATH`：SQLite 数据库路径（默认 `data/ledger.db`）
  - `LEDGER_ADMIN_PASSWORD`：管理员密码（默认 `admin123`，未设置时控制台打印安全告警）
  - `LEDGER_TOKEN_SECRET`：HMAC 会话签名密钥（默认自动生成 32 字节随机密钥）
- **版本管理**：Git；Conventional Commits（英文类型前缀 + 中文详细描述）
- **运行**：
  - 全流程构建：`make build`（生成 `bin/ledger`）
  - 单独运行后端：`make dev-server` 或 `go run ./cmd/server`
  - 单独运行前端开发服务：`make dev-web` 或 `cd web && npm run dev`
  - 启动二进制：`bin/ledger`（默认监听 `http://localhost:8080`）
- **测试**：
  - 全量测试：`make test`（涵盖后端 `go test -v ./...` 与前端 `tsc -b --noEmit`）
- ★ 数据库默认位于 `data/ledger.db`，测试通过临时目录进行，不污染真实数据
- ★ 前端开发服务器通过 Vite 代理将 `/api` 请求转发至后端口 `8080`

## 结构

```
Ledger/
├─ cmd/
│  └─ server/
│     └─ main.go             # 应用程序唯一入口，加载配置、初始化 DB、注册路由并处理优雅退出
├─ internal/
│  ├─ config/
│  │  └─ config.go           # 环境变量配置加载（PORT, DB_PATH, ADMIN_PASSWORD, TOKEN_SECRET）
│  ├─ db/
│  │  ├─ db.go               # SQLite 连接初始化（WAL、PRAGMA、5张数据表含 system_meta 迁移、payment_methods/transactions/categories 探针热迁移含 fee_cents、系统还款与转账分类/标签智能注入）
│  │  └─ db_test.go          # 数据层初始化、老库平滑升级、防复活幂等性、外键约束与探针热迁移测试
│  └─ server/
│     ├─ server.go           # HTTP 路由注册分发、健康检查与 SPA 静态文件回退服务
│     ├─ auth.go             # 管理员密码登录、防爆破时延、HMAC Token 签发与 RequireAuth 访问守卫
│     ├─ settings.go         # 资产/负债渠道（payment_methods）、类型（categories 支持 type 字段）与标签 CRUD API、409 账单引用删除拦截与系统分类/标签 ID 级不可变保护
│     ├─ transactions.go     # 单笔账单录入/更新/删除/列表查询，金额带符号分位转换、还款与转账双渠道校验、转账手续费原子存取与负数拦截、收支隔离筛选
│     ├─ stats.go            # 多维收支与宏观资产负债统计汇总：还款与转账双边核算、转账手续费纯资产扣减与净资产守恒、渠道明细与信用使用率、收支趋势隔离转账
│     └─ server_test.go      # 全业务端点集成测试（鉴权、设置 CRUD、409/400 拦截、账单 CRUD、还款与转账全链路及守恒核算、多维统计）
├─ web/                      # 前端 React + Vite + Tailwind + TypeScript 工程
│  ├─ src/
│  │  ├─ components/
│  │  │  ├─ primitives.tsx   # 共享原子构件层：Panel/IconButton/Button/SegmentedControl(共享位置指示器)/Chip/Amount/TypeTile/Rail/Skeleton/EmptyState/ConfirmDialog/OverflowMenu（受控溢出菜单、首项自聚焦、方向键与 Home/End 项间导航、外边界 pointerdown 监听、无视口翻转）
│  │  │  ├─ Charts.tsx       # 纯 SVG 图表：DonutChart（品牌单色阶环形 + 图例点选下钻）与 TrendChart（响应式 viewBox 双线收支趋势），零第三方图表依赖
│  │  │  ├─ Navbar.tsx       # 玻璃材质悬浮顶栏（backdrop-blur + 顶部内高光）、SegmentedControl 主导航（滑动指示器）、主题切换与登出
│  │  │  ├─ BottomBar.tsx    # 玻璃材质底部筛选胶囊（5 档 aria-selected）与品牌色 FAB（顶部内高光投影、hover/active 缩放）
│  │  │  ├─ RecordModal.tsx  # 金额唯一主角：四段类型滑块、初始化与自动聚焦收敛至打开转换（防输入法中文打断）、配置晚到自动补全（含类型化目标渠道默认）、移动端 16px 视口防缩放、转账手续费内联展开、双渠道互斥
│  │  │  ├─ AuthModal.tsx    # 管理员安全解锁浮层（pop 弹性入场、内联错误提示条、品牌淡底锁形牌）
│  │  │  ├─ Icons.tsx        # Fluent 语义纯 SVG 图标库（四类交易语义图标、MoreHorizontalIcon 三点与基础图标，圆头线帽 2–2.4 描边约定）
│  │  │  └─ Toast.tsx        # 弹簧入场胶囊通知（success/error/info 语义图标、移动端底部居中避开作业条、桌面右上锚定、aria-live）
│  │  ├─ pages/
│  │  │  ├─ StreamPage.tsx   # 账目流水：当月概览头条（自然月聚合、不受筛选影响、除零保护、收支比例导轨）+ 日表层组（sunken 表头 + 发丝行分隔）+ TypeTile 语义瓦片 + 金额对齐契约 + 骨架/空态
│  │  │  ├─ streamUtils.ts  # 流水纯函数工具（星期派生、元信息组装含转账手续费），金额格式化再导出自 lib/format.ts
│  │  │  ├─ StatsPage.tsx    # 统计看板：净资产 Hero（40px 主数值 + 资产负债率导轨，可派生指标零虚构）+ 发丝分节四格指标行（花费环比/储蓄率注脚）+ 资产负债渠道双列明细（移除初始金额噪音、额度导轨、≥80% 使用率语义切换）+ 当月支付途径分布 + 环形/趋势图
│  │  │  └─ SettingsPage.tsx # 基础设置：双分区工作台（分类与标签 / 渠道与账户）；分类行整行点击打开抽屉 + 行尾受控 OverflowMenu（调序/重命名/删除）；系统分类独立面板；资产与负债双列面板 + 渠道对话框（ChannelDialog，Portal 视口挂载、decimal 输入）；细分标签抽屉去噪（移除横幅与完成按钮）；配置加载骨架屏；Esc 分层仲裁链（删除确认 → 渠道对话框 → 溢出菜单 → 抽屉编辑 → 抽屉 → 分类编辑 → 新增输入）
│  │  ├─ lib/
│  │  │  ├─ api.ts           # 前端统一 Fetch 客户端、Token 本地持久化、401 拦截与资产负债/分类类型/转账扩展模型定义
│  │  │  └─ format.ts        # 唯一格式化模块：formatAmount/formatMoney/formatPercent/resolveTone/本地时间输入互转工具
│  │  ├─ App.tsx             # 应用主容器，协调主题（documentElement 同步 + 防闪脚本）、视图 rise 转场（key 重挂载）、账单删除单一 ConfirmDialog 确认宿主、全局快捷键（N 键基于 [aria-modal="true"] 真状态自动互斥）、细分标签添加失败错误穿透与提示
│  │  ├─ index.css           # Fluent 2 四层材质令牌体系（分层面/发丝线/品牌/四组语义色/半径/深度/动效/排版，深浅成对）、@layer base 键盘焦点轮廓定义（确保 outline-none 正常覆盖）、全局关键帧与 prefers-reduced-motion 退化
│  │  └─ main.tsx            # React 挂载入口
│  ├─ test/                  # 前端自动化自检（基于 Node 24 原生 node:test 与 --experimental-strip-types）
│  │  ├─ stream.test.ts      # 流水纯函数核心业务契约自检测试套件
│  │  └─ format.test.ts      # 格式化模块测试（formatMoney/formatPercent/resolveTone/日期往返）
│  ├─ embed.go               # Go embed 静态资源绑定（暴露 DistFS）
│  ├─ embed_test.go          # embed 资源可读性验证
│  ├─ vite.config.ts         # Vite 配置（Tailwind 插件、/api 反向代理）
│  ├─ package.json           # 前端依赖配置
│  └─ tsconfig.json          # TypeScript 配置
├─ .github/
│  └─ workflows/
│     └─ docker-publish.yml  # GitHub Actions 自动化构建并推送 Docker 镜像至 GHCR
├─ Dockerfile                # 多阶段构建：node 静态构建 → golang 静态编译 → alpine 轻量运行时
├─ temp/                     # 规划期设计 Demo 暂存区
├─ docker-compose.yml        # VPS 生产部署编排配置（拉取 ghcr.io/evan-1777/ledger 镜像）
├─ .dockerignore             # Docker 构建上下文排除规则
├─ Makefile                  # 统一构建编排（build, test, dev, clean）
└─ .docs/                    # 项目文档与阶段归档
```

- **数据流**：浏览器请求 → HTTP 路由分流：
  - `/api/health` → 健康状态探针（开放端点）
  - `/api/auth/login` → 密码校验并签发 HMAC Token
  - `/api/*` → `RequireAuth` 中间件守卫 → 业务/统计 Handler → SQLite 读写 → JSON 响应
  - 非 API 请求 → `web.DistFS`（匹配前端静态产物；未匹配则回退至 `index.html`）
- **依赖方向**：`cmd/server` 组合 `internal/config`、`internal/db`、`internal/server` 与 `web`；各 `internal/*` 模块间解耦，不反向依赖 `cmd`。

## 约定

- **命名**：Go 包与文件 snake_case，导出的类型与函数 PascalCase；TypeScript 组件 PascalCase，工具函数 camelCase
- **语言**：用户可见文本用中文；代码注释、提交前缀遵循英文约定
- **错误处理**：后端内部错误统一包装，对外返回对应 HTTP 状态码与结构化 JSON（引用删除严格返回 409 Conflict，非法参数返回 400 Bad Request）；前端统一捕获并展示 Toast
- **日志**：Go 标准库 `log`，输出清晰的时间戳与结构化上下文信息

## 约束与决策

- 2026-10-01 采用纯 Go SQLite 驱动 `modernc.org/sqlite` 代替 `go-sqlite3`——消除 CGO 依赖，极大简化跨平台编译与轻量级 Docker 镜像构建
- 2026-10-01 SQLite 连接池 DSN 驱动级参数注入——采用 `_pragma=foreign_keys(1)&_pragma=busy_timeout(5000)&_pragma=synchronous(NORMAL)` 保证连接池中每个独立物理连接外键约束恒定生效，配合外键 RESTRICT 约束杜绝孤儿数据竞态
- 2026-10-01 采用 Go `embed.FS` 嵌入前端 `dist` 产物——实现单个独立可执行文件的零外部依赖交付
- 2026-10-01 账单金额以带符号整数分（`amount_cents`）存储，支出为负、收入为正——彻底杜绝浮点累加漂移，API 统一转换为元单位
- 2026-10-01 采用单一管理员密码与 HMAC 会话凭证——符合私有个人部署 YAGNI 原则；登录失败注入 500ms 强制时延防范暴力枚举
- 2026-10-01 级联引用删除守卫——被 transactions 引用的支付途径、分类、细分标签执行删除时，应用层严格拦截并返回 409 Conflict，杜绝孤儿数据
- 2026-10-01 统计接口异常阻断与 CRUD 错误契约分流——统计查询全面执行 Fail-Fast，底层报错坚决返回 500，杜绝返回假零报表；CRUD 接口精准区分 400（唯一约束冲突）与 500（未预期底层故障）
- 2026-10-01 前端时间分组跨年展示——交易流非当年记录自动补齐年份前缀（`YYYY年M月D日`），消除跨年同月同日混淆
- 2026-10-01 前端界面采用 Fluent 品牌蓝与 Tailwind Slate 精细灰阶混合体系（Fluent-Slate Hybrid）——Segoe UI 字阶、900px 居中流式卡片、二级级联 Flyout 选择、无界面噪声
- 2026-10-01 容器化多阶段打包与 GitHub Actions 镜像自动化发布——采用 Node 24 编译静态资源、Golang 1.27 Alpine 静态编译单二进制、Alpine 3.21 最小化运行时（含 CA 证书、时区支持与健康探针），通过 GitHub Actions 推送至 GHCR（`ghcr.io/evan-1777/ledger`），提供 `docker-compose.yml`（强制声明 `LEDGER_ADMIN_PASSWORD` 杜绝弱默认密码）实现 VPS 零编译一键部署
- 2026-10-02 界面去噪与中性排版重塑——移除流水单侧彩色粗边框与首字方块图标，记账模态窗引入顶部双向胶囊滑块并移除用途快捷输入标签，统计看板彻底清理下钻引导文案
- 2026-10-02 消费类型手动调序与二级操作菜单体系——采用基于绝对数组索引递增的防碰撞调序算法杜绝同值死锁；消费类型与细分标签统一接入二级上下文操作菜单（支持重命名与删除），重命名以同构内联表单呈现并由 App.tsx 驱动 SSOT 同步
- 2026-10-02 移动端全屏自适应与底部悬浮防重叠——底部筛选胶囊在小屏下居中靠左避让右下角 FAB，在非流水页优雅退化仅保留悬浮 FAB；顶栏导航项与支付途径网格响应式收紧，模态窗启用内部弹性滚动
- 2026-10-02 顶栏登出断点规范化与滑块 GPU 硬件加速——顶栏登出按钮采用标准 `hidden sm:inline` 断点规范；记账模态窗收支滑块改用 `transform: translateX` 硬件加速，像素对称且消除布局 Reflow；暗黑模式补齐 `--color-expense-stroke` 与 `--color-income-stroke` 语义边框令牌
- 2026-10-02 设置调序防竞态与重命名健壮性增强——`App.tsx` 串行执行调序并合并为单次 `fetchConfigData()` 刷新，杜绝并发网络竞态与闪烁；调序优先交换已有 `sort_order`；内联重命名增加兄弟分类与同级标签重名预校验，`try...catch` 安全兜底保留编辑状态，全流程后端冲突映射为清晰中文提示
- 2026-10-02 数据库种子持久化与老库升级平滑纳管——在 SQLite 增加 `system_meta` 表并通过显式事务管理；全新库初始化种子并打标，已有数据老库升级自动补标且绝不重新注入默认项，彻底解决 Docker 容器重启与镜像升级时误复活已删除数据的问题
- 2026-10-02 顶栏响应式文本折叠与移动端安全尺寸规范——顶栏中央胶囊导航文字统一采用 `hidden sm:inline` 响应式断点（移动端纯标准 SVG 语义图标彻底杜绝挤压溢出，桌面端保留文字以维持低认知负荷）；操作簇按钮尺寸统一规范（34x34px），保障 320px–414px 移动端视口单行自适应排开
- 2026-10-02 设置页双核心业务分段与细分标签专属抽屉体系——将平铺卡片重构为「分类与标签」和「支付途径」双分段导航；分类细分标签管理收敛至专属 Layer 3 抽屉容器，基于 `activeCategoryId` 与父级 `App.tsx` 的 SSOT 实时派生同步，保留同构内联重命名与 409 拦截提示，彻底清除界面静态占位与多余教程解释
- 2026-10-03 支付途径升级为资产与负债渠道模型——在 `payment_methods` 中无缝扩展 `type`（asset/liability）、`initial_balance_cents`、`credit_limit_cents`；通过 `PRAGMA table_info` 探针热迁移平滑兼容既有数据库，在老库种子保护机制前注入，彻底避免对历史账单与外键的破坏
- 2026-10-03 资产与负债核心指标单查询聚合与衍生计算——后端通过单条轻量 LEFT JOIN 聚合查询按渠道累计历史交易金额；净资产由全部资产渠道余额减去全部负债渠道欠款严格闭环核算；负债渠道动态衍生信用额度使用率与可用额度，杜绝报表失真与假零
- 2026-10-03 设置页资产与负债渠道分列工作台与即时编辑——「支付途径」升级为双列并排的「资产渠道」与「负债渠道」容器；支持内联新增与即时原地编辑（更新渠道名称、初始金额与信用额度）；保留被引用删除的 409 拦截安全保护
- 2026-10-03 Fluent 2 宏观资产负债投资组合看板与进度条视觉规范——在统计页顶部置顶 3 联宏观指标卡（净资产、资产总计、负债总计），搭配资产结余与负债欠款双列明细面板；负债渠道采用 4px 紧凑进度导轨与语义色彩（赤字高亮/正常灰阶）即时映射额度使用率
- 2026-10-03 资产与负债渠道数据校验与溢缴额度自洽——服务端渠道创建与更新接口统一拦截负数金额并返回 400，前端全量补充 `min="0"` 与前置校验；负债渠道在负欠款（溢缴款）场景将可用额度上限自洽约束在授信额度本身；资产侧术语全面统一为「初始余额」，宏观 KPI卡片清除解释性副标题
- 2026-10-03 transactions 表类型扩展与探针热迁移——动态探测并追加 `type`（expense/income/repayment）与 `source_payment_method_id`（外键关联 payment_methods），老数据依据金额符号原子回填，零停机且无损升级
- 2026-10-03 系统级还款分类与标签预置及 ID 级不可变守卫——前置注入单系统分类「债务偿还」与单标签「负债还款」，ID 写入 `system_meta`；`settings.go` 基于 ID 拦截 PUT 与 DELETE 返回 400 Bad Request，从根因杜绝改名击穿与误删
- 2026-10-03 还款交易规则与双向账户宏观守恒核算——还款金额必须为大于 0 的正数，目标渠道必须为负债账户，转出渠道必须为资产账户或外部资金；负债端正金额自然冲销欠款，资产端扣减转出金额，净资产（`netAssets = totalAssets - totalLiabilities`）实现绝对物理守恒
- 2026-10-03 收支统计、趋势分布与流水日小计严格隔离还款——所有收入、支出、分类/标签/渠道分布及日分组小计严格排除还款记录，杜绝还款正金额导致收入虚增或消费失真
- 2026-10-03 前端 3 段滑块、编辑类型锁定与 4 档筛选联动——记账模态窗提供支出/收入/还款三段平滑胶囊切换；编辑已有账单时滑块置为禁用锁定态防跨类型错乱；流水列表支持 4 档位筛选并以中性品牌蓝呈现资金流转（`[转出渠道] → [还入渠道]`）
- 2026-10-03 渠道删除 409 守卫覆盖双边账单引用与前端无负债闭环——将支付渠道被引用删除拦截范围扩展至 `source_payment_method_id`，杜绝底层外键约束穿透返回 500；记账模态窗在还款模式且无负债渠道时温和禁用提交并提供直达基础设置添加的快捷引导
- 2026-10-03 前端视觉美学缺陷修复与设计体系对齐——暗黑模式补齐品牌色高亮（`--color-brand-light`）与边框（`--color-brand-stroke`）令牌，还款滑块与标签纳入统一变量驱动；Navbar 与 BottomBar 注入 `backdrop-blur-md` 与半透背景建立 Layer 2 物理材质层级；负债渠道额度使用率按 80% 分档映射语义色彩（<80% 中性灰，>=80% 赤字警示红）；收支 KPI 卡片清理自然周/累计支出等冗余副标题；收敛 12.5px/13.5px 半档字号，StreamPage 移动端操作按钮增大至 32px，核心导航控件添加 `focus-visible` 键盘焦点态，细分标签抽屉注入平滑从右滑入微动效
- 2026-10-04 categories 表类型扩展与探针热迁移——动态探测并追加 `type`（expense/income/system），迁移位置严格置于 `seed_initialized` 保护之前，仅在缺列时对老数据执行一次性打标（不干扰用户后续类型纠错），系统分类获取 ID 后显式确保 `type='system'`，实现存量老库无损平滑升级
- 2026-10-04 系统转账分类与标签预置及 ID 级不可变守卫——启动时事务内前置注入系统分类「账户转账」与标签「资金互转」，ID 持久化至 `system_meta`；API 端点（`settings.go`）对转账系统分类与标签的修改及删除请求严格返回 400 Bad Request，防止系统级外键与账单语义击穿
- 2026-10-04 转账交易契约与宏观资产守恒核算——`transactions.go` 支持 `type = 'transfer'`（金额正数、目标与来源均为资产渠道、双渠道互斥防同账户划转、自动回填系统分类）；`stats.go` 资产渠道结余纳管转出扣减（`source_transfer_sum`），总资产与净资产精确守恒变动 -fee（无手续费时净变动为 0）；月度/周度收支与分类下钻严格排除转账
- 2026-10-04 移动端 100dvh 视口高度与常驻底部操作栏——`RecordModal.tsx` 采用 `max-h-[calc(100dvh-24px)]` 动态视口高度，重构为 Flex 列布局（固定 Header + 可滚动表单 + 常驻 Footer），彻底解决移动端地址栏伸缩导致的保存按钮被截断与滚动死锁问题
- 2026-10-04 收支分类分流隔离与平滑内联展开——记账模态窗消除绝对定位二级悬浮面板，改为流式内联平滑展开；根据收支模式严格分流分类池，记收入仅展示收入分类且默认智能回填，记支出排除收入分类，点选后平滑自动收起
- 2026-10-04 设置页分类收支分段管理与历史纠错——分类管理工作台增加支出分类与收入分类二级轻量分段，新增分类自动继承当前分段；分类内联编辑支持微调分类类型，提供老库历史数据纠错途径；系统内置分类标注不可变系统标识，前端隐藏更名与删除入口
- 2026-10-04 移动端底部筛选胶囊间距防重叠——`BottomBar.tsx` 移动端内边距微调为 `px-2.5` 且间距设为 `gap-0.5`，胶囊总宽收缩至 248px，彻底消除 ≤375px 小屏下与右侧悬浮记账按钮（FAB）的边缘重叠，保留 35px 以上安全缓冲距离
- 2026-10-04 账目流水主页视觉重构与日表层合组（方案 A）——消除碎片化单笔浮起卡片，重构为每日一张连续表面 + 表头行（两段式日期与本地时区星期派生）+ hairline 分隔；形状编码类型（4 枚 32px 语义图标块）搭配单一色彩焦点（金额定宽竖向对齐契约 `${sign}¥${amount}`）；元信息完整包含细分标签且全宽度一致不丢失信息；常态元素收敛为单个更多入口并展开 React 声明式二级操作浮层（日容器不裁切保证边界溢出可见）；排除了过度设计的对账单列阵方案（YAGNI，避免为桌面密度牺牲移动端主作业流连续性与引入双布局复杂性）
- 2026-10-04 暗黑模式凹陷面令牌修正与 Mica 画布材质——在 `index.css` 根因处将暗色 `--color-subtle-bg` 调整为 `#172033` 恢复凹陷面层级，浅色与暗色分别注入极淡品牌色顶部径向渐变作为 Fluent Layer 0 画布材质
- 2026-10-04 复审质量加固与 Mica 画布材质归位——将 Layer 0 Mica 画布渐变材质收敛至 CSS 令牌层（`--canvas-gradient`）并由 App 根容器消费，彻底解决 body 背景被不透明容器遮挡的问题；暗色模式补齐 `--shadow-flyout` 阴影深度；流水纯函数（星期派生、元信息拼接、金额契约）抽离至 `streamUtils.ts`，接入 Node 24 原生 `node:test` 与 `--experimental-strip-types` 自动化自检（无第三方测试库开销）；二级操作浮层收敛至 WAI-ARIA disclosure 模式并退回普通按钮组，日分组容器退回 `<div>` 消除 landmark 语义噪音；彻底清除 `ClockIcon` 零引用死代码
- 2026-10-05 移动端通知提示 (Toast) 视口自适应修复——外层定位调整为 `fixed top-20 left-1/2 -translate-x-1/2 sm:translate-x-0 sm:left-auto sm:right-8 w-[calc(100vw-32px)] sm:w-full max-w-sm`，彻底消除单侧固定偏移导致的窄屏负坐标向左越界与文本截断，桌面端平滑保持右上锚定
- 2026-10-05 转账手续费数据模型与探针热迁移——在 `transactions` 表追加 `fee_cents INTEGER NOT NULL DEFAULT 0`；通过 `PRAGMA table_info` 探针热迁移平滑升级，老库零成本兼容；API 严格校验 `fee >= 0` 并原子存取
- 2026-10-05 转账手续费纯资产调整核算与收支隔离——遵循转账本质与既有收支隔离契约，转出资产结余纳管 `source_transfer_sum = amount_cents + fee_cents` 扣减，净资产精确减少 `fee`；周/月收支与分类分布保持对转账完全隔离，杜绝孤儿分类支出与分类百分比失真
- 2026-10-05 前端方案 A 金额卡片内敛手续费交互——遵循资深用户去噪原则，默认转账界面极简纯净，仅在账单金额卡片 Header 右上角提供微型 `+ 手续费` 触发；点开即内联展开输入框，支持一键清空收起；流水明细元信息按指定规范直观展示 `手续费 ¥X.XX`
- 2026-10-05 复审吸收与轻量收敛——校准术语表「双向资产转账」明确手续费净资产变动；剔除 RecordModal 提交阶段 parsedFee < 0 不可达防御分支，防线收敛于输入正则与服务端信任边界；清理 Plan 方案比对表中临时原型虚假引用
- 2026-10-14 Fluent 2 成品级 UI/UX 全站重构（不新增业务功能、不改后端契约）——`index.css` 重写为四层材质令牌体系（画布/内容/悬浮/模态分层面、发丝线、品牌色组、支出/收入/转账/还款四组语义色各四档、半径刻度、三级深度阴影、三条动效曲线三档时长、深浅主题成对定义，暗色以面提亮 + 顶部内高光表达层级）；新增共享原子构件层 `primitives.tsx`（Panel/IconButton/Button/SegmentedControl/Chip/Amount/TypeTile/Rail/Skeleton/EmptyState/ConfirmDialog），组件样式一律 Tailwind utility + 令牌任意值语法消费，禁止就地色值/圆角/阴影字面量；金额格式化收敛至 `lib/format.ts` 唯一模块（`formatMoney`/`formatPercent`/`resolveTone`/本地时间输入互转），streamUtils 再导出保持既有测试契约；自绘 SVG 图表 `Charts.tsx`（品牌单色阶环形图 + 图例点选同视口下钻、响应式 viewBox 双线趋势图），零第三方图表依赖；破坏性操作全面以应用内 `ConfirmDialog`（alertdialog 契约、焦点落于取消、Esc/遮罩等同取消）替换浏览器原生 `confirm`，App 层与设置页各自维护单一 `pendingDelete` 状态宿主；流水页新增当月概览头条（自然月聚合、不受筛选影响、比例导轨除零不渲染）；统计页重构为净资产 Hero 主视觉 + 发丝分节指标行（花费环比/储蓄率注脚，分母为零降级）+ 渠道双列明细；数据边界纪律：所有呈现数值仅由 `StatsSummary` 已有字段及其四则派生，禁止虚构历史快照类指标；`index.html` 补主题元信息与首帧防闪内联脚本（类挂 documentElement 与 App 主题同步）
- 2026-10-14 复审修复轮（吸收 Review 审计报告）——流水头条统计与底部筛选解耦（App 层并行拉取不带筛选数据源，`computeMonthHeadline` 独立消费，修复筛选档位下头条归零缺陷）；`:focus-visible` 移除强制 `border-radius` 修复杂圆形控件变形；`.num` 移入 `@layer components` 使 `tracking-*` utility 可覆盖；统计页补回被静默删除的「当月支付途径分布」面板；新增 `--overlay`/`--brand-glow`/`--donut-1..5`/`--r-nano` 令牌并清除全部 JSX 十六进制色值与 rgba 字面量（Navbar 渐变第二停改用 `--brand-pressed`）；删除零消费令牌 `--surface-raised`/`--e2`/`--transfer`/`--repay` 基色与死导出 `Badge`/`MoreVerticalIcon`，`formatPercent` 落地至全部百分比呈现点；SegmentedControl 补 aria-label 与 disabled（记账编辑态类型滑块真锁定）；RecordModal 表单标签程序化关联；RecordModal/AuthModal 补 dialog 语义；ConfirmDialog 焦点仅在打开时夺取；设置页空态去「点击右上角」指引改 EmptyState 直达按钮；表面材质收敛至 Panel 单一来源（日表圆角统一 16px）；`color-scheme` 与 meta theme-color 跟随应用主题而非系统；320px 筛选胶囊与 FAB 防重叠（<400px 收紧内边距与字号）
- 2026-10-14 复审驳回项备案——客户端 7 处重名预校验收敛（既有代码，后端 409 映射已兜底，改动风险大于收益）；Panel hero 变体保留（StatsPage 有真实调用方）；模态焦点陷阱留待后续专项（已有首焦点落点与 dialog 语义）
- 2026-10-14 金额焦点层级归位与模态视口级挂载——全局 `:focus-visible` 移入 `@layer base`，使控件级 `outline-none`（v4 即 `outline-style: none`）正常覆盖默认轮廓，消除记账金额输入框内外双重焦点边框；细分标签抽屉与共享 `ConfirmDialog` 一律 `createPortal` 挂载至 `document.body`，脱离祖先动画容器的包含块与层叠上下文（后续新增模态覆盖层沿用此约定，不在带动画的容器内直接渲染 `fixed` 覆盖层）；抽屉关闭路径统一为 `closeDrawer`，Escape 按确认 → 编辑 → 抽屉分层仲裁，打开自聚焦与关闭焦点恢复以 `isConnected` 守卫；新增标签以同步 ref 提交锁防重、失败保留草稿并由父级单次 Toast 提示，输入框不禁用以避免提交期间丢失焦点
- 2026-10-15 初始金额展示收敛与去噪——初始余额/初始欠款定位为账户真实状态校准参数，不再作为前台展示信息；设置页渠道行与统计页渠道明细彻底移除初始金额副文案，仅在新建/编辑渠道表单中保留；负债渠道保留额度与可用额度呈现
- 2026-10-15 设置页成熟列表重构与受控溢出菜单——分类行收敛为整行主操作（点击打开细分标签抽屉）+ 行尾受控 OverflowMenu（重命名/上移/下移/删除），行内清除常驻图标组与多余 Chip；系统分类独立为下方独立面板；资产与负债拆分为双面板双列并排；渠道编辑重构为应用内 ChannelDialog（Portal 视口挂载、decimal 输入、内联校验），彻底清零 type="number" 与行内表单噪音；细分标签抽屉移除冗余政策横幅与底部完成按钮；App 层提供 configLoaded 状态并在设置页展示 4 行骨架屏；全局 Esc 分层仲裁严格按层级响应
- 2026-10-15 RecordModal 初始化与输入法防打断收敛——将表单初始化与自动聚焦重构为单一「打开」转换（依赖收敛为 [isOpen, initialTransaction]），彻底解决因父组件配置回刷导致 effect 反复触发、清空描述并抢回 decimal 焦点的输入法打断根因；配置晚到场景以增量 fallback effect 补齐默认选中；输入框字号适配移动端 16px 防止 iOS 聚焦缩放打断键盘
- 2026-10-15 初审意见吸收——类型→目标渠道规则归位为 RecordModal 内单一 `targetChannels`，由类型切换与配置晚到回填共用（原先该规则只存在于切换分支，配置晚到时回填猜 `paymentMethods[0]`，还款/转账会落到资产渠道且提交校验不拦）；OverflowMenu 补齐 `role="menu"` 所需的方向键与 Home/End 项间导航，Escape 仍由宿主仲裁链持有；清除 SettingsPage 冗余类名（`group`/`relative`/`overflow-visible`，均为无消费者或默认值）。驳回：`temp/redesign-demo.html` 为工作区未暂存的用户删除动作，不代为提交

## 术语

- **单二进制 (Single Binary)** = 包含 Go 后端编译产物与内嵌前端静态资源的独立单一可执行程序
- **SPA 回退 (SPA Fallback)** = 当浏览器请求非 API 且非静态资源的路径时，服务端返回 `index.html`，交由客户端 React 处理路由
- **宏观资产组合矩阵 (Macro Portfolio Matrix)** = 统计页顶部净资产、资产总计、负债总计 3 联核心 KPI 卡片
- **探针热迁移 (Probe-based Hot Migration)** = 启动时通过 `PRAGMA table_info` 查询现有表列定义，动态按需执行 `ALTER TABLE ADD COLUMN`，实现零停机与跨版本平滑升级
- **双向账户核算 (Bilateral Account Accounting)** = 还款时目标负债渠道冲销欠款、转出资产渠道扣减结余，资产与负债同步变动并维持净资产物理守恒
- **双向资产转账 (Bilateral Asset Transfer)** = 资金在两个资产渠道之间的内部划转，转出方扣减余额（含可选转账手续费），转入方增加本金余额，无手续费时总资产与净资产保持绝对守恒，产生手续费时总资产与净资产精确变动 -fee，不计入收支损益
- **系统级不可变分类 (Immutable System Category)** = 预置于系统内由 `system_meta` 持久化 ID 的特殊分类，具有专用业务逻辑且禁止任何修改或删除操作

