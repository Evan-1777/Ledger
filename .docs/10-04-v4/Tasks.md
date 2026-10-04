# Tasks：流水重构复审批判吸收与质量加固 (Quick)

**状态**：DONE  
**完成日期**：2026-10-04  
**模式**：Quick  
**回归测试结论**：`make test` 全部通过（Go 18 项测试全绿、前端 TypeScript 检查零错误、Node 原生自检 17 项全绿）；`make build` 成功编译单二进制可执行文件 `bin/ledger`。  
**关联 Plan**：`Plan.md`  
**总计 Task**：3 个（已全部完成）  

---

### TASK-001：画布 Mica 材质令牌化与暗色浮层阴影修正

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/index.css` 令牌层声明 `--canvas-gradient`，并在暗黑模式补齐 `--shadow-flyout`；在 `web/src/App.tsx` 根容器消费渐变材质并移除 `body` 上的遮挡死样式。
- **Details**：
  - 在 `web/src/index.css` 的 `:root` 与 `.dark-mode` 分别声明 `--canvas-gradient` 顶部径向渐变；
  - 在 `.dark-mode` 中补齐漏掉的 `--shadow-flyout: 0 12px 28px rgba(0, 0, 0, 0.45), 0 2px 8px rgba(0, 0, 0, 0.3);`；
  - 清除 `index.css` 中 `body` 上的 `background-image` 以及无用的 `.dark-mode body, body.dark-mode` 规则；
  - 在 `web/src/App.tsx` 的根 `div` 容器（真实画布底色承载者）追加 `[background-image:var(--canvas-gradient)] bg-no-repeat transition-colors duration-200`。
- **Acceptance Criteria**：
  - 浅色与暗色模式下，页面顶部均可清晰感知极淡品牌色 Mica 材质渐变；
  - 顶栏半透磨砂玻璃（`backdrop-blur-md`）正常透出渐变氛围底色；
  - 暗黑模式浮层阴影深度与 Modal / Card 规范对齐；
  - `npm run lint` 通过。

---

### TASK-002：提取流水纯函数并建立轻量自动化自检

- **Status**：DONE
- **Executor**：主线
- **Description**：新建 `web/src/pages/streamUtils.ts` 导出星期派生、元信息组装与金额格式化纯函数；在 `web/test/stream.test.ts` 中基于 Node 24 原生 `node:test` 建立全覆盖确定性单测，并配置 `package.json` 测试脚本。
- **Details**：
  - 提取 `getDayInfo(dateStr: string, today?: Date)`：使用本地时区解析年月日，支持显式传入基准日期以供确定性测试，移除 `WEEKDAYS[...] || ''` 不可达兜底分支；
  - 提取 `formatTime(isoStr: string)`；
  - 提取 `buildMetaParts(item: TransactionItem)`：组装分类、标签、双向账户流向与时间，杜绝产生空元素或悬浮分隔点；
  - 提取 `formatAmount(amount: number, type?: string, amount_cents?: number)`：统一格式化为 `{ sign, formattedText: '${sign}¥${amountStr}' }`；
  - 新建 `web/test/stream.test.ts`：测试星期计算（验证防 UTC 漂移、今天/昨天/本年/跨年格式）、元信息组装（覆盖支出/收入/转账/还款各分支与缺失字段）、金额契约（正负符号与千分位规范）；
  - 在 `web/package.json` 中配置 `"test": "node --experimental-strip-types --test test/*.test.ts"`。
- **Acceptance Criteria**：
  - 纯函数逻辑独立可测，零组件状态与 DOM 耦合；
  - 执行 `npm run test` 运行 Node 原生自检单测 100% PASS，耗时 < 150ms 且无任何第三方测试框架依赖。

---

### TASK-003：StreamPage 接入纯函数并收敛浮层与容器语义

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/pages/StreamPage.tsx` 中接入外部纯函数，将日分组退回 `<div>` 并将二级浮层收敛至 WAI-ARIA disclosure 规范；删除 `web/src/components/Icons.tsx` 中无引用的 `ClockIcon`，并在 `Makefile` 的 `test` 目标串联前端自检。
- **Details**：
  - `StreamPage.tsx` 从 `./streamUtils.ts` 导入 `getDayInfo`、`buildMetaParts` 与 `formatAmount`，移除内部重复实现；
  - 将日分组外层 `<section>` 替换为 `<div>`，消除大量伪 landmark 导致的无障碍导航噪音；
  - 移除操作浮层与按钮上的 `role="menu"` 和 `role="menuitem"`，将触发按钮设为 `aria-haspopup="true"` 与 `aria-expanded={isMenuOpen}`，与 `SettingsPage.tsx` 保持行为与无障碍语义同构；
  - 删除 `web/src/components/Icons.tsx` 中的 `ClockIcon` 导出；
  - 在 `Makefile` 的 `test` 规则中增加 `&& npm run test`。
- **Acceptance Criteria**：
  - `ClockIcon` 死代码被彻底清除；
  - 账目流水页面功能与视觉表现完全无损；
  - `make test` 同时通过 Go 后端测试、前端 TypeScript 类型检查与 Node 原生纯函数自检；
  - `make build` 编译单二进制可执行文件通过。
