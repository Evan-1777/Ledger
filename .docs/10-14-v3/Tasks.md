# Tasks：金额输入框与细分标签抽屉修复

**关联 Plan**：Plan.md v1.1  
**状态**：DONE  
**日期**：2026-10-14  
**完成日期**：2026-10-14  
**总计 Task**：6 个  
**回归测试结论**：npm run lint (TypeScript)、npm test (30 项纯函数与工具测试)、npm run build (Vite 打包) 及 go test -v ./... (全量后端测试) 全部通过 (exit code 0)。依据 SCOPE 约定 9222 远程调试浏览器实例当前离线，带头浏览器环境自动化 DOM 断言未执行；静态代码契约、DOM 结构与层叠规则均已核验完成。

## Explore 证据与交接边界

已查阅关键文件：`.docs/SCOPE.md`、`.docs/Project.md`、`.docs/Plan.example.md`、`.docs/Tasks.example.md`、`web/package.json`、`web/src/index.css`、`web/src/App.tsx`、`web/src/pages/SettingsPage.tsx`、`web/src/components/RecordModal.tsx`、`web/src/components/AuthModal.tsx`、`web/src/components/primitives.tsx`。全部用户截图已阅读：`temp/PixPin_2026-10-14_16-44-56.png`、`temp/PixPin_2026-10-14_16-45-13.png`。

根因证据：

- `index.css:143` 未分层的 `:focus-visible` 高于 Tailwind utility；`RecordModal.tsx:409` 已有外层 focus-within 边框，432 行已有 outline-none，仍被全局规则覆盖。登录与设置等输入有同样的层级关系。
- `App.tsx:383` 页面容器有 animate-rise（transform 动画、both 填充）且建立 z-[1] 上下文；`SettingsPage.tsx:826` 抽屉 fixed inset-0 和 970 行 ConfirmDialog 均渲染在其后代，造成视口覆盖与堆叠受祖先影响。通过 Portal 消除依赖，不以增加 z-index 或删动画修补。
- `SettingsPage.tsx:104` 和 `primitives.tsx:392` 均监听 window Escape，缺少最上层仲裁；设置关闭路径重复且 Esc 与点击重置字段不一致。
- `App.tsx:325` 新增标签捕获异常但未抛出；`SettingsPage.tsx:273` await 后清空草稿，失败也会走清空。
- `App.tsx:167` 的 N 快捷键未排除抽屉和删除确认，焦点在抽屉按钮时能打开记账窗口。

工作区基线有用户既有的技能/AGENTS 暂存变更、`.pi/` 删除、旧 Demo 删除与截图未跟踪文件；这些不属于本次修复，保留原状。执行前重查 git status 和根目录文档，不覆盖新增的用户工作。本次没有修改产品代码、没有运行回归、没有归档或提交。

## Phase 1：焦点与模态挂载

### TASK-001：把默认键盘焦点规则移入基础样式层

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / 无
- **Description**：修改 `web/src/index.css` 中全局 `:focus-visible` 的层归属，让已有控件的 outline-none 和焦点样式正常覆盖。
- **Details**：将默认规则放入 `@layer base`，保留原有品牌色、2px 轮廓与偏移。不引入 important，不全局排除输入，不改金额解析或字号。金额沿用已有外层 focus-within 边框；若浏览器验证需要补充可辨识焦点，补在该外层而非内部输入。检查全部 outline-none 调用点的焦点反馈。
- **Acceptance Criteria**：记账打开自动聚焦、点击、Tab 聚焦金额时内部矩形 outline 不出现；外层蓝色边框仍可见。用途/时间/手续费/设置/登录输入焦点可辨识；导航与图标按钮 Tab 焦点可见。浅深主题均成立，TypeScript 检查通过。

### TASK-002：把标签抽屉与共享删除确认挂载到 body

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / 无，可在 TASK-001 后顺序执行
- **Description**：在 `web/src/pages/SettingsPage.tsx` 和 `web/src/components/primitives.tsx` 用 react-dom 已有的 createPortal 包裹对应覆盖层。
- **Details**：抽屉只迁移覆盖层，状态与 CRUD 保留在 SettingsPage；ConfirmDialog 在共享实现中迁移，检查 App 的账单删除调用者与 Settings 的分类/渠道/标签删除调用者。保留抽屉 z1100、确认 z1200、遮罩阻断与内部 stopPropagation。桌面 420px 贴右、100dvh 约束；窄屏保持底部面板与 85dvh 上限。正文加 min-h-0、输入 flex 项加 min-w-0，防止长列表/长标签和 320px 重命名表单溢出。保留现有圆角与面板边距。不改 App 页面动画、不新增 Portal 抽象。
- **Acceptance Criteria**：动画期间及结束后遮罩 bounds 为 (0,0,innerWidth,innerHeight)，覆盖导航/FAB；桌面面板右边缘等于视口右边缘；320/375px 无横向溢出，长列表只滚正文，完成按钮可达；确认显示在抽屉之上且全视口居中。账单、分类、渠道删除确认无回归。

## Phase 2：抽屉生命周期与异步契约

### TASK-003：统一抽屉关闭并按层处理键盘与焦点

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-002
- **Description**：修改 `SettingsPage.tsx` 的抽屉开关/效果与 Escape 监听、`primitives.tsx` 的确认焦点生命周期、`App.tsx` 的 N 快捷键入口。
- **Details**：
  - 两个管理/查看入口共用打开约定，捕获入口元素；遮罩、右上关闭、完成及 Escape 共用 closeDrawer，清空新标签草稿、重命名 ID/名称；关闭恢复原先 body overflow 与入口焦点。焦点效果只跟开关转换相关，避免 categories 刷新时抢走输入焦点。
  - 确认打开时 Settings 的 Escape 监听直接让位；无确认时先退出标签编辑，再关闭抽屉，关闭路径状态一致；不新增编辑退出后的焦点仲裁。
  - 抽屉初次打开聚焦新增输入，系统分类聚焦关闭按钮；添加程序化可访问名称。共享 ConfirmDialog 保留首焦点到取消，关闭时仅向仍连接到 DOM 的触发元素恢复焦点；触发点因删除消失时允许自然失焦。不实现 Tab/Shift+Tab 焦点环，不添加删除后焦点回退规则或全站模态框架。
  - N 快捷键在存在 `[aria-modal="true"]` 的 dialog/alertdialog 时返回，复用 DOM 真状态，不添加镜像抽屉 state。
  - 锁滚动条件与实际渲染的分类一致；父数据确实移除当前分类时关闭并释放状态，不因普通刷新关闭面板。
- **Acceptance Criteria**：确认弹出后 Esc 仅取消确认，抽屉保持打开；编辑中 Esc 仅取消编辑，第二次 Esc 关闭抽屉；所有关闭途径清空一致、可正常重开。确认关闭后可继续操作抽屉；抽屉关闭焦点回入口、body overflow 恢复；抽屉按钮上按 N 不打开记账，全部关闭后 N 正常。系统分类只读且焦点正确。

### TASK-004：保留新增标签失败时的草稿

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P1 / TASK-003
- **Description**：修正 `App.tsx` 的 handleAddTag 异常语义及 `SettingsPage.tsx` 的 handleCreateTagInDrawer 提交状态。
- **Details**：父回调仍负责单次错误 Toast，提示后 throw；子表单 try/catch/finally，只在 await 成功后清空，失败保留草稿且不重复 Toast。在 handleCreateTagInDrawer 的 preventDefault 后、校验和请求前检查提交锁，锁已占用则直接返回；首次合法提交在 await 前占锁，finally 释放。提交锁使用同步 ref，待提交 state 仅驱动新增输入/按钮禁用，覆盖同一渲染间隔内的连续 submit，不能仅依赖 disabled 或异步 state 更新。不改变 API、已有重名检查与分类 ID 派生标签列表。回调新增错误传播后检查全部调用者，本仓库当前仅有抽屉新增入口。重命名沿用既有失败保留逻辑，不重写所有设置 CRUD。
- **Acceptance Criteria**：模拟新增 400/网络失败，只出现一次错误提示且草稿仍在，可再次提交；慢请求期间连续 Enter/点击及同一事件循环连续分发两个 submit，均只发送一次请求；成功清空草稿、数据刷新后标签计数/列表同步；空名/同名不发送请求。重命名成功更新、失败保留；引用标签删除 409 保持列表。

## Phase 3：验证与交付

### TASK-005：运行前端检查及界面回归

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-001～004
- **Description**：在 `web/` 运行 npm run lint 和 npm test，并在实际浏览器检查金额与抽屉链路。
- **Details**：不增加测试框架、不跑无关后端构建。按 SCOPE 确认可用的 9222 浏览器；不可用时如实记录未完成项，编译不代替视觉验收。以下三个自检分别在指定状态执行，每个脚本缺少前置节点时抛错，不能视为通过；交付时记录状态、断言结果与人工操作结论。

#### 检查 A：仅打开记账窗口，聚焦金额

```js
(() => {
  const amount = document.getElementById("record-amount");
  if (!amount) throw new Error("前置条件：打开记账窗口");
  amount.focus();
  const s = getComputedStyle(amount);
  console.assert(s.outlineStyle === "none" || parseFloat(s.outlineWidth) === 0, "金额输入仍有内部 outline");
})();
```

人工确认外层焦点边框可见，关闭记账窗口，再进入设置页。

#### 检查 B：仅打开细分标签抽屉

```js
(() => {
  const drawer = [...document.querySelectorAll("[role=dialog]")].find(el => el.getAttribute("aria-label")?.includes("细分标签"));
  if (!drawer) throw new Error("前置条件：在设置页打开细分标签抽屉");
  const overlay = drawer.parentElement;
  const r = overlay.getBoundingClientRect();
  console.assert(Math.abs(r.x) < 1 && Math.abs(r.y) < 1 && Math.abs(r.width - innerWidth) < 1 && Math.abs(r.height - innerHeight) < 1, "抽屉遮罩不是完整视口");
  console.assert(overlay.parentElement === document.body, "抽屉未挂载到 body");
  console.assert(innerWidth < 640 || Math.abs(drawer.getBoundingClientRect().right - innerWidth) < 1, "桌面抽屉没有贴右");
  console.assert(document.documentElement.scrollWidth <= innerWidth, "页面横向溢出");
})();
```

人工检查头尾可达、正文滚动，并在抽屉按钮上按 N，确认没有打开记账窗口。

#### 检查 C：抽屉内点击删除标签，确认弹窗已打开

```js
(() => {
  const drawer = [...document.querySelectorAll("[role=dialog]")].find(el => el.getAttribute("aria-label")?.includes("细分标签"));
  const confirmation = document.querySelector("[role=alertdialog]");
  if (!drawer || !confirmation) throw new Error("前置条件：在标签抽屉内打开删除确认");
  confirmation.dispatchEvent(new KeyboardEvent("keydown", {key:"Escape", bubbles:true}));
  requestAnimationFrame(() => {
    console.assert(!document.querySelector("[role=alertdialog]"), "Esc 未取消确认");
    console.assert(drawer.isConnected, "Esc 穿透关闭了抽屉");
  });
})();
```

另用真实 Escape 键重复检查 C；检查标签编辑时第一次 Esc 退出编辑、第二次关闭抽屉。对提交锁使用慢请求及连续 submit，查看 Network 中请求数，不能仅检查按钮是否变灰。

- **Acceptance Criteria**：lint/test exit code 0；浏览器自检无断言失败。桌面截图对应 1873×960、小屏 320/375px，浅深主题，开启减少动效时均检查 TASK-001～004；操作矩阵含新增成功/失败、重命名成功/失败、空/长列表、系统分类、删除确认 Esc/取消/成功/409。记录执行环境与未验证项；没有浏览器时不得宣称已完全验收。

### TASK-006：同步项目记录、归档并单独提交本次修复

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P1 / TASK-005
- **Description**：更新 `.docs/Project.md` 的焦点样式层、抽屉 Portal 与交互契约说明，完成文档状态与归档并提交。
- **Details**：同步实际改动，不将计划写成已实现。Plan/Tasks 标 DONE、完成日期与真实回归结论后，按当天 `.docs/MM-DD-vN/` 最大版本 +1 归档，核对两文件齐全且根目录无残留；执行 git status、git diff（含 --cached）、git log，只暂存本次产品与文档文件，保留既有用户暂存区内容；路径限定提交本次文件，Conventional Commits 英文前缀加中文说明，不使用 amend 或跳过钩子。
- **Acceptance Criteria**：Project 与实际实现一致；归档完整；提交只含本次修复，无用户技能/AGENTS/.pi/截图/旧 Demo 删除改动；提交后报告 commit、测试结果与实际限制。
