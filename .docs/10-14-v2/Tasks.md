# Tasks：Review 审阅报告吸收修复（Fluent 2 重构残留问题）

**状态**：DONE（完成日期 2026-10-14）
**回归测试结论**：`npx tsc --noEmit` 通过；`npm test` 30/30 通过；`make test`（Go + 前端）全绿；`vite build` 成功且构建产物实测验证 `:focus-visible` 无 border-radius、`.num` 归入 `@layer components`；web/src 无十六进制色值/rgba 品牌光晕/rounded-[2px]/死导出/「点击右上角」残留。

**关联**：复审报告（.docs/10-14-v1 交付的只读审计）
**总计 Task**：17 个
**执行策略**：全部为主线执行（小差分、强依赖会话上下文，委托无正向收益）

---

## Phase 1：数据正确性与视觉回归

### TASK-001：头条统计与筛选解耦（H1）

- **Status**：DONE
- **Executor**：主线
- **Description**：App.tsx 的 fetchTransactions 并行追加 `api.getTransactions('all')` 存入新 state `monthTransactions`；StreamPage 新增 `monthTransactions` prop，`computeMonthHeadline` 只消费该源，列表继续消费筛选后的 `transactions`。
- **Acceptance Criteria**：选「转账/还款/支出」筛选时头条仍显示真实当月收支与比例导轨；tsc 通过。

### TASK-002：移除 ：focus-visible 强制圆角（M1）

- **Status**：DONE
- **Executor**：主线
- **Description**：index.css 删除 `:focus-visible` 内 `border-radius: 4px` 声明。
- **Acceptance Criteria**：构建产物中该规则不含 border-radius。

### TASK-003：.num 移入 @layer components（M2）

- **Status**：DONE
- **Executor**：主线
- **Description**：index.css 将 `.num` 规则包入 `@layer components`，使 tracking utility 可覆盖其字距。
- **Acceptance Criteria**：Amount hero/lg 的 `tracking-[-.028em]`/`[-.02em]` 生效于构建产物。

### TASK-004：补回「当月支付途径分布」面板（M3）

- **Status**：DONE
- **Executor**：主线
- **Description**：StatsPage 用现成 ChannelRow + Rail 消费 `stats.payment_distribution`，新增全宽 Panel 置于渠道双列与图表区之间；空态显示占位文案。
- **Acceptance Criteria**：面板渲染渠道名、金额、占比与导轨；与后端契约字段一致。

### TASK-005：品牌光晕/遮罩/环形图色板令牌化（L1 + L2 部分）

- **Status**：DONE
- **Executor**：主线
- **Description**：index.css :root 新增 `--overlay`、`--brand-glow`（暗色另设）、`--donut-1..5`、`--r-nano: 2px`；替换 4 处遮罩 rgba、3 处品牌光晕 rgba、Charts 色板 5 个 hex、Navbar 渐变第二停 `#0a5fb4` → `var(--brand-pressed)`（同时消灭死令牌）、5 处 rounded-[2px]/[2.5px] → `var(--r-nano)`。
- **Acceptance Criteria**：web/src 中不再出现上述 rgba/hex 字面量与 rounded-[2px]。

### TASK-006：删除零消费死令牌（L2）

- **Status**：DONE
- **Executor**：主线
- **Description**：index.css 删除 `--surface-raised`（深浅两处）、`--e2`（深浅两处）、`--transfer`、`--repay` 基色（深浅两处）。
- **Acceptance Criteria**：删除后 tsc 与构建通过，无 var() 悬空引用。

### TASK-007：死导出清理与 formatPercent 落地（L3）

- **Status**：DONE
- **Executor**：主线
- **Description**：删除 primitives.tsx `Badge` 别名、Icons.tsx `MoreVerticalIcon`；StatsPage（6 处）与 Charts（2 处）的 `.toFixed(1)%` 改用 `formatPercent`。
- **Acceptance Criteria**：grep 无 Badge/MoreVerticalIcon 引用；format.test.ts 继续通过。

---

## Phase 2：交互、可访问性与状态覆盖

### TASK-008：分段控件可访问名与禁用态（M4 + M6）

- **Status**：DONE
- **Executor**：主线
- **Description**：SegmentedControl 按钮在 label 为字符串时输出 `aria-label`；新增 `disabled?: boolean` prop 透传至按钮并附 disabled 样式；RecordModal 编辑态传 `disabled={!!initialTransaction}`；Icons.tsx 全部 svg 根元素加 `aria-hidden="true"`。
- **Acceptance Criteria**：<640px 顶栏与 <400px 类型滑块的每个按钮有非空可访问名；编辑态点击滑块无响应且按钮 disabled。

### TASK-009：RecordModal 表单标签关联（M5）

- **Status**：DONE
- **Executor**：主线
- **Description**：金额、用途说明、记账时间三处 label 加 htmlFor 并给 input 加 id；ChannelField 改为 span[id] + role="group" aria-labelledby（useId）。
- **Acceptance Criteria**：RecordModal 内所有文本/数字输入控件均有程序化关联标签。

### TASK-010：主模态 dialog 语义（L6）

- **Status**：DONE
- **Executor**：主线
- **Description**：RecordModal 与 AuthModal 内层卡片加 `role="dialog" aria-modal="true" aria-label`。焦点陷阱/归还本轮不做（已有首焦点落点，陷阱留待后续专项）。
- **Acceptance Criteria**：两模态在 DOM 中可被 dialog 语义查询到。

### TASK-011：ConfirmDialog 焦点仅在打开时夺取（L7）

- **Status**：DONE
- **Executor**：主线
- **Description**：primitives.tsx 将 focus 逻辑与 Esc 监听拆为两个 useEffect，focus 仅依赖 [open]。
- **Acceptance Criteria**：对话框保持打开期间内部状态变化不再触发 focus() 重置。

### TASK-012：320px 筛选胶囊与 FAB 防重叠（L9）

- **Status**：DONE
- **Executor**：主线
- **Description**：BottomBar 按钮在 <400px 采用 `px-2 text-xs`，≥400px 恢复 `px-2.5 text-[13px]`。
- **Acceptance Criteria**：按 CSS 取值推算胶囊右缘 ≤248px < FAB 左缘 252px。

### TASK-013：主题跟随应用而非系统（L8）

- **Status**：DONE
- **Executor**：主线
- **Description**：index.css :root `color-scheme: light`、.dark-mode `color-scheme: dark`，删除 index.html 中 meta color-scheme 与双 media theme-color，改单条 theme-color；App 主题 effect 与 index.html 防闪脚本同步 meta content。
- **Acceptance Criteria**：系统浅色 + 应用暗色时浏览器工具栏与原生控件呈暗色。

---

## Phase 3：结构与去噪

### TASK-014：表面材质收敛到 Panel（L4）

- **Status**：DONE
- **Executor**：主线
- **Description**：StreamPage 日表 section 与 SkeletonList 日组镜像改用/对齐 Panel（--r-lg）；SettingsPage PanelCard 内部改组合 Panel。
- **Acceptance Criteria**：surface+border+e1 阴影+圆角字符串全库仅存在于 primitives.Panel 一处。

### TASK-015：设置页空态去操作指引（L5）

- **Status**：DONE
- **Executor**：主线
- **Description**：分类/资产渠道/负债渠道三处「点击右上角…」替换为共享 EmptyState（带直接触发展开表单的 action 按钮）；抽屉内空态文案改为中性「暂无细分标签」。
- **Acceptance Criteria**：web/src 无「点击右上角」文案。

### TASK-016：过度设计接口面收敛

- **Status**：DONE
- **Executor**：主线
- **Description**：SettingsPageProps 的 onUpdatePaymentMethod/onReorderCategories 改必选并删除 `if (onUpdatePaymentMethod)` 与 `else Promise.all` 死分支；IconButton 删除 className prop；Rail 删除 color 默认值。驳回项：客户端 7 处重名预校验收敛（既有代码、改动风险大于收益）；Panel hero 变体（有真实调用方）。
- **Acceptance Criteria**：tsc 通过，死分支与死参数消失。

---

## Phase 4：验证与文档

### TASK-017：回归验证与文档维护

- **Status**：DONE
- **Executor**：主线
- **Description**：`npx tsc --noEmit`、`node --test`、`make test`；Project.md 同步（StatsPage 描述补支付途径分布、深度阴影档位更正、temp/ 归属声明、追加修复决策条目）。
- **Acceptance Criteria**：全部测试通过；Project.md 与代码一致。
