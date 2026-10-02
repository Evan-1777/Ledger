# Tasks：复审问题修复与健壮性提升（断点规范、调序防竞态、重命名校验与动画加速）

**关联 Plan**：`Plan.md` —— 复审问题修复与健壮性提升 v1.0  
**状态**：DONE  
**完成日期**：2026-10-02  
**总计 Task**：6 个 (已完成 6 个)

---

## Phase 1：视觉细节与动效硬件加速规范

### TASK-001：修正 Navbar.tsx 登出按钮断点为 hidden sm:inline

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/components/Navbar.tsx` 中将登出文字的无效断点 `hidden xs:inline` 修正为标准断点 `hidden sm:inline`。
- **Details**：
  - 定位 `Navbar.tsx` 登出按钮内部的 `<span className="hidden xs:inline">登出</span>`；
  - 替换为 `<span className="hidden sm:inline">登出</span>`；
  - 保证在小屏设备（< 640px）上仅展示图标保持紧凑，在桌面设备（>= 640px）上恢复图文完整显示。
- **Acceptance Criteria**：
  - 桌面端视口下，登出按钮中的“登出”文字清晰可见；
  - 移动端视口下，文字安全隐藏且无布局溢出；
  - 编译后 CSS 正确包含响应式规则。

### TASK-002：RecordModal.tsx 胶囊滑块改用 GPU transform 硬件加速

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/components/RecordModal.tsx` 中将收支双向胶囊滑块的位移动画由 `left` 属性过渡重构为 `transform: translateX` 硬件加速驱动。
- **Details**：
  - 固定滑块指示器左边界为 `left-1`，宽度保持 `w-[calc(50%-4px)]`；
  - 动效属性改用 `transition-transform duration-200 ease-out`；
  - 激活支出时使用 `translate-x-0`，激活收入时使用 `translate-x-full`；
  - 消除对 `left-[calc(50%+2px)]` 经验偏移的依赖，消除每帧重排（Reflow）。
- **Acceptance Criteria**：
  - 支出与收入状态切换平滑自如，左右边缘内边距像素级对称；
  - 位移由 GPU 合成器通道驱动。

### TASK-003：index.css 补齐 dark-mode 状态边框令牌

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/index.css` 的 `.dark-mode` 作用域中补齐 `--color-expense-stroke` 与 `--color-income-stroke` 令牌。
- **Details**：
  - 在 `.dark-mode` 中添加 `--color-expense-stroke: rgba(239, 68, 68, 0.3);` 与 `--color-income-stroke: rgba(16, 185, 129, 0.3);`；
  - 消除暗色模式下回退到浅色高亮硬边框的问题。
- **Acceptance Criteria**：
  - 暗色模式下，记账模态窗收支滑块处于激活状态时的边框半透明柔和，符合暗色调性。

---

## Phase 2：设置管理健壮性与数据流防竞态改造

### TASK-004：App.tsx 与 SettingsPage.tsx 调序数据流防竞态与序号交换实现

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/App.tsx` 中新增集中式 `handleReorderCategories` 接口，串行提交更新并在完成后仅执行一次 `fetchConfigData()`，消除并发网络竞态；在 `SettingsPage.tsx` 中优先对换已有 `sort_order`，相等时递增打破死锁。
- **Details**：
  - 在 `web/src/App.tsx` 声明 `handleReorderCategories(catA, catB)`：
    - 串行执行 `api.updateCategory(catA.id, catA.name, catA.sort_order)` 与 `api.updateCategory(catB.id, catB.name, catB.sort_order)`；
    - 仅在全部成功后执行一次 `await fetchConfigData()`；
    - 传递 `onReorderCategories` prop 给 `SettingsPage`；
  - 在 `web/src/pages/SettingsPage.tsx` 中计算新序号：
    - 若 `itemA.sort_order !== itemB.sort_order`，直接对换已有序号；
    - 若相等（碰撞状态），分别赋予 `targetIndex + 1` 与 `index + 1`；
    - 调用 `onReorderCategories`。
- **Acceptance Criteria**：
  - 调序网络请求全程只触发一次数据重新拉取，杜绝界面中间态闪烁与并发覆盖；
  - 无论是常规断号还是初始同值碰撞，均可稳定完成调序并持久化。

### TASK-005：SettingsPage.tsx 重命名同级查重、异常捕获与中文错误反馈

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/pages/SettingsPage.tsx` 与 `web/src/App.tsx` 中补齐重命名提交前同级查重，并在事件处理中捕获异常，将后端英文错误信息映射为清晰中文提示。
- **Details**：
  - 在 `SettingsPage.tsx` 的 `handleSaveCatRename` 中：
    - 校验新名称在兄弟分类中是否已存在（`categories.some(c => c.id !== cat.id && c.name === trimmed)`），若存在则提示“该消费类型已存在”并保持编辑框；
    - 用 `try...catch` 包裹 `await onUpdateCategory(...)`，保存成功才执行 `setEditingCatId(null)`，抛错时保留编辑态且不触发未捕获 Promise Rejection；
  - 在 `SettingsPage.tsx` 的 `handleSaveTagRename` 中：
    - 校验新名称在同分类细分标签中是否已存在（`currentCategory.tags.some(t => t.id !== tag.id && t.name === trimmed)`），若存在则提示“该分类下已存在同名标签”；
    - 用 `try...catch` 包裹 `await onUpdateTag(...)`；
  - 在 `App.tsx` 中：若捕获到 `category already exists` 映射提示“消费类型名称已存在”，若捕获到 `tag already exists in this category` 映射提示“该分类下已存在同名标签”。
- **Acceptance Criteria**：
  - 输入同名分类或标签时，前端即时拦截并给出中文友好提示；
  - 异常情况下控制台零 Unhandled Promise Rejection；
  - 错误反馈全流程 100% 保持中文界面。

---

## Phase 3：全链路回归验证与构建交付

### TASK-006：自动化回归测试与文档同步

- **Status**：DONE
- **Executor**：主线
- **Description**：执行全套自动化回归测试，确保无回归故障，并同步更新 `.docs/Project.md`。
- **Details**：
  - 执行 `make test` 验证后端单元测试与前端 TypeScript 静态检查；
  - 审查暗色模式与桌面端登出按钮样式；
  - 更新 `.docs/Project.md` 约束与决策记录。
- **Acceptance Criteria**：
  - `make test` 全部通过，退出码为 0；
  - `.docs/Project.md` 与实际代码保持严格一致。
