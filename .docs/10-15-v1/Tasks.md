# Tasks：初始金额隐藏、设置页重构与记账中文输入修复

**关联 Plan**：`Plan.md`
**Demo**：`temp/settings-redesign.html`（结构与交互基准，左下角悬浮条切换主题/加载态/空态）
**总计 Task**：14 个；全部由主线执行

---

## Phase 1：初始金额展示收敛

### TASK-01：设置页渠道行移除初始金额副文案
- **Status**：DONE
- **Executor**：主线
- **Description**：`web/src/pages/SettingsPage.tsx` 的 `channelRow` 只读态中，资产行不渲染副文案行；负债行副文案改为 `额度 ¥X`（credit_limit>0）或 `不设额度`。
- **Acceptance Criteria**：
  - 文件内不再出现模板串 `初始余额 ${formatMoney` 与 `初始欠款 ${formatMoney`
  - 编辑表单仍可修改初始余额/初始欠款

### TASK-02：统计页渠道明细移除初始金额
- **Status**：DONE
- **Executor**：主线
- **Description**：`web/src/pages/StatsPage.tsx` 资产行 `subLeft` 置为 `null`（保留「占资产 X%」）；负债行 `credit_limit === 0` 时 `subRight` 置为 `null`（保留 subLeft「不设额度上限」）。`ChannelRow` 的 `subLeft/subRight` 已是 `ReactNode`（含 `null`），不做类型改动，也不加「两者皆空不渲染」分支。
- **Acceptance Criteria**：grep `initial_balance|initial_debt` 在 StatsPage.tsx 无命中；`npm run lint` 通过

---

## Phase 2：记账弹窗中文输入修复

根因：`RecordModal` 初始化 effect 依赖 `[isOpen, initialTransaction, categories, paymentMethods]`。弹窗打开期间父组件任一次 `setCategories/setPaymentMethods`（登录后 `fetchConfigData`、设置操作回刷）都会重跑 effect：清空描述、重置类型，并在 50ms 后把焦点抢回 `inputMode="decimal"` 的金额框，打断输入法组合，表现为描述框打不出中文。

### TASK-03：初始化与自动聚焦收敛为「打开」转换
- **Status**：DONE
- **Executor**：主线
- **Description**：`web/src/components/RecordModal.tsx`
  - 现有初始化 effect 依赖改为 `[isOpen, initialTransaction]`，内部逻辑不变（读取当次渲染的 categories/paymentMethods）；聚焦 setTimeout 仅留在此 effect 中，并在 cleanup 中 clearTimeout
  - 新增一个补默认值 effect，依赖 `[isOpen, categories, paymentMethods]`：仅当 `isOpen && !initialTransaction` 且 `categoryId === 0` 时按当前 recordType 回填默认分类/标签，`paymentMethodId === 0` 时回填首个渠道；不触碰 description、amountStr、焦点
- **Acceptance Criteria**：
  - 初始化 effect 依赖数组中不含 categories/paymentMethods
  - 补默认值 effect 中不出现 `setDescription`、`setAmountStr`、`focus(`
  - 新建账单打开时金额框仍自动聚焦；配置晚于弹窗加载时分类与渠道被自动选中

### TASK-04：移动端输入字号
- **Status**：DONE
- **Executor**：主线
- **Description**：
  - `RecordModal.tsx` 与 `SettingsPage.tsx` 的 `INPUT_CLASS` 字号改为 `text-[16px] min-[640px]:text-[13.5px]`（SettingsPage 原为 `text-xs`，桌面端改为 `min-[640px]:text-xs`），防止 iOS 聚焦缩放打断键盘切换
- **Acceptance Criteria**：两处 INPUT_CLASS 含 `text-[16px]`；`npm run lint` 通过；交付消息请用户在真机验证中文输入

---

## Phase 3：设置页重构（对齐 Demo）

### TASK-05：新增「更多」图标
- **Status**：DONE
- **Executor**：主线
- **Description**：`web/src/components/Icons.tsx` 新增 `MoreHorizontalIcon`（三个实心圆点，viewBox 24，r=1.8，与 Demo 一致）
- **Acceptance Criteria**：导出存在且被 TASK-06 消费

### TASK-06：新增受控溢出菜单原子 OverflowMenu
- **Status**：DONE
- **Executor**：主线
- **Description**：`web/src/components/primitives.tsx` 新增 `OverflowMenu`
  - Props：`label: string; open: boolean; onOpenChange: (open: boolean) => void; items: ({ label: string; onSelect: () => void; disabled?: boolean; tone?: 'danger' } | 'divider')[]`
  - 触发器：32px 图标按钮，`aria-label="${label} 更多操作"`、`aria-haspopup="menu"`、`aria-expanded`
  - 菜单：外层 `relative` 包裹，菜单 `absolute right-0 top-full mt-1 z-[50]`，`role="menu"`，项 `role="menuitem"`；材质 `bg-[var(--surface)] border-[var(--line)] rounded-[var(--r-md)] shadow-[var(--e4)] animate-pop`；danger 项用 `--expense-text/--expense-soft`
  - 打开时监听 document `pointerdown`：以包裹层 ref（触发器 + 菜单）为界，落在包裹层外才 `onOpenChange(false)`；触发器自身的开关只由 `onClick` 经 `onOpenChange` 切换，避免 pointerdown 先关、onClick 再开的抖动；选中项先关闭再执行 onSelect；打开时聚焦首个可用项
  - Escape 不在原子内处理（由宿主 Esc 仲裁链统一处理）
  - 定位上限写 `ponytail:` 注释：不做视口翻转、不引 Portal；菜单在滚动容器（如抽屉主体 `overflow-y-auto`）内随滚动区外扩，末行需滚动可见
- **Acceptance Criteria**：组件导出；不使用十六进制/rgba 字面量；`npm run lint` 通过

### TASK-07：分类面板重构
- **Status**：DONE
- **Executor**：主线
- **Description**：`SettingsPage.tsx` 分类分区
  - 删除 PanelCard 标题行，面板头改为：左侧 `SegmentedControl`（支出 / 收入，小号）+ 右侧 `Button subtle sm`「新建分类」（保留 `PlusIcon`，对齐 Demo `.ph`）
  - 行结构：整行主体为 `<button>`（点击 `openDrawer`），两行文本：分类名（13.5px/600）+ 标签预览（`tags.map(t=>t.name).join(' · ')`，无标签显示「暂无细分标签」，12px fg-3，单行省略）；行尾标签数（12px muted，num）+ `OverflowMenu`：重命名 / 上移（首行 disabled）/ 下移（末行 disabled）/ divider / 删除
  - 行间发丝线 + hover 背景 `--surface-hover`、圆角 10px（参照 Demo `.row`）
  - 删除行内 `Chip`「N 个细分标签」、四个常驻 IconButton 与「管理标签」按钮
  - 新建分类、重命名沿用现有内联表单与校验逻辑，不改契约
  - 空态文案：标题「暂无支出分类/暂无收入分类」，副标题「新建后即可在记账时选择」，动作「新建分类」
- **Acceptance Criteria**：分类行内无 `ChevronUpIcon/ChevronDownIcon` 常驻按钮；调序、重命名、删除经菜单可达且行为与改前一致

### TASK-08：系统分类独立面板
- **Status**：DONE
- **Executor**：主线
- **Description**：系统分类从分类面板底部移出，作为下方独立 Panel「系统分类」；行结构同 TASK-07 但无菜单，行尾为锁形图标 +「系统」小字与 ChevronRight；点击打开只读抽屉
- **Acceptance Criteria**：移除「系统内置」「N 个内置标签」两枚 Chip；面板仅在存在系统分类时渲染

### TASK-09：渠道分区改为双面板 + 渠道对话框
- **Status**：DONE
- **Executor**：主线
- **Description**：
  - 资产 / 负债两个 Panel 在 ≥720px 并排（`grid min-[720px]:grid-cols-2 gap-4`），各自内部单列列表；面板头：标题 + 数量 + `Button subtle sm`「添加」（保留 `PlusIcon`，对齐 Demo）
  - 行：色点 + 名称 + （负债）额度副文案（TASK-01）+ `OverflowMenu`：编辑 / divider / 删除
  - 空态对齐 Demo：标题「暂无资产渠道 / 暂无负债渠道」，副标题「用于记录支出与收入 / 用于记录还款与额度」，动作「添加资产渠道 / 添加负债渠道」
  - 删除 `showAddAssetInput/showAddLiabilityInput/editingPm*` 等内联表单状态与 JSX，改为单一 `channelDialog: { mode: 'create'; type } | { mode: 'edit'; pm } | null`；同步删除失效的 `handleCreateAssetChannel` / `handleCreateLiabilityChannel` / `handleStartEditPm` / `handleSavePmEdit`（否则 tsc noUnusedLocals 报 TS6133）
  - 同文件内新增本地组件 `ChannelDialog`：`createPortal` 至 body，外壳样式与 `ConfirmDialog` 同构（overlay + `--e4` + `animate-pop`，`role="dialog" aria-modal aria-labelledby`），层级 `z-[1100]`（高于页面内容，低于 `ConfirmDialog` 的 `z-[1200]`）；字段：名称（必填，自动聚焦）、初始余额/初始欠款（`inputMode="decimal"`，¥ 前缀）、负债额外授信额度（placeholder「不设额度」）；表单 `<label htmlFor>` 关联
  - 校验：名称为空、重名、负数时在对应字段下方显示内联错误（`--expense-text` 12px）并置红边框，不发请求；提交中按钮「保存中…」并禁用；失败保持对话框与输入（错误 Toast 由 App 既有逻辑提供）；成功关闭
  - 遮罩点击与关闭按钮等同取消
- **Acceptance Criteria**：SettingsPage 内不再存在 `showAddAssetInput`、`editingPmId`；新建/编辑/删除资产与负债渠道全流程可用；`type="number"` 输入在本文件内清零

### TASK-10：细分标签抽屉去噪
- **Status**：DONE
- **Executor**：主线
- **Description**：
  - 删除系统分类说明横幅（「系统分类标签由底层调度引擎固定保护，不可增删改」），改为头部分类名旁锁形图标 +「系统」
  - 头部标题由「X · 细分标签」改为分类名 + 数量 Chip；删除底部「完成」页脚
  - 标签行：重命名 / 删除收进 `OverflowMenu`；系统标签行不渲染菜单，删除「系统固定」Chip
  - 输入框 placeholder 改为「新标签名称」；保留同步锁、失败保留草稿、焦点恢复等既有行为
  - 标签行菜单沿用 TASK-06 的定位上限（抽屉主体 `overflow-y-auto`，末行菜单随滚动区外扩、需滚动可见），不引 Portal
  - 收敛 `SettingsPage.tsx` import 至实际使用集：移除 `ChevronUpIcon`/`ChevronDownIcon`/`EditIcon`/`TrashIcon`（`PlusIcon` 保留给「新建分类 / 添加」按钮）
- **Acceptance Criteria**：抽屉内无「底层调度引擎」「完成」文案；系统分类打开时焦点落在关闭按钮（既有逻辑不回归）

### TASK-11：配置加载骨架
- **Status**：DONE
- **Executor**：主线
- **Description**：`App.tsx` 新增 `configLoaded` 状态，`fetchConfigData` 首次 settle（finally）后置 true，登出不重置；向 SettingsPage 传 `loading={!configLoaded}`；SettingsPage 在 loading 时各面板列表区渲染 4 行 `Skeleton`（名称 30% + 副文案 55%），不渲染空态
- **Acceptance Criteria**：首次进入设置页不再闪现空态；`npm run lint` 通过

### TASK-12：Esc 分层仲裁链更新
- **Status**：DONE
- **Executor**：主线
- **Description**：SettingsPage 新增单一 `openMenu: string | null`（键如 `cat-3`/`pm-5`/`tag-9`），所有 OverflowMenu 由它受控；切换分区/分段、打开抽屉或对话框时置 null。Esc 顺序：pendingDelete（让给 ConfirmDialog）→ channelDialog 关闭 → openMenu 关闭 → 抽屉内重命名 → 抽屉 → 分类重命名 → 新建分类输入
- **Acceptance Criteria**：每次 Esc 只关闭最上层一项；effect 依赖数组同步新增 `channelDialog`/`openMenu`，并移除已删除的内联表单状态（`showAddAssetInput`/`showAddLiabilityInput`/`editingPm*`）

---

## Phase 4：验证与文档

### TASK-13：回归验证
- **Status**：DONE
- **Executor**：主线
- **Description**：
  - `make test`（go test + tsc + node:test）
  - `cd web && npx vite build --outDir /tmp/ledger-dist-check --emptyOutDir` 验证打包后删除 `/tmp/ledger-dist-check`
  - grep 检查：`web/src` 中 SettingsPage/StatsPage 无 `#[0-9a-fA-F]{3,6}\b`、`rgba(` 字面量
  - 若 9222 浏览器实例可用，375px 与 1280px 视口各走查一次设置页与记账弹窗；不可用则在报告中注明
- **Acceptance Criteria**：命令全部 exit 0（tsc noUnusedLocals 无 TS6133，即 SettingsPage 无失效 import / 死 handler）；测试结论写入 Plan.md

### TASK-14：文档、归档与提交
- **Status**：DONE
- **Executor**：主线
- **Description**：
  - 更新 `.docs/Project.md`：结构树 SettingsPage/primitives(OverflowMenu)/Icons 描述、temp/ 说明（`redesign-demo.html` 已由用户删除，改为当前 Demo 或删除该行）、新增本阶段决策条目（初始金额仅作校准不展示；设置页列表行 + 溢出菜单 + 渠道对话框；RecordModal 初始化仅在打开转换执行）
  - 删除 `temp/settings-redesign.html`
  - Plan.md / Tasks.md 标注 DONE 与回归结论，归档至 `.docs/<执行当日 MM-DD>-vN/`（当日无同名目录取 v1，否则取当日最大 N 加 1）
  - 提交仅暂存本阶段文件（不包含 .pi 删除、.agents/.codebuddy/.dsh/AGENTS.md 改动、temp 截图），提交信息 `feat(web): ...` + 中文描述
- **Acceptance Criteria**：根目录无 Plan.md/Tasks.md；`git show --stat HEAD` 仅含本阶段文件
