# Tasks：订阅固定开支管理页

**关联 Plan**：Plan.md —— 订阅固定开支管理页 v1.1
**状态**：DONE（2026-10-31）
**日期**：2026-10-31
**版本**：v1.1（2026-10-31 评审修订）
**总计 Task**：13 个
**执行主体**：主线

---

## 前置约定

- 设计基线为 Microsoft Fluent 2：沿用 web/src/index.css 的四层材质令牌、Segoe UI 字体栈、4/8px 间距与现有 Panel/Button/OverflowMenu 构件，不新增硬编码色值或第三方 UI 依赖。
- Demo 为 temp/subscriptions-page-demo.html：Hero、五段导航、分组、行菜单、添加/编辑/分组/确认弹层、明暗主题与 320/360/400/420/640/1440 视口均已自检（含 Tab 与操作区不相交）。实现以 Demo 的排版节奏与信息层级为准，数据与交互以本文件契约为准。
- 金额计算只用整数分；API 同时返回 amount_cents 与 amount。前端汇总不得直接累加浮点 amount。
- 所有新增 API 均走 RequireAuth；页面不写 localStorage 业务数据。
- 本机门禁（基线 2026-10-29：Web 38 项测试通过；Go 全包通过）：

  gofmt -l .
  go vet ./...
  go test -count=1 ./...
  cd web && npm run lint && npm test && npm run build

- 既有工作区存在 24 个已暂存的技能/规则文件、7 个 .pi 删除、temp/redesign-demo.html 删除与两张用户截图；不恢复、不 reset 这些既有暂存，不纳入提交。
- 根目录 Plan.md / Tasks.md 在本轮执行完成后按 Archive 流程移入 .docs/MM-DD-vN/。

---

## Phase 1：持久化与订阅 API

### TASK-001：新增订阅分组与订阅表

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / 无
- **Description**：在 internal/db/db.go 的 schema 中新增 subscription_groups 与 subscriptions 两张表，包含外键、检查约束与分组索引；现有库通过 CREATE TABLE IF NOT EXISTS 自动升级，不注入任何示例订阅。
- **Details**：
  - subscription_groups：id INTEGER PRIMARY KEY AUTOINCREMENT、name TEXT NOT NULL COLLATE NOCASE UNIQUE、sort_order INTEGER DEFAULT 0、created_at TEXT DEFAULT CURRENT_TIMESTAMP。
  - subscriptions：id INTEGER PRIMARY KEY AUTOINCREMENT、group_id INTEGER DEFAULT NULL REFERENCES subscription_groups(id) ON DELETE SET NULL、name TEXT NOT NULL、amount_cents INTEGER NOT NULL CHECK(amount_cents > 0)、billing_day INTEGER NOT NULL CHECK(billing_day BETWEEN 1 AND 31)、status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','paused'))、created_at TEXT DEFAULT CURRENT_TIMESTAMP。
  - 新增 CREATE INDEX IF NOT EXISTS idx_subscriptions_group_id ON subscriptions(group_id)。
  - 建表位置在 payment_methods / transactions 之后；不改变现有 seed 逻辑，也不新增默认分组。
  - 在 internal/db/db_test.go 增加建表与约束用例：全新库存在两表；插入分组/订阅后删除分组，订阅仍在且 group_id 为 NULL；billing_day=0、32 与 status='archived' 被约束拒绝；插入 Apple 后再插入 apple 被 UNIQUE 拒绝；对同一路径连续调用 InitDB 两次不报错且数据不重复。
  - 复用既有旧库夹具方式补一例：已有 payment_methods/transactions 数据的库升级后两表存在，旧行数不变。
- **Acceptance Criteria**：
  - gofmt -l internal/db 无输出；go test -count=1 ./internal/db 全部通过。
  - 既有 TestInitDB / TestOldDatabaseUpgrade / TestPaymentMethodsMigration / TestTransactionsMigration / TestCategoriesMigration 不回归。
  - 删除分组后订阅记录仍存在且 group_id 为 NULL。

### TASK-002：分组 CRUD 端点与集成测试

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-001
- **Description**：新增 internal/server/subscriptions.go，定义 SubscriptionGroup 模型与四个分组 Handler；在 internal/server/server.go 注册鉴权路由。
- **Details**：
  - 模型字段：ID int64 json id、Name string json name、SortOrder int json sort_order、CreatedAt string json created_at。
  - GET /api/subscription-groups：ORDER BY sort_order ASC, id ASC，返回 [] 而不是 null。
  - POST /api/subscription-groups：请求 name、sort_order；TrimSpace 后非空；重复名返回 400（复用 isUniqueConstraintError）；成功 201。
  - PUT /api/subscription-groups/{id}：请求 name、sort_order；校验 id、名称与重复名；不存在返回 404；成功 200。
  - DELETE /api/subscription-groups/{id}：直接删除分组，依赖已启用的外键 ON DELETE SET NULL 将组内订阅转为未分组；成功返回 {"success":true}；不存在 404。不要再写第二条 UPDATE，避免同一语义双重保障。
  - 所有路由包裹 s.requireAuth；沿用 writeJSON / writeJSONError，不新增响应包装。
  - 新建 internal/server/subscriptions_test.go：覆盖创建、列表顺序、重命名、精确重复名与 Apple/apple 400、空名 400、非法 id 400、404、删除分组后组内订阅 group_id 为空、未带 Authorization 返回 401。
- **Acceptance Criteria**：
  - gofmt -l internal/server 无输出；go vet ./... 退出码 0。
  - go test -count=1 ./... 全部通过，既有用例不回归。
  - 删除分组不会删除其订阅；未登录访问任一分组端点返回 401。

### TASK-003：订阅 CRUD 端点与参数校验

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-001, TASK-002
- **Description**：在 internal/server/subscriptions.go 增加 Subscription 模型与四个订阅 Handler，注册鉴权路由，并补齐金额、日号、状态与分组存在性校验。
- **Details**：
  - 模型字段：ID、GroupID *int64 json group_id（未分组输出 null）、Name、AmountCents int64 json amount_cents、Amount float64 json amount、BillingDay int json billing_day、Status string json status、CreatedAt。
  - GET /api/subscriptions：ORDER BY group_id IS NULL, group_id ASC, billing_day ASC, id ASC；amount = amount_cents / 100。
  - POST /api/subscriptions：请求 name、group_id、amount、billing_day、status（可省略，默认 active）。名称 TrimSpace 非空；amount 在 0.01–1,000,000.00 元之间，转换为 int64(math.Round(amount*100)) 后必须 > 0，否则 400；billing_day 1–31；status 仅 active/paused；group_id 为 0/null 视为未分组，>0 必须存在，<0 显式拒绝，均返回 400。成功 201。
  - PUT /api/subscriptions/{id}：全量更新 name、group_id、amount、billing_day、status；同样校验；不存在 404；成功 200。
  - DELETE /api/subscriptions/{id}：成功 {"success":true}；不存在 404。
  - 扩展 internal/server/subscriptions_test.go：无分组创建、带分组创建、金额 0/负数/0.001（不足 1 分）/1,000,000.01 400、billing_day 0/32 400、status 非法 400、group_id 不存在或为 -1 400、更新后改组/暂停生效、列表金额与 cents 对应、删除后列表不再包含、未登录 401。
- **Acceptance Criteria**：
  - 创建成功后 amount_cents 与输入金额按分四舍五入一致；金额为 12.345 时落为 1235 分。
  - 暂停状态在列表中原样返回，不会影响其他记录。
  - gofmt、go vet、go test 全部通过。

---

## Phase 2：客户端契约与导航接入

### TASK-004：订阅 API 模型与客户端方法

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-002, TASK-003
- **Description**：在 web/src/lib/api.ts 增加 SubscriptionGroup、Subscription、SubscriptionInput 类型，并在 api 对象中增加分组与订阅的 8 个方法。
- **Details**：
  - SubscriptionGroup：id、name、sort_order、created_at。
  - Subscription：id、group_id number | null、name、amount_cents、amount、billing_day 1..31（类型写 number）、status 'active' | 'paused'、created_at。
  - SubscriptionInput：name、group_id number | null、amount、billing_day、status。
  - 方法：getSubscriptionGroups、createSubscriptionGroup、updateSubscriptionGroup、deleteSubscriptionGroup、getSubscriptions、createSubscription、updateSubscription、deleteSubscription。
  - DELETE 返回 Promise，成功体为 { success: boolean }；创建/更新返回对应实体；沿用 request 泛型，不绕过 401 拦截。
  - 不修改既有类型和请求函数。
- **Acceptance Criteria**：
  - cd web && npm run lint 通过。
  - 所有方法路径、方法动词与 Phase 1 契约一致，请求体字段为 snake_case。

### TASK-005：五段导航与订阅页挂载

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-004
- **Description**：在 web/src/components/Icons.tsx 增加 SubscriptionIcon（循环箭头语义）；在 Navbar.tsx 扩展 TabType 与五项导航；在 App.tsx 渲染 SubscriptionsPage 并传入鉴权状态与 Toast。
- **Details**：
  - SubscriptionIcon：24 viewBox、stroke 2、15px 默认，语义为循环/续费；不引入图标库。
  - TabType 增加 'subscriptions'；顺序为 stream、stats、subscriptions、assets、settings。
  - 五项文案改为「流水」「统计」「订阅」「资产」「设置」；compact 仍为 640px 以下隐藏文字，aria-label 保持完整。
  - 为五项导航传入窄屏 padding 覆盖：className="[&>button]:px-[7px] min-[420px]:[&>button]:px-2.5"，使 420px 以下 nav 最小内容宽从 191px 降到 161px，420px 起恢复 10px；不隐藏品牌和操作按钮。
  - App 导入 SubscriptionsPage；currentTab === 'subscriptions' 时渲染 SubscriptionsPage 组件，传入 authenticated 与 onToast 两个 props。
  - 不把订阅数据提升到 App；不改变 stats / config 的既有拉取条件。
  - 320/360/400/420px 下 topbar 的 brand、五项 tab、主题、登出全部可见；documentElement.scrollWidth <= clientWidth，最后一个 .tab 右缘小于 .actions 左缘，五个 .tab 中心 elementFromPoint 命中自身或子元素。
- **Acceptance Criteria**：
  - cd web && npm run lint 通过。
  - 点击五项导航均切换正确页面；订阅 Tab 在桌面显示文字、移动端显示循环图标。
  - 320/360/400/420px 下无横向滚动、无 Tab 遮挡；现有四页布局不回归。

---

## Phase 3：订阅页展示与管理

### TASK-006：订阅派生纯函数

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-004
- **Description**：新增 web/src/pages/subscriptionsUtils.ts，集中处理下次续费日、7 天窗口、月度/年度汇总、状态筛选与分组分区，页面不自行散写这些规则。
- **Details**：
  - 类型：SubscriptionFilter = 'all' | 'active' | 'paused'；SubscriptionSection 包含 key、name、group、items、activeCount、totalCount、monthlyCents（只计使用中）。
  - startOfLocalDay(now) 与 daysInMonth(year, monthIndex)；不修改传入 Date。
  - nextRenewalDate(billingDay, now)：取本月 min(day, 月末) 的本地零点；若早于今天则取下一月 min(day, 下月月末)，跨年正确。今天到期返回今天。
  - calendarDayDiff(from, to)：用 Date.UTC(y,m,d) 计算整天差，避免 DST 影响。
  - formatRenewalDate(date)：返回「M 月 D 日」用于行内「下次」。
  - summarizeSubscriptions(subs, now)：monthlyCents 只加 active；annualCents = monthlyCents * 12；upcomingCents / upcomingCount 只统计 active 且 0 ≤ dayDiff ≤ 6；activeCount。
  - buildSubscriptionSections(groups, subs, filter, now)：分组按 sort_order、id；组内按 nextRenewalDate、name.localeCompare('zh-CN')；未分组最后；filter='all' 保留空分组，active/paused 只留有匹配项的分组；未分组只在有匹配项时出现。
  - 不读写 DOM、不调用 API、不引入日期库。
- **Acceptance Criteria**：
  - 文件可被 node --experimental-strip-types 直接导入，无浏览器 API。
  - 所有金额派生只使用 amount_cents，函数无浮点累加。
  - 页面只消费这些派生结果，不再重复实现续费日或合计逻辑。

### TASK-007：页面骨架、Hero、筛选与分组列表

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-005, TASK-006
- **Description**：新增 web/src/pages/SubscriptionsPage.tsx 的只读展示层：页面头、月度 Hero、状态筛选、分组分区、行内容、加载/错误/空态；数据加载与刷新在页面内完成。
- **Details**：
  - Props：authenticated: boolean；onToast: (type, message) => void。
  - 状态：groups、subscriptions、loading、loadError、refreshError、filter、openMenu、待处理弹窗状态；首次 authenticated=true 时 Promise.all 拉取两组数据；登录状态从 false 变 true 时按 initial 模式加载。load('initial') 清空数据并显示 Skeleton；load('refresh') 保留当前数据、不置 loading，只更新 refreshError。
  - 页面头：h1「订阅」；右侧「新建分组」ghost 按钮与「添加订阅」primary 按钮，320px 下均保留文字（实测 200px 操作区与 39px 标题可共存）。
  - Hero 使用 Panel variant="hero"：eyebrow「每月固定开支」+ Chip「N 项使用中」；月合计使用 formatMoney(monthlyCents/100, {sign:'none'})；右侧「年度预估」「未来 7 天」；底部 7px 分组分布条，按 buildSubscriptionSections(all) 的 monthlyCents 与 donutColor(index) 绘制，role="img" + aria-label。
  - 工具栏：全部 / 使用中 / 已暂停三个过滤按钮放在 role="group" 容器中，使用 aria-pressed 表达选中（普通按钮不使用无效的 aria-selected）；右侧「共 N 项」或「N 项已暂停」。
  - 分组卡：Panel p-0 overflow-visible；分组头用 sunken 底 + donutColor 小方点 + 名称 + 使用中项数（暂停筛选时显示已暂停项数）+ 使用中月合计 + OverflowMenu 占位；行含 34px 首字母瓦片、名称、状态 Chip（仅暂停显示）、「每月 X 日 · 下次 M 月 D 日」、金额 / 月、行菜单占位。
  - 空分组在 all 视图显示 0 项、¥0.00 / 月，并渲染一行「暂无订阅」+「添加」按钮；暂停筛选下分组小计显示 —（无使用中金额），组内暂停行仍显示各自金额；未分组分区不显示分组菜单。
  - 状态：加载时 Hero 与两组 Skeleton；首次加载/重试失败清空 groups 与 subscriptions，显示错误面板与「重试」，不显示旧数据；变更后的刷新失败走 refreshError，不在本 Task 处理。无任何订阅且无分组时只显示 EmptyState「还没有订阅」+「添加第一个订阅」，不渲染零值 Hero 与空分组；有分组但无订阅时保留 Hero 0 与空分组；筛选后无结果时显示「暂无使用中的订阅 / 暂无已暂停的订阅」+「查看全部」。
  - 320px 行内元信息允许两行，金额与菜单不被挤压；不新增 CSS 令牌。
- **Acceptance Criteria**：
  - 首屏在没有数据时不会出现 NaN、undefined 或空金额。
  - 分组小计只含使用中；暂停行不计入 Hero、分组小计与未来 7 天。
  - 320/360/400/420/640/1440 宽度下无横向滚动；暗色主题文字与边框可辨。
  - 首次加载或重试失败时清空上一轮数据并保留重试入口；变更后刷新失败的行为由 TASK-009 覆盖。

### TASK-008：订阅与分组表单弹层

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-007
- **Description**：在 SubscriptionsPage.tsx 内实现 SubscriptionDialog 与 GroupDialog：Portal 挂载、焦点进入、Esc/遮罩关闭、滚动锁定、字段校验与提交反馈；弹层只通过回调提交，不直接调用页面状态。
- **Details**：
  - SubscriptionDialog 支持 create / edit；字段：服务名称（required、maxlength 60）、分组 select（全部分组 + 未分组）、每月金额（number、min 0.01、max 1000000、step 0.01、¥ 前缀）、扣款日（number、1–31、日 后缀）；提交按钮显式 type="submit"。
  - create 默认 active、分组为当前分区或未分组；edit 回填 name、group_id、amount、billing_day、status；状态不在表单内修改，由行菜单负责。
  - 校验：名称 TrimSpace 非空；金额在 0.01–1,000,000.00 之间；扣款日为 1–31 整数；分组 id 必须存在于当前 groups 或为 null。错误在字段下方内联显示并聚焦首个错误字段；服务端失败时保留弹层与输入，Toast 显示错误。
  - GroupDialog 支持 create / rename；名称 required、maxlength 30；重复名（大小写不敏感）内联提示；提交中禁用按钮。
  - 两个弹层使用 createPortal 到 document.body；role="dialog"、aria-modal、aria-labelledby/aria-label；打开后聚焦首个输入，关闭后焦点回到触发元素；打开时锁定 body overflow；Esc 先关弹层；提交通过回调交给页面，不在弹层内直接调用 API。
  - 输入字号在移动端 16px，避免 iOS 聚焦缩放；按钮沿用 Button，外壳沿用 surface / line / r--xl / e4 令牌。
- **Acceptance Criteria**：
  - 320x568 下两个弹层完整可见、可滚动、无字段被截断；添加订阅表单在 320 宽度下两个数字字段并排不溢出。
  - 空名称、0 金额、32 日、重复组名均无法提交并显示明确错误。
  - 关闭弹层不产生请求；提交成功后才关闭并刷新。

### TASK-009：管理动作、菜单与刷新链路

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-008
- **Description**：接通新增、编辑、暂停/恢复、删除订阅；新建/重命名/上移/下移/删除分组；空分组添加；所有变更成功后重新拉取数据并 Toast，失败保留上下文。
- **Details**：
  - 行 OverflowMenu：编辑、暂停续费（active 时）/恢复续费（paused 时）、分隔线、删除。暂停/恢复用全量 PUT 提交当前行字段。
  - 分组 OverflowMenu：在此分组添加订阅、重命名、上移、下移、分隔线、删除；首组禁用上移、末组禁用下移；未分组无菜单。
  - 新建分组 sort_order = 当前最大 sort_order + 1；重命名保留 sort_order；上移/下移后把新顺序写成 1..N，逐个 PUT 有变化的项，任一步失败都重新加载并 Toast。
  - 删除订阅用 ConfirmDialog：标题「删除订阅」、detail 为服务名、confirmLabel「删除」、tone danger。删除分组用 ConfirmDialog：说明组内 N 项订阅将移至未分组，detail 为组名与 N。
  - 删除分组成功 Toast「分组已删除，订阅已移至未分组」；删除订阅成功 Toast「订阅已删除」；新增/修改/暂停/恢复/分组操作均有对应成功文案。失败显示服务端错误或「操作失败」。
  - 单一 openMenu 状态保证同时只开一个菜单；页面 Esc 优先关 ConfirmDialog / 弹层，其次关菜单；点击空白关闭菜单。
  - 变更后统一 await load('refresh')；不做乐观更新。refresh 模式不置 loading、不清空数据；若失败，保留当前可见数据，设置 refreshError 并在列表上方显示「数据未同步」+「重试」轻提示，同时 Toast；重试按钮再次调用 load('refresh')，成功后清除 refreshError。
  - 空分组行「添加」直接打开该组的 create 对话框；分组菜单「在此分组添加」相同。
- **Acceptance Criteria**：
  - 新增/编辑后行内容、Hero、分组小计、未来 7 天与年度预估同步更新。
  - 暂停后该行不计入任何总额，恢复后恢复计入；状态 Chip 与行菜单文案同步切换。
  - 删除分组后其订阅出现在「未分组」，且组内金额仍计入 Hero。
  - 菜单不被分组卡裁切；320px 下首行与最后一行菜单都可见。
  - 首次加载失败显示清空后的错误面板；变更后刷新失败保留数据与「数据未同步」提示，重试成功后提示消失。
  - 所有 API 失败路径不会关闭用户正在编辑的弹层或丢失输入。

---

## Phase 4：纯函数、接口与界面回归

### TASK-010：订阅纯函数测试

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-006
- **Description**：新增 web/test/subscriptions.test.ts，使用 node:test + node:assert/strict 覆盖续费日推导、7 天窗口、汇总与分组。
- **Details**：
  - 固定本地日期构造：new Date(2026, 9, 31)（2026-10-31）、new Date(2027, 1, 10)（2027-02-10）、new Date(2026, 11, 31)。
  - nextRenewalDate：10-31 的 1 日 -> 11-01；10-31 的 5 日 -> 11-05；10-31 的 31 日 -> 10-31（今天）；12-31 的 1 日 -> 次年 01-01；2027-02-10 的 31 日 -> 02-28；2027-04-10 的 31 日 -> 04-30。
  - summarize：active 68 + 15 + 72 = 155 元时 monthlyCents=15500、annualCents=186000；paused 35 不计；upcoming 只含 diff 0–6；diff 7 排除；空数组全 0。
  - buildSubscriptionSections：分组排序、组内按下次续费日、无分组最后、all 保留空组、active 过滤隐藏空组与暂停组、paused 只显示暂停项。
  - formatRenewalDate 固定输出「11 月 5 日」；不依赖运行时时区以外的东西。
- **Acceptance Criteria**：
  - cd web && npm test 全部通过，新增用例 ≥10 条。
  - 任意一条边界被改坏时对应用例失败（例如去掉月末夹取、把 7 天窗口写成 ≤7、把暂停计入合计）。
  - 既有 stream/assets/format 测试不回归。

### TASK-011：全量门禁与浏览器复核

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-001 ~ TASK-010
- **Description**：执行 Go 与 Web 全量门禁，并在浏览器中对订阅页做多视口、明暗主题与关键交互复核，记录实际通过项数与发现的问题。
- **Details**：
  - gofmt -l . 无输出；go vet ./... 退出码 0；go test -count=1 ./... 记录 db / server 用例数。
  - cd web && npm run lint、npm test、npm run build 均退出码 0；记录测试项数与 build 产物。
  - 浏览器检查 320x568、360x800、400x800、420x800、640x900、1440x900：五项导航、Hero、筛选、分组菜单、行菜单、添加/编辑弹层、分组弹层、确认框、暗色主题；每个视口断言 scrollWidth <= clientWidth、最后一个 Tab 与 actions 不相交、五个 Tab 中心点命中。
  - 检查 640px 视口 + 200% 页面缩放（等效 320 CSS px）下页面无横向滚动，弹层内容可滚动。
  - 检查键盘路径：Tab 可达所有按钮；Esc 关闭当前层；弹层关闭后焦点回到触发按钮。
  - 检查筛选：全部/使用中/已暂停的数量、分组小计与空态一致；筛选不改变 Hero 总额；筛选按钮的 aria-pressed 随状态切换。
  - 发现布局或交互问题时回到对应 Task 修正，再重跑受影响门禁。
- **Acceptance Criteria**：
  - 所有门禁退出码 0，记录实际数字。
  - 六种视口均无横向滚动、无内容裁切、无 Tab 遮挡、无不可达操作。
  - 明暗主题下正文、次要信息、边框与主按钮对比可辨。
  - 无 console error；无死链、无 TODO 或占位文案进入界面。

---

## Phase 5：文档、归档与提交

### TASK-012：Project.md 与实现同步

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-011
- **Description**：更新 .docs/Project.md 的阶段、结构、数据流与测试记录，确保文档只描述已落地的事实。
- **Details**：
  - 阶段描述补充「订阅固定开支管理」。
  - 结构树补充 internal/server/subscriptions.go、internal/server/subscriptions_test.go、web/src/pages/SubscriptionsPage.tsx、web/src/pages/subscriptionsUtils.ts、web/test/subscriptions.test.ts；Navbar 说明改为五段导航。
  - 数据流补充 /api/subscription-groups 与 /api/subscriptions 的鉴权、CRUD 与分组删除转未分组语义。
  - 测试记录补本轮日期、新增用例数与门禁实际结果。
  - 不提前宣称未完成项；不修改 SCOPE.md。
- **Acceptance Criteria**：
  - Project.md 中不存在与实际文件/路由/字段不一致的描述。
  - 未新增过期的临时说明或未实现能力。
  - 本轮改动路径在白名单内；工作区既有无关改动未被触碰。

### TASK-013：归档与提交

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-012
- **Description**：将 Plan.md / Tasks.md 标记 DONE、补完成日期与回归结论，按 Archive 规则移入 .docs/MM-DD-vN/，并按路径提交本轮变更。
- **Details**：
  - 归档目录：以执行日为准，格式 MM-DD-vN；查询 .docs 下同日前缀，取最大 N + 1；本轮预计 10-31-v1。
  - 归档前在 Plan.md 与 Tasks.md 的完成记录写入：完成日期、交付结果、门禁命令与项数、变异校验（如移除月底夹取/暂停排除后测试失败）。
  - 移动后校验 .docs/MM-DD-vN/ 同时含 Plan.md 与 Tasks.md，根目录无残留。
  - git status / git diff / git log 检查；记录当前 git diff --cached --name-only 的既有暂存清单。不要执行 git reset，避免改动用户既有暂存区。
  - 只 git add 白名单路径；禁止全局 git add -A / git add .。Plan/Tasks 已移动，需用 scoped 命令暂存删除与新增：git add -A -- Plan.md Tasks.md .docs/MM-DD-vN/。随后用 pathspec 提交：git commit -- 白名单路径。这样 24 个既有暂存文件不会进入 HEAD，但仍保持暂存。
  - 白名单：internal/db、internal/server/subscriptions.go、internal/server/subscriptions_test.go、internal/server/server.go、web/src/lib/api.ts、web/src/components/Icons.tsx、web/src/components/Navbar.tsx、web/src/App.tsx、web/src/pages/SubscriptionsPage.tsx、web/src/pages/subscriptionsUtils.ts、web/test/subscriptions.test.ts、.docs/Project.md、.docs/MM-DD-vN/、Plan.md、Tasks.md、temp/subscriptions-page-demo.html。
  - 提交前用 git diff --cached --name-only -- 白名单路径 核对已暂存内容；提交后用 git show --name-only HEAD 确认只含白名单。不提交技能文件、.pi 删除、temp/redesign-demo.html 删除、两张截图。
  - 提交信息使用英文 Conventional Commits 前缀 + 中文描述，聚焦为什么；不加 --no-verify，不 amend。
- **Acceptance Criteria**：
  - 归档目录同时含 Plan.md 与 Tasks.md，根目录无 Plan.md / Tasks.md。
  - git show --name-only HEAD 只含白名单路径；既有 24 个暂存文件仍未进入 HEAD 且保持暂存。
  - 未使用全局 git add -A、git add .、git reset 或 --no-verify；仅对 Plan/Tasks 迁移使用 scoped git add -A -- Plan.md Tasks.md .docs/MM-DD-vN/。
  - 提交信息符合项目规范，工作区无关改动保持原状。

---

## 完成记录

- **状态**：DONE（2026-10-31），13 个 Task 全部完成。
- **交付**：Phase 1 订阅两表与 8 个鉴权端点（含校验、401、删组转未分组）；Phase 2 客户端契约、五段导航与订阅页挂载；Phase 3 Hero/筛选/分组列表、订阅与分组弹层、管理动作与两态刷新；Phase 4 纯函数测试与全量门禁、浏览器多视口复核；Phase 5 Project.md 同步、归档 `.docs/10-31-v1/` 与 pathspec 提交。
- **门禁**：`gofmt -l .` 无输出；`go vet ./...` 0；`go test -count=1 ./...` 全包通过（db + server 29 项）；`cd web && npm run lint` 0；`npm test` 52 项通过（新增 14 项）；`npm run build` 成功。
- **变异校验**：移除 `nextRenewalDate` 月末夹取后短月用例失败；移除 `summarizeSubscriptions` 暂停排除后 2 项失败；恢复后复跑全部通过。
- **浏览器复核**：320/360/400/420/640/1440 视口无横向滚动与 Tab 遮挡；筛选、菜单、弹层、确认、删组转未分组、加载失败与刷新失败重试均通过；控制台无 error。
