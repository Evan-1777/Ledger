# Plan：流水重构复审批判吸收与质量加固 (Quick)

**状态**：DONE  
**完成日期**：2026-10-04  
**模式**：Quick  
**回归测试结论**：`make test` 全部通过（Go 18 项测试全绿、前端 TypeScript 检查零错误、Node 原生自检 17 项全绿）；`make build` 成功编译单二进制可执行文件 `bin/ledger`。  

---

## 1. 复审意见批判性吸收分析

对照 10-04-v3 复审报告（78分）及工程纪律（`engineering-discipline`）、极简主义（Ponytail）：

| 复审问题 | 建议修法 | 批判吸收判定 | 处理决策与理由 |
|---|---|---|---|
| **1. Mica 画布材质不可见** | 将材质移至真实持有画布底色的元素，令牌层声明 `--canvas-gradient` | **采纳** | 100% 根因修正。`App.tsx` 根容器具有不透明 `bg-[var(--color-canvas-bg)]` 并铺满视口，导致 `body` 背景渐变被遮挡。在令牌层声明 `--canvas-gradient`，由 App 根容器同时消费底色与渐变，实现 SSOT。 |
| **2. 核心纯函数零自动化校验** | 提取纯函数，使用 Node 内置 `node:test` + `node:assert` 编写自检 | **采纳** | 契合非平凡逻辑留存最小可运行校验的纪律。利用 Node 24 原生 `--experimental-strip-types` 与 `node:test`，零新增 npm 依赖，验证星期派生、元信息拼接中点自洽与金额格式契约。 |
| **3. role="menu" 半套 ARIA 缺乏焦点管理** | 补齐焦点管理或收敛为 WAI-ARIA disclosure 模式 | **采纳（选用 disclosure 模式）** | YAGNI。仅有两个操作按钮的轻量浮层引入复杂的 Arrow/Home/End 键盘焦点漫游机制属于过度工程；移除伪 `role="menu"` / `menuitem`，保留 `aria-expanded` 与 `aria-label`，与 `SettingsPage.tsx` 同构一致。 |
| **4. ClockIcon 零引用死代码** | 删除未使用的图标组件 | **采纳** | 遵循删除优于增加，清理死导出。 |
| **5. 令牌选择器遗留与兜底** | 补 `--shadow-flyout` 暗色覆盖；删 `.dark-mode body`；删 `|| ''`；渐变过渡 | **采纳基础修正，校准/驳回渐变过渡** | 补齐暗色浮层阴影、移除不可达兜底与死选择器属于合规清理。但关于 `background-image` CSS transition：CSS 规范不支持跨渐变直接平滑插值，强加 `@property` 或多层透明 DOM 属于过度设计与高脆性黑魔法；由 App 根容器对底色执行 `transition-colors duration-200` 即可提供自然的主题平滑过渡。 |
| **6. <section> 无可访问名称** | 给 `aria-label` 或退回 `<div>` | **采纳（选用 <div>）** | 列表中数十个日容器若全声明为 landmark section 会对读屏用户造成导航噪音；退回 `<div>` 最轻量且语义精确。 |

---

## 2. 实施范围

1. **画布材质与阴影令牌**：`web/src/index.css`, `web/src/App.tsx`
2. **纯函数提取与自动化测试**：`web/src/pages/streamUtils.ts` (新), `web/test/stream.test.ts` (新), `web/package.json`
3. **StreamPage 接入与语义清理**：`web/src/pages/StreamPage.tsx`, `web/src/components/Icons.tsx`, `Makefile`
