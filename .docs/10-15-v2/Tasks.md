# Tasks：收支统计页重构与资产概览页独立

**状态**：DONE
**完成日期**：2026-10-15
**回归测试**：全量单元与集成测试（`make test`）37 项前端自检与全部后端测试通过，前端构建（`npm run build`）成功
**关联 Plan**：`Plan.md` —— v1.1
**总计 Task**：8 个（全部完成）

---

## Phase 1：资产派生纯函数与自检

### TASK-001：新增资产派生模块
- **Status**：DONE
- **Executor**：主线
- **Description**：新增 `web/src/pages/assetsUtils.ts`，导出 `deriveAssets(summary: AssetSummary)`。
- **Details**：
  - 返回 `assets`（按 remaining_balance 降序）、`liabilities`（按 current_debt 降序）
  - 每个资产项附 `share`：max(0, 余额) / Σmax(0, 余额) × 100，分母为 0 时为 0（`share` 为资产页占比唯一口径，刻意不消费后端 `AssetChannelStat.percentage`，规避负余额渠道导致的占比失真）
  - 返回 `debtRatio`：total_assets > 0 ? total_liabilities / total_assets × 100 : null
  - 返回 `credit`：仅统计 credit_limit > 0 的负债，{ limit, used, usage, available }；无额度负债时为 null；available = max(limit − used, 0)
- **Acceptance Criteria**：`npm run lint` 通过；模块无 React 依赖

### TASK-002：资产派生自检
- **Status**：DONE
- **Executor**：主线
- **Description**：新增 `web/test/assets.test.ts`（node:test，沿用 stream.test.ts 写法：`.ts` 后缀导入 + `--experimental-strip-types`）。
- **Details**：覆盖降序排序、负余额 share 为 0 且其余 share 合计 100、total_assets=0 时 debtRatio 为 null、无额度负债不计入 credit、全部无额度时 credit 为 null
- **Acceptance Criteria**：`cd web && npm run test` 全部通过

---

## Phase 2：资产概览页与导航接入

### TASK-003：新增资产概览页
- **Status**：DONE
- **Executor**：主线
- **Description**：新增 `web/src/pages/AssetsPage.tsx`，props：`stats`、`loading`、`onManageChannels`。
- **Details**：
  - Hero（Panel variant="hero"）：「净资产」标签 + 眼睛 IconButton（`pressed` prop 透传 `aria-pressed`，label 切换「隐藏金额/显示金额」，见 TASK-004）；40px 主数值（负值 expense-text 与 − 号）；右列资产总计/负债总计/资产负债率（null 显示「—」）；底部 10px 堆叠分布条，色阶取 Charts 同源 `--donut-1..5`，role="img" 带 aria-label
  - 隐藏状态存 localStorage `ledger_hide_amounts`，隐藏时全部金额替换为「••••••」，百分比保留
  - 双列面板（≥768px 两列）：行首瓦片按账户类型统一图标、不使用名称首字：「资产账户」行 = WalletIcon 瓦片（brand-soft）+ 名称 + 副行（6px 分布色点 + 占比，色点与分布条同色以维持对应）+ 余额；「负债账户」行 = CreditCardIcon 瓦片（expense-soft）+ 名称 + 「可用 X · 额度 Y」或「不设额度」+ 欠款 + 额度 Rail（≥80% 切 expense 语义，与原 StatsPage 规则一致）；负债面板头下方展示总额度使用率与可用（credit 非 null 时）
  - 分布条 ↔ 行联动以 AssetsPage 内 `activeIndex` state 驱动（分布条位于 Hero、行位于双列 Panel，跨 DOM 子树无法用纯 CSS 选择器）：资产行 `onMouseEnter` 设 `activeIndex`、`onMouseLeave` 清空，分布条非对应段 opacity 降至 0.28，过渡用 `--d2`；只读展示行不设 `tabIndex`（无键盘操作，避免空 Tab 停靠点）
  - 面板头右侧「管理」ghost 按钮调用 onManageChannels；资产空态 EmptyState 带「添加资产账户」action 同样调用 onManageChannels；负债空态无 action
  - 加载骨架：Hero 210px + 双列 260px
- **Acceptance Criteria**：lint 通过；界面无解释性文案；所有金额经 formatMoney

### TASK-004：新增眼睛与信用卡图标
- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/components/Icons.tsx` 新增 `EyeIcon`、`EyeOffIcon`、`CreditCardIcon`（圆角卡面 + 磁条线 + 短签名线），沿用 aria-hidden、24 viewBox、2 描边圆头线帽约定；并在 `web/src/components/primitives.tsx` 为 `IconButton` 增加可选 `pressed?: boolean`，透传为 `aria-pressed`（未传时不渲染该属性，既有调用点零影响）。
- **Acceptance Criteria**：lint 通过；无零引用导出

### TASK-005：导航与 App 接入
- **Status**：DONE
- **Executor**：主线
- **Description**：修改 `web/src/components/Navbar.tsx`、`web/src/App.tsx`、`web/src/pages/SettingsPage.tsx`。
- **Details**：
  - Navbar：`TabType` 增加 `'assets'`；TAB_ITEMS 顺序为 账目流水 / 收支统计 / 资产概览（WalletIcon）/ 基础设置；admin 胶囊显示断点 `min-[640px]` → `min-[768px]`
  - App：stats 拉取条件改为 `currentTab === 'stats' || currentTab === 'assets'`（加载 effect、保存后刷新、删除后刷新、登录成功回调四处同步）；渲染 AssetsPage，onManageChannels 切换至设置页渠道分区
  - SettingsPage：新增可选 prop `initialSection?: 'categories' | 'paymentMethods'` 作为 activeTab 初始值（内部 activeTab 仍为 state，靠 App 侧 `key={currentTab}` 重挂载生效）
  - App 持有 `settingsSection` state，进入设置页的三条入口须逐一显式设置，杜绝重挂载残留上次分区：① 顶栏 `onTabChange('settings')` → `'categories'`；② 资产页「管理」→ `'paymentMethods'`；③ RecordModal `onNavigateToSettings`（记账页「暂无负债渠道」引导）→ `'paymentMethods'`
- **Acceptance Criteria**：lint 通过；资产页「管理」进入设置页直接显示渠道分区；从渠道分区经顶栏切走再回设置页显示分类分区（无分区残留）；320 / 640 / 768px 顶栏单行不溢出

---

## Phase 3：收支统计页重构

### TASK-006：重构收支统计页
- **Status**：DONE
- **Executor**：主线
- **Description**：重写 `web/src/pages/StatsPage.tsx` 的资产相关部分。
- **Details**：
  - 删除净资产 Hero、资产/负债渠道双列面板与对应 ChannelRow 负债分支、WalletIcon 等失效导入
  - 新 Hero（variant="hero"）：「N 月结余」标签（N 取当前本地月）+ 40px 带符号结余（正 income-text / 负 expense-text）+ 收入、支出两列数值 + 6px 收入/支出比例分布条（收入+支出为 0 时不渲染）+ 储蓄率 Chip
  - 指标行四格：本周花费 / 当月花费（含较上月注脚）/ 上月花费 / 日均花费（month_expense ÷ 当月已过天数）
  - 双列：当月支出构成（DonutChart 原样）+ 近 6 个月收支（TrendChart 原样）
  - 当月支付途径分布面板保留现有实现，置于双列之后
  - 骨架同步为 Hero 170px + 指标 96px + 双列 230px
- **Acceptance Criteria**：lint 通过；grep `asset_summary` 在 StatsPage.tsx 无结果；空态文案沿用现有 EmptyState

---

## Phase 4：测试与文档

### TASK-007：构建与全量测试
- **Status**：DONE
- **Executor**：主线
- **Description**：执行 `make test` 与 `cd web && npm run build`；对照 Demo 在浅/深主题、320/768/1280px 检查资产页与统计页。
- **Acceptance Criteria**：命令退出码均为 0；不保留 dist 以外的临时产物

### TASK-008：同步 Project.md 并清理 Demo
- **Status**：DONE
- **Executor**：主线
- **Description**：更新 `.docs/Project.md` 结构树（AssetsPage.tsx、assetsUtils.ts、assets.test.ts，StatsPage 描述改为收支看板，Navbar 四段导航）与决策条目；交付后删除 `temp/assets-stats-redesign.html`。
- **Acceptance Criteria**：Project.md 描述与代码一致；temp/ 无本轮残留
