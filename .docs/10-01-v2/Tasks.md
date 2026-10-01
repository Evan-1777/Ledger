# Tasks：核心记账业务、分类设置与 Fluent 统计前端开发

**关联 Plan**：`Plan.md` —— 核心记账业务、分类设置与 Fluent 统计前端开发 v1.0  
**总计 Task**：12 个

---

## Phase 1：数据持久层演化与管理员密码鉴权机制

### TASK-001：设计并实现 SQLite 核心数据表结构与初始种子数据

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/db/` 模块中实现数据表自动迁移函数，创建 `categories`、`tags`、`payment_methods` 和 `transactions` 四张数据表，统一金额为整数分（`amount_cents`）与时间为 RFC3339 UTC 格式，并注入默认基础种子数据。
- **Details**：
  - `categories`：`id` (INTEGER PK AUTOINCREMENT), `name` (TEXT UNIQUE NOT NULL), `sort_order` (INTEGER DEFAULT 0), `created_at` (TEXT DEFAULT CURRENT_TIMESTAMP)
  - `tags`：`id` (INTEGER PK AUTOINCREMENT), `category_id` (INTEGER NOT NULL REFERENCES categories(id) ON DELETE RESTRICT), `name` (TEXT NOT NULL), `sort_order` (INTEGER DEFAULT 0), `created_at` (TEXT DEFAULT CURRENT_TIMESTAMP), `UNIQUE(category_id, name)`
  - `payment_methods`：`id` (INTEGER PK AUTOINCREMENT), `name` (TEXT UNIQUE NOT NULL), `sort_order` (INTEGER DEFAULT 0), `created_at` (TEXT DEFAULT CURRENT_TIMESTAMP)
  - `transactions`：`id` (INTEGER PK AUTOINCREMENT), `amount_cents` (INTEGER NOT NULL), `description` (TEXT NOT NULL), `payment_method_id` (INTEGER NOT NULL REFERENCES payment_methods(id) ON DELETE RESTRICT), `category_id` (INTEGER NOT NULL REFERENCES categories(id) ON DELETE RESTRICT), `tag_id` (INTEGER NOT NULL REFERENCES tags(id) ON DELETE RESTRICT), `transacted_at` (TEXT NOT NULL), `created_at` (TEXT DEFAULT CURRENT_TIMESTAMP)
  - 存储口径定死：`amount_cents` 为带符号整数分（例如 -3200 表示支出 32.00 元，+500000 表示收入 5000.00 元）；`transacted_at` 统一持久化为 RFC3339 UTC 格式字符串（`2006-01-02T15:04:05Z`）；
  - 默认内置种子：支付途径（微信支付、支付宝、招商银行卡、现金钞票）；类型与细分标签（餐饮美食 [午餐, 晚餐, 咖啡奶茶, 超市买菜]、交通出行 [地铁, 打车出租, 公交]、居家生活 [房租月供, 物业水暖, 日用百货]、休闲娱乐 [电影演出, 数字游戏, 运动健身]、职业收入 [主业工资, 年终奖金, 兼职报酬]）。
- **Acceptance Criteria**：
  - 数据库启动时表结构自动建立，开启外键约束；
  - 首次初始化后表中写入默认种子数据，重复启动保持幂等；
  - `internal/db/db_test.go` 覆盖表结构完整性与种子测试且全部通过。

### TASK-002：实现配置扩展与管理员密码校验鉴权中间件

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/config/` 与 `internal/server/` 中新增环境变量 `LEDGER_ADMIN_PASSWORD` 支持，实现密码登录端点 `POST /api/auth/login`（附带防爆破延迟）与 Bearer Token 会话校验中间件。
- **Details**：
  - `internal/config/config.go` 新增 `AdminPassword` 字段，默认值为 `admin123`；新增 `TokenSecret` 自动生成或配置支持；若检测到使用默认密码，启动时输出控制台安全告警；
  - `internal/server/auth.go` 实现登录端点：接收 `{ "password": "..." }`；若校验失败，强制执行 `time.Sleep(500 * time.Millisecond)` 防暴力枚举，并返回 401；校验成功则签发带 30 天有效期的 HMAC Token；
  - 实现状态检查端点 `GET /api/auth/check`：校验请求头 `Authorization: Bearer <token>`；
  - 实现通用 `RequireAuth` 中间件守卫业务 API，验证失败返回 401 结构化 JSON：`{ "error": "unauthorized" }`。
- **Acceptance Criteria**：
  - 正确管理员密码调用 `/api/auth/login` 返回有效 Token；
  - 错误密码调用触发 500ms 防爆破延迟并返回 401；
  - 携带有效 Token 访问 `/api/auth/check` 返回 200，伪造或未携带 Token 访问受保护路由返回 401；
  - 单元测试覆盖正常登录、错误密码延迟与鉴权拦截。

---

## Phase 2：基础配置管理与收支统计核心 API

### TASK-003：实现支付途径、类型与细分标签 CRUD API 及引用删除守卫

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/server/` 中实现配置项的管理端点，支持前端设置页对支付途径、类型及细分标签进行增删改查，并在应用层提供严格的账单引用保护。
- **Details**：
  - `GET /api/payment-methods`，`POST /api/payment-methods`，`PUT /api/payment-methods/{id}`，`DELETE /api/payment-methods/{id}`
  - `GET /api/categories`（附带关联 tags），`POST /api/categories`，`PUT /api/categories/{id}`，`DELETE /api/categories/{id}`
  - `GET /api/tags?category_id={id}`，`POST /api/tags`，`PUT /api/tags/{id}`，`DELETE /api/tags/{id}`
  - 应用层删除统一守卫：
    - 删除支付途径：若 `SELECT COUNT(1) FROM transactions WHERE payment_method_id = ?` > 0，返回 409 Conflict `{ "error": "该支付途径已有关联账单，禁止删除" }`；
    - 删除细分标签：若 `SELECT COUNT(1) FROM transactions WHERE tag_id = ?` > 0，返回 409 Conflict `{ "error": "该细分标签已有关联账单，禁止删除" }`；
    - 删除消费类型：若 `SELECT COUNT(1) FROM transactions WHERE category_id = ?` > 0，返回 409 Conflict `{ "error": "该消费类型已有关联账单，禁止删除" }`；若无直接引用但有下属标签，先检查所有下属标签是否无关联账单，满足条件后在单个事务内删除下属标签与分类。
- **Acceptance Criteria**：
  - 所有端点均由 `RequireAuth` 中间件守卫；
  - 存在关联账单的途径、类型、标签删除时严格返回 409 并给出清晰提示；
  - 无关联引用的条目可正常删除并即时生效；
  - 单元测试覆盖基础 CRUD 与 409 引用拦截。

### TASK-004：实现单笔账单完整 CRUD（录入、更新、删除与流水列表）API

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/server/` 中实现账单录入、更新、删除与流水列表端点，完成浮点金额到带符号整数分的转换、标签归属级联校验及 RFC3339 时间标准化。
- **Details**：
  - 数据模型转换：接口入参接受以元为单位的小数金额 `amount`（负为支出、正为收入），后端通过 `int64(math.Round(req.Amount * 100))` 存入 `amount_cents`；返回时计算 `amount = float64(t.AmountCents) / 100.0`；
  - 时间标准化：若前端提供 `transacted_at` 则解析并转为 UTC RFC3339 字符串，未提供则使用当前服务器时间 `time.Now().UTC().Format(time.RFC3339)`；
  - `POST /api/transactions`：录入新账单，校验 `tag_id` 必须归属于指定 `category_id`，校验外键合法；成功返回 201；
  - `PUT /api/transactions/{id}`：编辑更新历史账单，入参同 POST，执行相同的归属校验与金额转换；成功返回 200；
  - `GET /api/transactions`：支持 `limit`、`offset` 分页，联表输出分类名、分类图标、标签名、支付途径名、`amount`、`amount_cents` 与 `transacted_at`，按 `transacted_at DESC, id DESC` 排序；
  - `DELETE /api/transactions/{id}`：删除指定 ID 账单，成功返回 200 `{ "success": true }`。
- **Acceptance Criteria**：
  - 成功录入账单，数据库中 `amount_cents` 与 `transacted_at` 准确无误；
  - `PUT /api/transactions/{id}` 成功更新账单数据并校验标签归属合法性；
  - 当 tag 不属于指定 category 时返回 400 校验错误；
  - 单元测试覆盖创建、更新、查询、删除全流程。

### TASK-005：实现多维收支统计汇总 API（闭环支撑统计看板）

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `internal/server/` 中实现多维数据统计端点 `GET /api/stats/summary`，以本地时区截取时间窗口并在数据库内以整数分求和，闭环输出前端统计页所需的全部指标。
- **Details**：
  - 时间窗口与时区换算：
    - 以服务器本地时区（`time.Local`）截取自然周（周一 00:00:00 至周日 23:59:59）、当前自然月（当月 1 日 00:00:00 至当月最后一天 23:59:59）与上一个自然月的起止时间点；
    - 将上述起止时间统一转换为 UTC RFC3339 字符串，用于 SQL 范围过滤（`WHERE transacted_at >= ? AND transacted_at <= ?`）；
  - 纯整数代数汇总（彻底避免浮点累加漂移）：
    - `week_expense`：本周所有 `amount_cents < 0` 记录的 `SUM(amount_cents)` 绝对值除以 100.0；
    - `month_expense`：当月所有 `amount_cents < 0` 记录的 `SUM(amount_cents)` 绝对值除以 100.0；
    - `last_month_expense`：上月所有 `amount_cents < 0` 记录的 `SUM(amount_cents)` 绝对值除以 100.0；
    - `month_income`：当月所有 `amount_cents > 0` 记录的 `SUM(amount_cents)` 除以 100.0；
    - `month_balance`：`month_income - month_expense`；
    - `savings_rate`：若 `month_income > 0` 则为 `math.Round((month_balance / month_income) * 1000) / 10`，否则为 0；
    - `category_distribution`：当月各分类支出聚合（分类 ID、名称、图标、金额、在当月总支出中的占比）；
    - `payment_distribution`：当月各支付途径支出聚合（途径 ID、名称、金额、占比）；
    - `monthly_trends`：查询近 6 个自然月的月度汇总数组，每项包含月份（`YYYY-MM`）、当月支出 `expense`、当月收入 `income`。
- **Acceptance Criteria**：
  - 接口结构完整包含 `week_expense`, `month_expense`, `last_month_expense`, `month_income`, `month_balance`, `savings_rate`, `category_distribution`, `payment_distribution`, `monthly_trends`；
  - 所有金额由整数分计算得出，无浮点累加误差；
  - 单元测试覆盖跨月跨年统计计算与空记录防御。

---

---

## Phase 3：前端 Fluent 2 视觉底座与交互外壳

### TASK-006：构建应用外壳（顶栏分段胶囊主导航、底栏筛选胶囊与 FAB 悬浮按钮）

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/` 中配置 Fluent 2 视觉系统变量与样式，搭建包含顶部分段胶囊导航、底部中心筛选胶囊与右下角 FAB 按钮的应用外壳（900px 居中流式画布）。
- **Details**：
  - `web/src/index.css`：定义 Fluent 蓝（`#0078d4`）、高阶灰中性色阶、标准字阶（12px Caption, 14px Body, 16px Subtitle, 20px Title, 28/34px Display）、全局 `font-variant-numeric: tabular-nums` 等宽数字规范与 12px 标准卡片圆角，支持暗黑模式无缝切换；
  - 顶部导航栏（60px）：左侧应用圆角标识与 Ledger 标题；居中分段胶囊主导航 `[账目流水][收支统计][基础设置]`；右侧暗黑切换按钮、`A admin` 管理员徽章与登出动作；
  - 底部控制层：居中悬浮筛选胶囊 `[全部][支出][收入]`，以及右下角高亮圆形 FAB `+` 按钮；
  - 900px 居中流式画布，留白与比例完全复刻参考范式。
- **Acceptance Criteria**：
  - 顶栏分段胶囊平滑无缝切换三大主视图；
  - 底部筛选胶囊与 FAB 悬浮定位稳固，响应式居中，无晃动或错位；
  - 完美复刻参考范式的高清留白、极简排版与视觉节奏；
  - 遵循 `production-frontend` 守则：杜绝任何 AI 提示词与界面噪声。

### TASK-007：实现统一 API 客户端与密码解锁模态层

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/lib/api.ts` 与组件层封装全局 Fetch 客户端，集成 LocalStorage Token 管理、401 自动拦截与管理员密码解锁模态框。
- **Details**：
  - `api.ts`：自动向请求头注入 `Authorization: Bearer <token>`，统一处理错误返回与 JSON 反序列化；
  - 当收到 401 响应时，触发全局鉴权失效状态；
  - 实现 `AuthModal.tsx`（Layer 3 模态浮层）：呈现 Fluent 风格的管理员解锁卡片，支持输入密码调用 `/api/auth/login` 解锁。
- **Acceptance Criteria**：
  - 页面初次加载时调用 `/api/auth/check`，未解锁时弹出模态框；
  - 输入正确密码成功解锁并持久化 Token，后续请求自动携带；
  - 主动锁定后清除 Token 并重新弹出锁定层。

---

## Phase 4：三大主页面业务功能实现

### TASK-008：实现账目流水流式卡片与纵深记账录入悬浮窗（含二级级联弹出菜单）

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/pages/RecordPage.tsx` 及 `RecordModal.tsx` 中实现居中流式卡片看板与具备强大功能纵深的记账录入/编辑悬浮窗。
- **Details**：
  - 900px 居中账目流水看板：
    - 分组展示：基于 `transacted_at` 发生时间戳倒序呈现（“今天”、“昨天”、“更早”等分组），分组头包含日历图标、日期描述、总笔数与当期支出小计胶囊；
    - 账单卡片：纯白 12px 圆角、左侧状态色条（支出 #ef4444，收入 #10b981）、分类单字圆形/方块头像、用途大字、细分标签胶囊、时钟与支付途径副线、等宽格式化金额与 hover 隐显编辑/删除动作；
    - 编辑交互闭环：点击卡片编辑图标（铅笔）调出预填当前条目数据的 `RecordModal`，保存时调用 `PUT /api/transactions/{id}` 并就地更新列表项；
    - 删除交互闭环：点击删除图标（垃圾桶）调用 `DELETE /api/transactions/{id}` 并执行平滑退出动效；
    - 联动底栏筛选胶囊：点击“全部”、“支出”、“收入”实时秒级无感过滤；
  - Layer 3 记账录入悬浮窗（`RecordModal`）：
    - 点击右下角 FAB `+` 按钮（或键盘快捷键 `N`）调起居中模态卡片，外层带柔和遮罩与深度阴影；
    - 焦点金额 Hero 区域（32px，充裕留白），右上角集成正负性切换指示徽标（默认支出“- 支出”，输入“+”或点按切换为“+ 收入”）；
    - 用途说明输入框，附带常用快捷词标签（商务简餐、地铁充值、超市买菜、咖啡饮品）；
    - **消费类型与细分标签二级级联弹出菜单（Cascading Flyout）**：
      - 触发区为当前选中的类型与标签路径（如“餐 餐饮美食 › 午餐”），点击后在下方呼出二级级联菜单面板；
      - 级联菜单左栏：展示所有主消费类型列表，支持 hover / 点击即时切换活跃分类；
      - 级联菜单右栏：动态展示当前悬停/激活类型下的所有细分标签列表，点选标签后即刻选定并关闭级联菜单回填到表单中；
    - 支付途径磁贴单选组；
    - 键盘交互：支持快捷键 `N` 一键调起悬浮窗，`Esc` 键快捷闭合；
    - 底部操作栏：取消与“记录此账单”主按钮。
- **Acceptance Criteria**：
  - 账目流水卡片排版、间距、字体与颜色与 Demo 一致；
  - 点击右下角 FAB 唤起独立悬浮窗录入，支持新建与编辑已有账单；
  - 类型与细分标签采用二级级联弹出菜单，交互层级清晰；
  - 提交后悬浮窗关闭，流水列表即时增加或更新记录；
  - 界面零噪音，无冗余调试文本。

### TASK-009：实现统计页多维收支洞察看板与下钻分析

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/pages/StatsPage.tsx` 中对接 `/api/stats/summary` 完整渲染四联指标卡片与多维深度统计看板。
- **Details**：
  - 顶部指标栏：横向四卡片（本周花费、当月花费、上月花费、本月结余与储蓄率标签），数值统一采用 `tabular-nums`；
  - 分类支出占比看板：
    - 同构编码：条形进度图呈现各分类支出金额与占比，最低占比行保持高对比度 Fluent 蓝，保障可读性；
    - 支持交互下钻展开所选分类的细分标签消费明细；
  - 趋势图表区：展示近 6 个月月度收支双柱趋势图（红色支出、绿色收入），柱状高度由月度聚合数据自适应计算；
  - 支付途径分布：展示各渠道消费总额与百分比。
- **Acceptance Criteria**：
  - 完整呈现本周、当月、上月花费、当月结余四大指标；
  - 图表编码一致，信息密度饱满且对比度达标；
  - 交互下钻顺畅，空状态与加载态过渡平滑。

### TASK-010：实现设置页一体化分组管理工作台

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/pages/SettingsPage.tsx` 中实现支付途径磁贴网格与消费类型-细分标签内嵌分组管理。
- **Details**：
  - 模块 1（支付途径）：紧凑的磁贴网格展示各结算通道，支持行内快捷新增、编辑与删除；
  - 模块 2（消费类型与下属细分标签）：
    - 采用分行分组卡片：每行呈现消费类型图标、名称及下属标签数；
    - 标签芯片默认纯净呈现，`✕` 删除按钮仅在鼠标 hover 浮现，极大降低视觉噪点；
    - 每个分类行提供行内 `+ 新增细分标签` 按钮与右上角添加入口；
  - 采用 Layer 3 Fluent 对话框进行修改输入，右上角浮动通知（Toast）给予柔和操作反馈；
  - 统一捕获后端 409 Conflict 异常并向用户展示清晰友好的阻断提示（如“已有账单关联，无法删除”）。
- **Acceptance Criteria**：
  - 彻底抛弃空洞的三塔式布局，改为信息密度高、逻辑自然的分组流式卡片；
  - 增删改查逻辑完整，数据即时同步至记账录入面板的选项中。

---

## Phase 5：端到端集成验证与单二进制产物交付

### TASK-011：编写后端与前端集成测试并验证无回归

- **Status**：DONE
- **Executor**：主线（Executor环境受限接力）
- **Description**：补充完整的后端业务端点集成测试（`internal/server/server_test.go`），并执行前端 TypeScript 编译与语法检查。
- **Details**：
  - 测试用例覆盖：密码验证（含 500ms 延迟防爆破）、账单创建与 PUT 更新、整数分求和、级联标签校验、花费统计时间计算（覆盖跨月跨年）、409 删除引用阻断；
  - 前端执行 `npm run lint`（`tsc -b --noEmit`），确保所有 TypeScript 类型定义严密且零编译警告。
- **Acceptance Criteria**：
  - `go test -v ./...` 全部测试绿色通过；
  - 前端编译检查零错误。

### TASK-012：执行单二进制全流程构建与自动化冒烟验证及文档维护

- **Status**：DONE
- **Executor**：主线（Executor环境受限接力）
- **Description**：执行 `make build` 打包全量静态资源至 Go 单二进制 `bin/ledger`，并通过自动化 CLI/curl 冒烟测试全链路，最后同步更新 `.docs/Project.md`。
- **Details**：
  - 执行 `cd web && npm run build` 生成 `web/dist`；
  - 执行 `go build -o bin/ledger ./cmd/server` 编译独立二进制；
  - 启动后台进程 `PORT=8080 bin/ledger`，执行自动化 curl 冒烟验证：
    1. `GET /health` 响应 200 `{ "status": "ok" }`；
    2. `GET /` 响应 200 并包含嵌入的前端单页应用 HTML；
    3. `POST /api/auth/login` 传入密码验证成功换取有效 Token；
    4. 携带 Token 请求 `GET /api/payment-methods`、`GET /api/categories`、`GET /api/transactions`、`GET /api/stats/summary` 均响应 200 且返回数据结构健全；
    5. 测试完毕优雅终止测试服务进程；
  - 同步更新 `.docs/Project.md` 的架构、接口、环境变量与数据表结构描述。
- **Acceptance Criteria**：
  - `bin/ledger` 独立启动无外部依赖；
  - 自动化 curl 冒烟验证 5 项检查全绿通过；
  - `.docs/Project.md` 完整记录所有对外接口、配置项与数据表字段，与代码库实际状态一致。
