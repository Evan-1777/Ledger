# Tasks：抽屉新增标签焦点与决策记录修复（Quick）

**关联 Plan**：无（Quick 模式跳过 Plan，故本归档仅含 Tasks.md）  
**状态**：DONE  
**日期**：2026-10-14  
**完成日期**：2026-10-14  
**总计 Task**：3 个  
**回归测试结论**：npm run lint（tsc -b --noEmit）exit 0；npm test 30 项通过 / 0 失败；npm run build（Vite）成功并刷新 web/dist/index.html 资源哈希。本次仅改动前端组件与文档，未触及后端契约，未执行 go test；焦点连续性与重复提交需真实浏览器验证，按 SCOPE 约定 9222 实例离线，未执行带头 DOM 断言。

## 背景

复审确认上一轮交付 `79c2e37` 已修复金额双重焦点与抽屉视口挂载，遗留三项收尾问题：提交期间禁用输入框导致焦点丢失；新增按钮的空值禁用条件与函数内既有校验重复；`.docs/Project.md` 缺少本次带日期的决策记录。

改动范围限定 2 个文件，不涉及后端、接口与全站布局。

## TASK-001：移除新增标签输入框的提交期禁用

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / 无
- **Description**：删除 `web/src/pages/SettingsPage.tsx` 抽屉新增表单中输入框的 `disabled={isSubmittingTag}`。
- **Details**：防重复提交已由 `isCreatingTagRef` 同步锁在函数入口拦截，输入的禁用属重复防御；移除后焦点在请求期间保持于输入框，连续添加与失败重试无需重新点击。`isSubmittingTag` 保留用于按钮的「添加中…」与禁用反馈。
- **Acceptance Criteria**：提交进行中输入框保持聚焦；连续两次 Enter 仅发出一次请求；请求成功后可直接输入下一个标签；失败后草稿与焦点均保留。

## TASK-002：收敛新增按钮的禁用条件

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P1 / TASK-001
- **Description**：将按钮 `disabled` 由 `isSubmittingTag || !drawerNewTagName.trim()` 收敛为 `isSubmittingTag`。
- **Details**：空值校验已存在于 `handleCreateTagInDrawer`（`if (!trimmed) return`），UI 层不再重复；按钮恢复常态可用，空值提交为无副作用的 no-op。
- **Acceptance Criteria**：空输入点击添加不发送请求且无报错；提交中按钮禁用并显示「添加中…」。

## TASK-003：补充决策记录与文档校正

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P1 / 无
- **Description**：在 `.docs/Project.md` 的「约束与决策」追加 2026-10-14 条目，并校正「概述」措辞。
- **Details**：记录两条耐久决策——键盘焦点轮廓归入 `@layer base` 以让控件级 `outline-none` 正常覆盖；模态覆盖层一律 `createPortal` 至 `document.body`，不在带动画的容器内直接渲染 `fixed` 覆盖层。校正「以被 outline-none 覆盖」为「可被 outline-none 覆盖」。不改写历史归档文档。
- **Acceptance Criteria**：条目与代码库实际一致；措辞通顺；无虚构未实现内容。

## 交付约束

- 单 Task 修改文件数 ≤ 3，本次总计 2 个文件
- 提交仅包含本次文件，保留工作区既有暂存变更与未跟踪截图
