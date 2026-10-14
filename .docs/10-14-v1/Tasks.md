# Tasks：Web 前端成品级 UI/UX 重构

**关联 Plan**：`Plan.md` —— Web 前端成品级 UI/UX 重构 v1.0
**状态**：DONE（2026-10-14，回归测试结论见 Plan.md 头部）
**视觉基准**：`temp/redesign-demo.html`（静态原型，浏览器直接打开）
**执行主体**：全流程主线（不委托 Subagent，理由见 Plan §4）
**总计 Task**：17 个

## 全局约束（所有 Task 适用）

1. **执行主体**：Phase 1 → 5 全部由主线按序完成。不启动并行隔离会话，避免视觉语言漂移与工作区竞争。
2. **令牌唯一来源**：所有颜色、半径、阴影、时长、曲线必须取自 Phase 1 落盘的 CSS 变量。禁止在 JSX 中出现就地颜色字面量、就地圆角像素、就地阴影字符串、就地过渡时长。
3. **样式组织规范（桥接 Tailwind v4 与原型）**：
   - `index.css` 只承载：令牌定义、body 基础样式、`.num` 与焦点环等全局工具类、以及少量全局关键帧（`rise` / `pop` / `fade` / `slide` / `toastIn` / `pulse`）
   - 组件样式一律以 Tailwind utility 写在 JSX 内，令牌通过任意值语法消费（`bg-[var(--surface)]`、`rounded-[var(--r-md)]`、`transition-transform duration-[var(--d2)]`）
   - 原型中的 `.seg` / `.panel` / `.row` / `.chan` / `.amtbox` 等手写类名**不落盘**，仅作为视觉基准对照
   - 禁止在组件内使用 `@apply`，禁止新增组件级 CSS 类与并行样式文件
4. **数据边界**：任何呈现的数值必须由现有契约派生（`StatsSummary` 已有字段及其四则运算、`Transaction` 列表的本地聚合）。**禁止虚构**需要历史快照或未被返回的字段（净资产月环比、周期交易笔数等）。所有比率必须处理分母为 0，输出占位而非 `NaN`。
5. **不改业务契约**：不修改 `web/src/lib/api.ts` 的接口与类型；`streamUtils.ts` 的既有导出签名与返回结构保持不变（`web/test/stream.test.ts` 必须持续通过）。
6. **四个必答状态**：每个数据视图都要实现加载骨架、空态、错误提示、正常态。
7. **动效只碰 `transform` 与 `opacity`**，并在 `prefers-reduced-motion` 下退化为瞬变（Phase 1 全局兜底，构件层不得绕过）。

---

## Phase 1：设计令牌与基础构件层

### TASK-001：重写 index.css 为四层材质令牌体系

- **Status**：DONE
- **Executor**：主线
- **Description**：重写 `web/src/index.css`，以 Fluent 2 为基准建立完整令牌层，替换现有 `--color-*` 命名；保留 `body.dark-mode` 类名钩子（App.tsx 现有逻辑不变）。
- **Details**：
  - **层级面**：`--canvas`、`--canvas-glow`（radial 渐变材质）、`--surface`、`--surface-raised`、`--surface-sunken`、`--surface-hover`、`--glass`
  - **线条**：`--line`、`--line-strong`、`--highlight-top`（暗色 `rgba(255,255,255,.06)`，浅色 `transparent`）
  - **前景四级**：`--fg`、`--fg-2`、`--fg-3`、`--fg-muted`
  - **品牌**：`--brand`（`#0078D4`）、`--brand-hover`、`--brand-pressed`、`--brand-text`（浅色下取深色以保证正文对比度）、`--brand-soft`、`--brand-line`；暗色下抬升至 `#479EF5`
  - **语义四组**（每组 4 个令牌：`-`（图形）/`-text`（文本）/`-soft`（淡底）/`-line`（描边））：`--expense`、`--income`、`--transfer`、`--repay`
  - **半径刻度**：`--r-xs:6px`、`--r-sm:8px`、`--r-md:12px`、`--r-lg:16px`、`--r-xl:20px`、`--r-pill:999px`
  - **深度**：`--e1`…`--e4`（浅色多层柔和投影；暗色更重投影 + `--highlight-top` 顶部内高光）
  - **动效**：`--ease-out: cubic-bezier(.22,1,.36,1)`、`--ease-std: cubic-bezier(.2,0,0,1)`、`--ease-spring: cubic-bezier(.16,1,.3,1)`；`--d1:120ms`、`--d2:180ms`、`--d3:260ms`
  - **排版**：`--font` 字栈前部保留 Segoe UI，随后 PingFang SC / HarmonyOS Sans SC / 微软雅黑；`.num` 类统一 `tabular-nums` + `-.02em` 字距
  - 全局工具类与关键帧：`.num`、`:focus-visible` 焦点环、`::selection`、滚动条、`color-scheme`，以及 `rise` / `pop` / `fade` / `slide` / `toastIn` / `pulse` 六个关键帧及其对应类
  - 保留 `@media (prefers-reduced-motion: reduce)` 的全局退化
- **Acceptance Criteria**：
  - 深浅两套主题下，上列令牌**成对且完备**（`grep` 每个令牌在 `:root` 与 `.dark-mode` 中均有定义）
  - 视觉对照 `temp/redesign-demo.html` 的十六进制取值一致
  - 正文色对 canvas 对比度 ≥ 4.5:1；`--brand-text`、`--expense-text`、`--income-text` 对 `--surface` 对比度 ≥ 4.5:1
  - 开启 `prefers-reduced-motion` 后所有动画接近瞬变
  - 文件中不存在组件级样式类（无 `.panel` / `.row` 之类的原型类名残留）

---

### TASK-002：新增共享原子构件层

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/components/` 新增 `primitives.tsx`，以 Tailwind utility + 令牌任意值语法实现跨视图复用的原子构件。
- **Details**：导出并实现：
  - `Panel`——内容面容器（`variant: 'plain' | 'hero'`），统一 1px `--line` + `--e1` + 顶部内高光；`hero` 变体改用 `--brand-line` 描边 + `--e3`
  - `IconButton`——34px 方形图标按钮，`tone: 'neutral' | 'danger'`，必填 `aria-label`，hover 底色 + `active:scale(.94)`
  - `Button`——`variant: 'primary' | 'subtle' | 'ghost' | 'danger'`，`size: 'sm' | 'md' | 'lg'`，按压 `scale(.97)`
  - `SegmentedControl`——通用分段控件，`items` 任意数量，指示器使用共享位置 `translateX` 位移（非淡入淡出），支持 `compact` 变体在窄屏隐藏文字
  - `Chip` / `Badge`——`tone: 'neutral' | 'brand'`
  - `Amount`——数值文本，`tone` 取自交易类型语义，`size: 'hero' | 'lg' | 'md' | 'sm'`，数字走 `.num`
  - `TypeTile`——32px 语义图标瓦片，按交易类型映射 `--soft` 底 + `--text` 色 + 对应图标
  - `Rail`——4px 比例导轨，`value` 百分比自动钳制在 0–100
  - `Skeleton` / `SkeletonList`——脉冲占位，尺寸须与真实结构一致
  - `EmptyState`——图标圆底盘 + 标题 + 副标题 + 行动按钮（`action?: { label: string; onClick: () => void }`）
  - `ConfirmDialog`——契约如下：

    ```ts
    interface ConfirmDialogProps {
      open: boolean;
      title: string;
      description?: string;      // 主说明
      detail?: string;           // 被操作对象摘要，如「午餐 · −¥38.50」
      confirmLabel?: string;     // 默认「确认」
      cancelLabel?: string;      // 默认「取消」
      tone?: 'danger' | 'neutral';
      loading?: boolean;         // 确认中禁用按钮并切换文案由调用方控制
      onConfirm: () => void;
      onCancel: () => void;
    }
    ```

    `role="alertdialog"` + `aria-modal`；打开时焦点落在取消按钮；Esc 与遮罩点击均等同取消；确认按钮在 `loading` 下禁用
- **Acceptance Criteria**：
  - `npx tsc -b --noEmit` 通过，props 无 `any`
  - 全部视觉值来自 TASK-001 令牌；文件中无十六进制色值与像素圆角字面量
  - `ConfirmDialog` 可被账单删除（App 层）与设置页三类实体删除共用，调用方无需自建模态外壳
  - 三个视图调用同一构件时视觉表现完全一致

---

### TASK-003：收敛金额格式化至单一模块

- **Status**：DONE
- **Executor**：主线
- **Description**：新建 `web/src/lib/format.ts` 作为**唯一**格式化模块，并让 `web/src/pages/streamUtils.ts` 复用它，消除双重实现。
- **Details**：
  - `format.ts` 导出：`formatAmount`（签名与返回结构完全沿用现有实现，含 `FormattedAmount` 类型）、`formatMoney(value, opts?: { sign?: 'auto' | 'none' })`、`formatPercent(value)`、`resolveTone(type)`、`toLocalInputValue(iso)` / `fromLocalInputValue(str)`
  - `streamUtils.ts` 删除 `formatAmount` 的本地实现与 `FormattedAmount` 定义，改为再导出：

    ```ts
    export { formatAmount } from '../lib/format';
    export type { FormattedAmount } from '../lib/format';
    ```

    `getDayInfo`、`formatTime`、`buildMetaParts` 保留在原文件，签名与行为不变
  - 新建 `web/test/format.test.ts`，追加针对 `formatMoney` / `formatPercent` / `resolveTone` 的断言（≥4 条，含负数、千分位、未知类型回退）
- **Acceptance Criteria**：
  - `web/test/stream.test.ts` 全部用例**原样通过**，导入路径与断言一字未改
  - `web/test/format.test.ts` 全部通过
  - `grep -rn "function formatAmount" web/src` 只有 `lib/format.ts` 一处命中

---

### TASK-004：扩展 Icons.tsx 语义图标集

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/components/Icons.tsx` 补齐各视图所需图标，统一 `size` 与 `strokeWidth` 约定（2–2.4，圆头线帽）。
- **Details**：新增 `CheckIcon`、`AlertIcon`、`InfoIcon`、`ChevronRightIcon`、`WalletIcon`、`ArrowTrendIcon`；保留全部既有图标导出。所有图标沿用 `currentColor` 描边、24 viewBox。
- **Acceptance Criteria**：
  - 现有图标调用点零改动即可编译通过
  - 新图标默认尺寸与既有同类图标光学对齐
  - 无未被引用的死代码图标（交付前 grep 确认）

---

### TASK-005：更新 index.html 主题元信息与防闪脚本

- **Status**：DONE
- **Executor**：主线
- **Description**：修改 `web/index.html`，补充主题元信息与首屏防闪脚本。
- **Details**：`<meta name="color-scheme" content="light dark">`、深浅两值 `theme-color`、`<head>` 内联同步脚本读取 `localStorage.ledger_theme` 并提前落 `dark-mode` 类；补内联 SVG data URI favicon（品牌标记），杜绝 404 请求。
- **Acceptance Criteria**：
  - 深色偏好用户刷新首帧即为深色，无浅色闪帧
  - 控制台无资源 404

---

## Phase 2：应用外壳与全局反馈层

### TASK-006：重制 Navbar

- **Status**：DONE
- **Executor**：主线
- **Description**：重写 `web/src/components/Navbar.tsx`，使用 `SegmentedControl` 与 `--glass` 材质。
- **Details**：
  - 高度 60px，`sticky top-0`，`backdrop-blur-[18px]` + 1px `--line` 底边 + 顶部内高光
  - 品牌标记改为渐变圆角牌（参照原型）
  - 三个导航项走 `SegmentedControl`，`role="tablist"` / `aria-selected`，指示器 `translateX` 位移
  - 右侧操作簇：主题切换 `IconButton` + 桌面端 admin 胶囊 + 登出 `IconButton`（`tone="danger"`，移动端仅图标）
- **Acceptance Criteria**：
  - 320px 视口下顶栏不溢出、不换行
  - 键盘 Tab 可遍历全部控件，焦点环可见；当前视图 `aria-selected="true"`
  - 切换主题时顶栏与内容区同步，无局部残留旧色

---

### TASK-007：重制 BottomBar

- **Status**：DONE
- **Executor**：主线
- **Description**：重写 `web/src/components/BottomBar.tsx`，重做筛选胶囊与 FAB 的材质与间距。
- **Details**：
  - 胶囊：`--glass` + blur + `--e3`，内部 5 档 `aria-selected`，选中态 `--surface-sunken` 底
  - ≥640px 居中；<640px 左侧 12px 定位，单档内边距收紧，与 FAB 保留 ≥24px 安全距离
  - 非流水视图仅保留 FAB
  - FAB：52px 圆，品牌色投影 + 顶部 1px 内高光；hover `scale(1.05)`、active `scale(.94)`
- **Acceptance Criteria**：
  - 320/375/414px 三档视口下胶囊与 FAB 无重叠
  - FAB 具备 `aria-label="记账"` 并响应键盘激活

---

### TASK-008：重制 Toast

- **Status**：DONE
- **Executor**：主线
- **Description**：重写 `web/src/components/Toast.tsx` 为弹簧入场胶囊通知，补齐图标语义与堆叠顺序。
- **Details**：
  - 容器 `aria-live="polite"`；移动端底部居中（`bottom: 88px`）避开作业条，≥640px 右上；`pointer-events` 仅作用于通知本体
  - 单条：圆形语义图标（success/error/info）+ 标题 + 次要描述 + 关闭 `IconButton`
  - 入场 `translateY(12px) scale(.96)` → 静止，`--ease-spring` `--d3`；最近项在上
  - 关闭按钮点击即移除；自动计时移除沿用 App 层现有逻辑
- **Acceptance Criteria**：
  - 三类通知语义色可辨且对比度达标
  - 同时存在 3 条时不遮挡 FAB 与筛选胶囊

---

### TASK-009：重制 AuthModal

- **Status**：DONE
- **Executor**：主线
- **Description**：重写 `web/src/components/AuthModal.tsx`，作为产品的第一印象界面。
- **Details**：锁形图标置于圆角品牌淡底牌中；标题与副标题按原型节奏排布；输入框统一输入形态；加载态按钮禁用，错误态内联 `--expense-soft` 提示条；入场用 `pop` 关键帧。
- **Acceptance Criteria**：
  - 空密码提交给出内联错误，而非浏览器原生提示
  - 回车提交、输入框自动聚焦；登录失败后不关闭弹窗

---

### TASK-010：App.tsx 版面、转场与确认框接线

- **Status**：DONE
- **Executor**：主线
- **Description**：改写 `web/src/App.tsx` 的容器骨架与全局控件接线，替换 `window.confirm`。
- **Details**：
  - 根容器承载 `--canvas-glow` 材质；`main` 内容最大宽度 900px，纵向内边距按原型（移动端 24px 顶 / 120px 底）
  - 视图切换增加 180ms 上浮进入（`rise`），`key` 绑定当前视图以触发重挂载动画
  - 账单删除的确认状态宿主收敛在 App：`pendingDelete: { id: number; summary: string } | null`，单一 `ConfirmDialog` 实例消费；确认后执行 `api.deleteTransaction` 并刷新，**移除 `window.confirm` 调用**
  - 主题切换期间给 `body` 临时加 200ms 过渡类，避免瞬间跳变
- **Acceptance Criteria**：
  - 全项目检索 `window.confirm` 结果为零
  - 三个视图切换均有统一进入过渡，`prefers-reduced-motion` 下无位移
  - 已有数据加载、错误处理、快捷键 `N` 行为不变

---

## Phase 3：账目流水主画布重构

### TASK-011：重构 StreamPage 信息结构

- **Status**：DONE
- **Executor**：主线
- **Description**：重写 `web/src/pages/StreamPage.tsx`，建立「本月概览头条 + 日表层组」两级结构。
- **Details**：
  - **头条统计作用域（硬性约束）**：
    - 聚合范围 = `transactions` 中 `transacted_at` 落在**当前自然月**（本地时区）的全部记录；跨月数据一律不计入
    - 头条**不受底部筛选影响**（它表达的是「本月」，筛选只作用于下方列表）
    - 支出 = Σ|amount|（`type === 'expense'` 或 legacy 负 `amount_cents`），收入 = Σ amount（`type === 'income'`）；沿用现有隔离契约，严格排除 `transfer` 与 `repayment`
    - 比例导轨 = `expense / (expense + income)`；**分母为 0 时不渲染导轨**（而非渲染 0 宽元素）
    - 注：接口 `limit=100`，当月记录超过该上限时头条为可见部分的近似值，不为此新增请求
  - **头条版式**：无卡片外壳，直接落在画布；当月支出（22px 主数值）+ 收入 + 结余；右侧 132px 收支比例导轨
  - **日表层组**：`--surface` + `--r-md` + `--e1`；表头 `--surface-sunken` 底 + 底部发丝线，左侧日期主/次双段（复用 `getDayInfo`），右侧当日支出/收入小计（同样排除转账与还款）
  - **行**：36–40px 行高，`TypeTile` + 主标题 + 二级元信息（`buildMetaParts` 拼接，`·` 分隔符用 `--fg-muted`）+ 右对齐 `Amount`（复用 `formatAmount`）+ 行尾操作簇
  - 操作簇在 ≥640px 下悬停/聚焦显示（`opacity .55 → 1`），移动端常驻
  - 二级浮层改为右对齐 `--e3` 浮层，spring 入场，Esc 与外部点击关闭
  - 加载态用 `SkeletonList`（日组骨架，尺寸与真实结构一致）；空态用 `EmptyState` + 「记一笔」行动按钮
- **Acceptance Criteria**：
  - `web/test/stream.test.ts` 全部通过
  - 构造跨月数据（含上月记录）时，头条数值与当月实际值一致，不含历史月
  - 筛选为「转账」等单一类型时，头条不报错、导轨不出现 `NaN`
  - 320px 视口无横向滚动；超长描述与超长金额不破版
  - 空态、骨架、正常三态均能复现且切换无跳动

---

## Phase 4：统计看板重构

### TASK-012：重写 StatsPage 主视觉、指标行与渠道面板

- **Status**：DONE
- **Executor**：主线
- **Description**：重写 `web/src/pages/StatsPage.tsx`，把「等权 KPI 卡堆」替换为净资产主视觉 + 发丝分节指标行 + 分发行渠道面板。
- **Details**：
  - **数据边界（硬性约束）**：仅使用 `StatsSummary` 已有字段及其四则派生。**不得**呈现净资产月环比或周期交易笔数（后端无历史快照与计数）。
    - 资产负债率 = `total_liabilities / total_assets`，`total_assets === 0` 时不渲染该 chip
    - 渠道总数 = `asset_channels.length + liability_channels.length`
    - 当月花费环比 = `(month_expense - last_month_expense) / last_month_expense`，`last_month_expense === 0` 时不渲染该注脚
    - 储蓄率沿用 `savings_rate`
  - **Hero**：`Panel variant="hero"`；左侧「净资产」标签 + 40px 数值（移动端 34px）+ 上列可派生 chip；≥720px 右侧并列资产/负债双行与一条负债占资产比例导轨（钳制 0–100%）
  - **指标行**：本周花费 / 当月花费（含环比注脚）/ 上月花费 / 当月结余（含储蓄率注脚），置于单一面内以发丝线分格（<720px 两列两行，≥720px 四列）
  - **渠道双列面板**：每行色点 + 名称 + 右侧余额（负债用 `--expense-text`），下方 4px `Rail` 比例，再下 11.5px 副信息（初始余额/占比，或剩余可用/额度·使用率）；负债使用率 ≥80% 时余额、副信息与导轨同步切换语义色；无数据由 `EmptyState` 接管
  - 加载态用骨架屏；全部数值走 `Amount` / `formatMoney`
- **Acceptance Criteria**：
  - 首屏第一视觉落点为净资产，第二落点为指标行
  - 净资产为负时自动切换语义色且布局不塌陷
  - `total_assets === 0`、`last_month_expense === 0`、空渠道三种边界下无 `NaN`、无 `Infinity`、无空白塌陷
  - 指标行在 320/768/1440px 三档下分格线连续且不错位

---

### TASK-013：以自绘 SVG 新增图表组件

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/components/` 新增 `Charts.tsx`，实现 `DonutChart` 与 `TrendChart` 两个纯 SVG 组件，供 StatsPage 消费。
- **Details**：
  - `DonutChart`：品牌单色阶环形（`#0f6cbd → #bcdcfb` 五档递进，不使用彩虹色），`stroke-dasharray/offset` 分段，中心显示合计金额；图例（名称 / 金额 / 占比）可点击，选中项 `--brand-soft` 底 + `--brand-line` 描边
  - 选中某分类时在同一面板内展开该分类的细分标签 chips（金额 + 占比），再点收起；选中态 `aria-pressed`
  - `TrendChart`：`viewBox` 响应式宽（**禁止固定像素宽**），支出为实线 + 渐变面积，收入为实线，末月数据点放大强调；网格线走 `--line`，月份标签 `--fg-3`
  - 两个组件均需处理空数组、单元素数组与全零值（不出现负高、断线或除零）
- **Acceptance Criteria**：
  - 无第三方图表依赖（依赖清单与改动前一致）
  - 320px 视口下两图不溢出容器
  - 空数据、单月数据、全零数据三种输入均不报错且不塌陷
  - 图表具备 `role="img"` 与 `aria-label` 摘要

---

## Phase 5：记账表单与设置中心重构

### TASK-014：重制 RecordModal

- **Status**：DONE
- **Executor**：主线
- **Description**：重写 `web/src/components/RecordModal.tsx`，确立「金额是唯一主角」的表达。
- **Details**：
  - 四段类型滑块改用 `SegmentedControl`（图标 + 文字，≤400px 仅图标），指示器 `translateX` 位移；编辑态锁定并降低不透明度
  - 金额输入区：34px 字重 680 的输入、`¥` 前缀弱化、聚焦态切换边框与底色；转账时右上角保留 `+ 手续费` 内联展开
  - 其余字段统一输入形态与 `--line-strong` 边框，聚焦出现 3px `--brand-soft` 光晕
  - 分类选择保留内联渐进披露；转账/还款的系统锁定卡改为 `--surface-sunken` 底 + 锁图标 + 「系统固定」
  - 底部常驻操作栏：`ghost 取消` + `primary 保存`；错误态内联在滚动区底部
  - 日期字段改用 `toLocalInputValue` / `fromLocalInputValue`，删除文件内重复的手写日期拼接
  - 现有校验规则（金额、用途、渠道、双方互斥、手续费非负）全部保留
- **Acceptance Criteria**：
  - `max-h-[calc(100dvh-24px)]` 与常驻 Footer 行为不变：移动端键盘弹起时保存按钮永不被裁切
  - 四类记账形态切换时表单无抖动（指示器位移，无 reflow）
  - 既有校验全部可触发内联错误
  - 文件内无手写日期拼接残留（全部走 TASK-003 的日期工具）

---

### TASK-015：重制 SettingsPage 与标签抽屉

- **Status**：DONE
- **Executor**：主线
- **Description**：重写 `web/src/pages/SettingsPage.tsx`（含内联标签抽屉），收敛为「分类与标签 / 渠道与账户」双分区工作台。
- **Details**：
  - 页头：20px 标题 + 右侧 `SegmentedControl`（两档）
  - 分类区：支出/收入二级切换（计数显示）+ 发丝线列表；每行主标题 + 「N 个细分标签」副信息 + 标签入口 / 上移 / 下移 / 删除 `IconButton`；系统内置分类标注 `--brand-soft` 徽标并隐藏编辑删除入口
  - 渠道区：资产/负债双列，每行展示名称与初始余额（负债为额度与初始欠款），操作入口**常驻可见**（移除 `opacity-0 group-hover` 写法）
  - **确认弹窗状态宿主（硬性约束）**：SettingsPage 内部维护单一状态

    ```ts
    const [pendingDelete, setPendingDelete] =
      useState<{ kind: 'category' | 'channel' | 'tag'; id: number; name: string } | null>(null);
    ```

    分类、渠道、标签三类删除共用这一个状态与**一个** `ConfirmDialog` 实例；`onDelete*` 回调签名保持不变，仅在触发前设置 `pendingDelete`。**不在 SettingsPage 内新建第二套模态外壳**
  - 删除引用冲突（后端 409）时关闭弹窗并由 Toast 呈现服务端文案
  - **标签抽屉**：右侧滑入（`--d3` spring）面板，宽 `min(420px,100%)`，`--e4` 左侧投影 + `--highlight-top`；<640px 下沉为底部面板（上缘 16px 圆角，保留 12px 安全边距）；遮罩 `rgba(8,12,20,.44)` + `blur(4px)`，点击遮罩关闭；Esc 优先关闭重命名态，再关闭抽屉；打开时锁定背景滚动
- **Acceptance Criteria**：
  - 320px–1920px 视口下所有行操作入口可见可点
  - 三类删除共用同一确认弹窗，无重复模态逻辑；确认后正确调用对应回调
  - 删除已引用条目时展示可读冲突提示，后端交互不变
  - 抽屉打开时背景滚动锁定，关闭后恢复；移动端底部形态不被系统手势区裁切
  - 重命名失败时编辑态保留、可继续修改（现有 `try…catch` 兜底行为不变）

---

## 收尾

### TASK-016：全量构建、测试与跨界面走查

- **Status**：DONE
- **Executor**：主线
- **Description**：执行 `make test`（Go 集成测试 + 前端类型检查）与 `cd web && npm run build`，并对三视图走查整改。
- **Details**：
  - `grep` 旧令牌名（`--color-*`）、`window.confirm`、`function formatAmount` 确认零残留
  - 逐项比对 `temp/redesign-demo.html`：令牌取值、圆角刻度、阴影层级、间距节奏、动效时长
  - 深浅两套主题 × 三个视图 × 320/768/1440px 三档视口走查
  - 重点回归：跨月数据与单一类型筛选下的流水头条；`total_assets === 0` / `last_month_expense === 0` / 空渠道下的统计页
- **Acceptance Criteria**：
  - `make test` 全绿；`npm run build` 成功且产物体积无异常膨胀
  - 无 `any` 逃逸、无未使用导出
  - 走查问题清单清零

---

### TASK-017：更新 Project.md、归档与提交

- **Status**：DONE
- **Executor**：主线
- **Description**：同步 `Project.md` 的前端描述与决策，完成归档并提交。
- **Details**：
  - 在 `Project.md`「结构」更新组件与页面文件的职责描述；在「约束与决策」追加本次视觉体系决策条目（令牌体系、构件层、自绘图表、确认对话框替换原生 `confirm`、四条语义色调、数据边界纪律）
  - Plan.md 与 Tasks.md 全部 Task 标记 DONE 后，按 Archive 流程移入 `.docs/<MM-DD-vN>/`
  - 按 Conventional Commits（英文类型前缀 + 中文详细描述）提交，排除密钥类敏感文件
- **Acceptance Criteria**：
  - `Project.md` 描述与实际代码一致，无过期条目
  - `.docs/<归档目录>/` 同时含 `Plan.md` 与 `Tasks.md`，根目录无残留
  - `git log` 显示语义清晰的提交，无密钥类文件入库
