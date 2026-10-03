# Tasks：前端美学缺陷修复与设计体系对齐

**关联 Plan**：`Plan.md` —— 前端美学缺陷修复与设计体系对齐 v1.0  
**状态**：DONE  
**日期**：2026-10-03  
**回归测试结论**：全量测试通过（Go 11 个测试 PASS，前端构建与类型检查 0 错误）  
**总计 Task**：11 个

---

## Phase 1：视觉令牌暗色适配与物理材质层级重塑

### TASK-001：在 index.css 的 .dark-mode 块中补齐品牌色高亮与边框令牌

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/index.css` 的 `.dark-mode` 选择器中添加 `--color-brand-light` 与 `--color-brand-stroke` 变量定义。
- **Details**：
  - 针对 `web/src/index.css`，在 `.dark-mode` 规则内添加：
    - `--color-brand-light: rgba(0, 120, 212, 0.16);`
    - `--color-brand-stroke: rgba(71, 158, 245, 0.4);`
  - 与现存的 `--color-expense-stroke` / `--color-income-stroke` 透明度定义风格统一。
- **Acceptance Criteria**：
  - `index.css` 语法正确
  - 暗黑模式下变量 `--color-brand-light` 解析为 `rgba(0, 120, 212, 0.16)`，不再回退到浅色 `#eff6fc`
  - 暗黑模式下变量 `--color-brand-stroke` 解析为 `rgba(71, 158, 245, 0.4)`

### TASK-002：重构还款滑块与还款标签以使用品牌色变量令牌

- **Status**：DONE
- **Executor**：主线
- **Description**：替换 `RecordModal.tsx` 与 `StreamPage.tsx` 中的硬编码 rgba 颜色，使用 `--color-brand-light` 与 `--color-brand-stroke` 统一驱动。
- **Details**：
  - `web/src/components/RecordModal.tsx` 第 309 行：将 `bg-[rgba(0,120,212,0.12)] border border-[rgba(0,120,212,0.35)]` 替换为 `bg-[var(--color-brand-light)] border border-[var(--color-brand-stroke)]`
  - `web/src/pages/StreamPage.tsx` 第 168 行：将 `bg-[rgba(0,120,212,0.08)] text-[var(--color-brand)] border border-[rgba(0,120,212,0.2)]` 替换为 `bg-[var(--color-brand-light)] text-[var(--color-brand)] border border-[var(--color-brand-stroke)]`
- **Acceptance Criteria**：
  - 两个文件内不再包含背景或边框类（bg-/border-）品牌色 rgba 硬编码字面量
  - 还款滑块在支出/收入/还款平滑切换时正常渲染
  - 深色模式下还款滑块和标签呈现柔和半透明深蓝背景

### TASK-003：升级 Navbar 顶栏与 BottomBar 底部胶囊物理材质

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `Navbar.tsx` 与 `BottomBar.tsx` 注入 `backdrop-blur-md` 与半透明卡片背景，建立 Layer 2 物理材质层级。
- **Details**：
  - `web/src/components/Navbar.tsx`：将 header 类名 `bg-[var(--color-card-bg)]` 调整为 `backdrop-blur-md bg-[var(--color-card-bg)]/85`
  - `web/src/components/BottomBar.tsx`：将底部筛选胶囊类名 `bg-[var(--color-card-bg)]` 调整为 `backdrop-blur-md bg-[var(--color-card-bg)]/85`
- **Acceptance Criteria**：
  - 页面滚动时，底层卡片内容经过顶栏下方呈现高斯模糊毛玻璃穿透效果
  - 底部筛选胶囊悬浮呈现通透毛玻璃质感，边框清晰

---

## Phase 2：排版去噪、状态映射与细节缺陷修复

### TASK-004：实现负债渠道额度使用率双档语义色彩映射

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/pages/StatsPage.tsx` 中，根据渠道信用额度使用率 `usage_rate` 分档控制进度条背景色彩。
- **Details**：
  - 修改 `web/src/pages/StatsPage.tsx` 第 209 行进度条内部指示器：
    - 当 `lc.usage_rate >= 80` 时使用 `bg-[var(--color-expense-dark)]`
    - 当 `lc.usage_rate < 80` 时使用 `bg-[var(--color-neutral-fg-subtle)]`
- **Acceptance Criteria**：
  - 使用率低于 80% 的负债渠道，进度条展示为中性灰阶
  - 使用率达到或超过 80% 的负债渠道，进度条高亮赤字警示红
  - 进度条平滑过渡动画正常

### TASK-005：修复储蓄率徽章内边距笔误并移除收支 KPI 卡片废话副标题

- **Status**：DONE
- **Executor**：主线
- **Description**：修正 `StatsPage.tsx` 储蓄率徽章内边距为 `py-0.5`，并移除收支统计卡片上的冗余副标题说明。
- **Details**：
  - 修正 `web/src/pages/StatsPage.tsx` 第 118 行储蓄率徽章类名 `py-0.2` 为 `py-0.5`
  - 删除第 83 行 `<span className="text-[11px] text-[var(--color-neutral-fg-subtle)]">自然周统计</span>`
  - 删除第 92 行 `<span className="text-[11px] text-[var(--color-neutral-fg-subtle)]">当月累计支出</span>`
  - 删除第 101 行 `<span className="text-[11px] text-[var(--color-neutral-fg-subtle)]">上一自然月全量</span>`
- **Acceptance Criteria**：
  - 储蓄率徽章上下内边距正常（从 0.8px 扩大到 2px）
  - 4 联收支 KPI 卡片与顶部 3 联宏观卡片排版结构对齐，无多余副标题文本

### TASK-006：收敛半档碎片字号并将 BottomBar 筛选项重构为局部 map 遍历

- **Status**：DONE
- **Executor**：主线
- **Description**：规范收敛半档字号，并使用局部数组配置重构 `BottomBar.tsx` 中的 4 个重复按钮。
- **Details**：
  - `web/src/components/Navbar.tsx`：将胶囊按钮文字类名 `text-[12.5px] sm:text-[13.5px]` 调整为 `text-xs sm:text-sm`，登出按钮 `text-[12.5px] sm:text-[13px]` 调整为 `text-xs`
  - `web/src/pages/StreamPage.tsx`：将第 162 行 `text-[14px]` 调整为 `text-sm`，第 197 行 `text-[15px] sm:text-[16px]` 调整为 `text-sm sm:text-base`
  - `web/src/components/Toast.tsx`：将第 22 行提示框类名 `text-[13.5px]` 调整为 `text-sm`
  - `web/src/components/BottomBar.tsx`：提取 `FILTER_OPTIONS` 静态常量数组，通过 `.map()` 渲染 4 个筛选选项按钮，消除重复的平铺模板代码
- **Acceptance Criteria**：
  - 全站无 `text-[12.5px]`、`text-[13.5px]`、`text-[14px]` 半档字号
  - 移动端 320px 视口下 Navbar 与 BottomBar 单行不折行
  - BottomBar 4 档筛选行为与原功能一致

### TASK-007：清理 index.html 残留类名与 Icons.tsx 未引用图标

- **Status**：DONE
- **Executor**：主线
- **Description**：移除 `web/index.html` body 上被覆盖的类名，并从 `web/src/components/Icons.tsx` 中移除零引用的 `ChevronRightIcon`。
- **Details**：
  - 在 `web/index.html` 第 8 行移除 `class="bg-neutral-50 text-neutral-900 antialiased"`
  - 在 `web/src/components/Icons.tsx` 中删除 `ChevronRightIcon` 函数定义（第 123-129 行）
- **Acceptance Criteria**：
  - `index.html` 内无残留的死类名
  - `Icons.tsx` 中无未引用图标导出
  - 项目编译通过

---

## Phase 3：触达可达性与动效补全

### TASK-008：扩大 StreamPage 移动端编辑与删除按钮触控尺寸

- **Status**：DONE
- **Executor**：主线
- **Description**：将移动端流水列表项的编辑与删除按钮触控尺寸调整为 32x32px。
- **Details**：
  - 修改 `web/src/pages/StreamPage.tsx` 第 213 行与第 221 行：
    将按钮尺寸类名从 `w-7 h-7` 调整为 `w-8 h-8 sm:w-7 sm:h-7`
- **Acceptance Criteria**：
  - 移动端视口下，编辑与删除按钮尺寸为 32px x 32px
  - 桌面端视口下，编辑与删除按钮维持 28px x 28px
  - 按钮内部 SVG 图标居中对齐

### TASK-009：为核心交互控件添加键盘焦点指示（focus-visible）

- **Status**：DONE
- **Executor**：主线
- **Description**：为 `Navbar.tsx` 导航胶囊、`BottomBar.tsx` 筛选按钮及记账 FAB 注入 `focus-visible` 焦点态样式。
- **Details**：
  - `Navbar.tsx` 3 个导航胶囊按钮：添加 `focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-brand)]`
  - `BottomBar.tsx` 筛选按钮：添加 `focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-brand)]`
  - `BottomBar.tsx` FAB 按钮：添加 `focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-[var(--color-brand)]`
- **Acceptance Criteria**：
  - 键盘 Tab 键聚焦到导航项、筛选按钮及 FAB 时，显示清晰的高对比度外环
  - 鼠标点击交互时不触发外环（仅键盘焦点有效）

### TASK-010：在 index.css 中定义滑入动效并赋予 SettingsPage 细分标签抽屉面板

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/index.css` 增加 `@keyframes slideInRight` 动画规则，并在 `SettingsPage.tsx` 抽屉面板应用该动画。
- **Details**：
  - `web/src/index.css` 中添加：
    ```css
    @keyframes slideInRight {
      from { transform: translateX(100%); }
      to { transform: translateX(0); }
    }
    .animate-slide-in-right {
      animation: slideInRight 0.22s cubic-bezier(0.16, 1, 0.3, 1);
    }
    ```
  - `web/src/pages/SettingsPage.tsx` 第 919 行抽屉面板容器类名中追加 `animate-slide-in-right`
- **Acceptance Criteria**：
  - 点击分类“管理细分标签”呼出抽屉时，抽屉面板从右侧平滑滑入
  - 关闭抽屉时状态重置无残留

---

## Phase 4：全流程编译验证与设计规范文档校准

### TASK-011：执行全量测试并更新 Project.md 设计体系定性描述

- **Status**：DONE
- **Executor**：主线
- **Description**：执行 `make test` 与 `npm run build`，并在 `.docs/Project.md` 中修正设计规范宣称，记录本次审美重塑决策。
- **Details**：
  - 运行 `make test`（Go 测试 + TypeScript lint）与前端打包
  - 更新 `.docs/Project.md`：
    - 将第 111 行原“严格遵循 Microsoft Fluent 2 视觉规范”纠偏为“采用 Fluent 品牌蓝与 Tailwind Slate 精细灰阶混合体系（Fluent-Slate Hybrid）”
    - 在约束与决策中追加记录本次暗色令牌补齐、Layer 2 毛玻璃物理材质、额度使用率双档映射与界面去噪的改动记录
- **Acceptance Criteria**：
  - `make test` 通过，0 错误
  - `cd web && npm run build` 成功无告警
  - `Project.md` 表述与实际代码实现保持 100% 一致性
