# Tasks：界面去噪重塑、类型标签二级管理增强与移动端深度适配

**状态**：DONE  
**完成日期**：2026-10-02  
**回归测试结论**：`make test` 全套测试与 TypeScript 静态检查 100% 通过（退出码 0）。  
**关联 Plan**：`Plan.md` —— 界面去噪重塑、类型标签二级管理增强与移动端深度适配 v1.1  
**总计 Task**：13 个（已完成 13 个）  

---

## Phase 1：流水页面与账单卡片视觉去噪重构

### TASK-001：移除流水卡片单侧彩色硬边框与首字图标

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/pages/StreamPage.tsx` 中移除账单卡片单侧彩色粗边框与分类首字方块图标，重构为纯净中性卡片与清晰字体层级。
- **Details**：
  - 移除 `border-l-4 border-l-[var(--color-expense)]` 和 `border-l-4 border-l-[var(--color-income)]` 类名，统一采用 `border border-[var(--color-neutral-stroke)]`；
  - 移除首字图标容器 `<div className="w-9 h-9 rounded-lg ...">{item.category_name.charAt(0)}</div>`；
  - 左侧区域以用途说明作为主标题，横向紧跟分类与细分标签徽标；次行呈现发生时分与支付渠道；
  - 账目空状态提示文字由“点击右下角 “+” 开始记录第一笔收支”更新为“点击右下角 “+” 开始记账”。
- **Acceptance Criteria**：
  - 流水卡片四周无单侧加粗彩色边框；
  - 卡片左侧无首字方块图标；
  - 标题、标签、时间与金额的排版清晰自然无错位。

### TASK-002：调整流水卡片操作按钮的触摸与桌面响应

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/pages/StreamPage.tsx` 中优化编辑与删除操作按钮的交互显隐策略，保留既有 `title` 属性，兼顾桌面端悬浮与移动端触控。
- **Details**：
  - 调整操作按钮显隐类名：桌面端保持悬浮感知，移动端保持可见（`opacity-65 sm:opacity-0 sm:group-hover:opacity-100 transition-opacity`）；
  - 保留既有 `title="编辑账单"` 与 `title="删除账单"` 作为提示，不添加冗余的 `aria-label`；
  - 调整卡片右侧金额与操作区在移动屏幕下的弹性空间，防止金额与按钮发生重叠截断。
- **Acceptance Criteria**：
  - 桌面端悬浮出现操作按钮；
  - 移动设备触控无需悬停即可直接点击编辑与删除；
  - 无重复属性膨胀。

---

## Phase 2：记账模态窗交互重塑与文案精简

### TASK-003：实现记账模态窗双向胶囊滑块收支切换

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/components/RecordModal.tsx` 中引入顶置双向胶囊滑块（支出 / 收入），默认选中支出态，提供物理滑动视觉反馈。
- **Details**：
  - 在表单顶部构建全宽/高可见度的分段胶囊容器，包含平滑滑动的背景滑块指示器；
  - 设置默认状态为支出（`isExpense = true`）；
  - 点击“支出”或“收入”时平滑位移指示器，并高亮对应语义色彩（支出深红/收入深绿）；
  - 移除原有金额输入框内部的微型药丸切换按钮；
  - 保证提交时依据当前胶囊状态正确映射为正负数值。
- **Acceptance Criteria**：
  - 打开记账弹窗默认选中支出；
  - 点击收入和支出有平滑滑动位移动效；
  - 金额输入区内无重复的药丸切换按钮。

### TASK-004：移除用途说明快捷输入与修正弹窗标题

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/components/RecordModal.tsx` 中彻底删除用途说明快捷预置标签，并将弹窗标题统一由“记一笔账”改为“记账”。
- **Details**：
  - 彻底删除 `quickChips` 数组定义及对应的预置输入按钮集群 DOM；
  - 用途说明保留单一简洁的输入框与规范的 placeholder；
  - 弹窗头部标题由 `{initialTransaction ? '编辑账单' : '记一笔账'}` 修改为 `{initialTransaction ? '编辑账单' : '记账'}`。
- **Acceptance Criteria**：
  - 用途说明下方无任何快捷标签；
  - 新建记账时弹窗头部标题为“记账”，编辑时为“编辑账单”。

### TASK-005：移除分类细分级联选择器首字图标

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/components/RecordModal.tsx` 中移除分类触发器及展开级联面板中的所有首字方块图标。
- **Details**：
  - 移除触发按钮内部的 `{currentCategory?.name ? currentCategory.name.charAt(0) : '未'}` 首字容器；
  - 移除级联面板左侧分类列表项中的 `{cat.name.charAt(0)}` 首字容器；
  - 保持层级结构纯净，以清晰的分类名称加右向箭头直接衔接细分标签。
- **Acceptance Criteria**：
  - 级联触发按钮与弹出选择面板中无任何首字方块图标；
  - 分类与细分标签展示整洁规范。

---

## Phase 3：消费类型手动排序与二级操作菜单

### TASK-006：消费类型纯文本标题呈现、防碰撞排序与 App.tsx 状态同步

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/pages/SettingsPage.tsx` 与 `web/src/App.tsx` 中移除消费类型首字图标，采用纯文本标题，并实现基于绝对索引递增的上下手动排序，在 `App.tsx` 贯通更新回调。
- **Details**：
  - 移除卡片左侧首字方块图标，定死采用纯文本标题结构：`{cat.name}` 与 `({cat.tags?.length || 0} 个细分标签)`；
  - 在卡片头部右上角直接设置外露的“上移”与“下移”控制按钮（首项禁用上移，末项禁用下移）；
  - 排序算法防碰撞：当用户点击上移/下移交换位置时，重新按照数组排列次序给两项分配新的 `sort_order`（赋值为严格递增的目标序号，如交换后对应位置的索引递增值，消除同值 0 碰撞死锁）；
  - 在 `web/src/App.tsx` 补充 `handleUpdateCategory`（内部调用 `api.updateCategory` 并触发 `fetchConfigData()` 刷新全局单源数据），并作为 prop 传给 `SettingsPage`；
  - 若网络请求失败，通过 Toast 报警并重新触发数据拉取以补偿重置。
- **Acceptance Criteria**：
  - 消费类型卡片头部为整洁纯文本标题，无首字图标；
  - 点击上移或下移能够正确调整相邻分类顺序，并无视旧 `sort_order` 是否同值均能成功调序；
  - `App.tsx` 完整维护分类更新链路，`make test` 静态类型检查零报错。

### TASK-007：构建消费类型二级操作上下文菜单与同构内联重命名

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/pages/SettingsPage.tsx` 与 `web/src/components/Icons.tsx` 中增加更多操作按钮与二级上下文菜单，支持内联重命名与删除。
- **Details**：
  - 在 `web/src/components/Icons.tsx` 中补齐 `MoreVerticalIcon`；
  - 在卡片头部操作区增加更多操作按钮 `···` 与弹出式二级菜单（Layer 3 popover）；
  - 避免过度设计：二级菜单内部**坚决不重复放置**已外露的上移/下移按钮，专注收纳低频次操作：“重命名类型”与“删除类型”；
  - 定死重命名交互：点击“重命名类型”激活当前分类的内联编辑输入框（与既有“新增分类”表单风格完全同构，消除多余模态弹窗），保存后调用 `onUpdateCategory`；
  - 点击菜单外部区域自动关闭浮层。
- **Acceptance Criteria**：
  - 消费类型卡片具备收纳“重命名类型”与“删除类型”的精简二级菜单，无冗余调序项；
  - 重命名以内联输入框形态展示并成功持久化生效；
  - 点击外部自动关闭菜单。

### TASK-008：构建细分标签二级操作菜单与同构内联重命名

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/pages/SettingsPage.tsx` 与 `web/src/App.tsx` 中改造细分标签微章交互，移除单一删除叉号，提供二级操作菜单支持重命名与删除，并在 `App.tsx` 贯通回调。
- **Details**：
  - 改造细分标签微章样式：定死在微章右侧附带微型更多操作符号 `···`；
  - 点击展开标签二级菜单，包含：“重命名标签”与“删除标签”；
  - 定死重命名交互：点击“重命名标签”展开内联修改输入框（与现有“新增标签”输入框完全同构），输入新名称后调用 `onUpdateTag`；
  - 在 `web/src/App.tsx` 补充 `handleUpdateTag`（内部调用 `api.updateTag` 并触发 `fetchConfigData()` 刷新全局单源数据），并作为 prop 传给 `SettingsPage`；
  - 点击外部自动关闭菜单。
- **Acceptance Criteria**：
  - 细分标签具备独立二级操作菜单；
  - 能够以内联表单平滑重命名细分标签并实时同步至全局；
  - `App.tsx` 与 `SettingsPage.tsx` 类型契约完整闭环。

---

## Phase 4：统计看板微调与移动端全屏深度适配

### TASK-009：删除统计看板下钻说明文案

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/pages/StatsPage.tsx` 中删除“点击分类查看细分标签下钻”提示文案。
- **Details**：
  - 定位并彻底删除包含“点击分类查看细分标签下钻”的文本标签 DOM；
  - 保持卡片头部布局规整，仅保留“当月支出分类占比”主标题；
  - 保留分类卡片交互式点击展开细分明细的完整逻辑。
- **Acceptance Criteria**：
  - 统计页面不再渲染任何下钻操作指导文案；
  - 点击分类柱状条依然可正常下钻查看细分标签数据。

### TASK-010：重构底部悬浮工具栏解决移动端冲突并处理 showFilter 退化

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/components/BottomBar.tsx` 中重构筛选胶囊与记账 FAB 按钮的定位布局，解决窄屏遮挡，明确非流水页时的布局退化，并修正文案。
- **Details**：
  - 解决窄屏冲突：在移动视口（`< 640px`）且 `showFilter=true` 时，采用安全避让排版（筛选胶囊居中靠左，留出右侧 64px 间隙供 FAB 停靠），彻底杜绝物理遮挡；
  - 处理布局退化：在 `showFilter=false` 状态（统计页与设置页）下，不渲染任何空通栏底栏，仅保留独立的悬浮圆形 FAB，消除左侧大片空白失衡与内容遮挡；
  - 将记账悬浮按钮的 title 由“记一笔 (快捷键 N)”改为“记账 (快捷键 N)”；
  - 保证所有底部按钮触控面积不小于 40px。
- **Acceptance Criteria**：
  - 在 375px 流水页视口下，筛选胶囊与记账 FAB 完全无重合；
  - 在统计和设置页（`showFilter=false`）下，仅显示轻量悬浮 FAB，无空白底栏遮挡；
  - FAB 按钮提示文案为“记账 (快捷键 N)”。

### TASK-011：深度优化顶栏与弹窗移动端触摸自适应

- **Status**：DONE
- **Executor**：主线
- **Description**：在 `web/src/components/Navbar.tsx`、`web/src/components/RecordModal.tsx` 与 `web/src/pages/SettingsPage.tsx` 中适配移动端小视口。
- **Details**：
  - `Navbar.tsx`：内边距适配为 `px-3 sm:px-8`，胶囊导航项在小屏下适度收紧内边距（`px-2.5 sm:px-4`），确保小屏幕下不换行、不溢出；
  - `RecordModal.tsx`：弹窗外层边距移动端自适应，最大高度设为 `max-h-[90vh]` 并开启内部平滑滚动；支付渠道由 `grid-cols-4` 改为 `grid-cols-2 sm:grid-cols-4`；
  - `SettingsPage.tsx`：支付渠道网格同步适配为 `grid-cols-2 sm:grid-cols-4`。
- **Acceptance Criteria**：
  - 在移动设备视口（375px–390px）下，顶部导航完整显示无挤压换行；
  - 记账弹窗在小屏完整展示无溢出剪裁；
  - 支付方式按钮网格整齐无文本截断。

---

## Phase 5：全链路回归验证与构建交付

### TASK-012：执行全套自动化测试与静态类型检查

- **Status**：DONE
- **Executor**：主线
- **Description**：运行工程级自动化测试与前端 TypeScript 静态编译，保证无回归缺陷与类型错误。
- **Details**：
  - 运行 `make test` 执行全套 Go 单元测试与端点集成测试；
  - 检查 `tsc -b --noEmit` 确保无任何 TypeScript 类型缺失或隐式 any；
  - 记录测试输出与运行耗时。
- **Acceptance Criteria**：
  - `make test` 全部通过且退出码为 0；
  - 前端编译检查零报错。

### TASK-013：代码级响应式断点审查与文档同步

- **Status**：DONE
- **Executor**：主线
- **Description**：对修改涉及的前端组件进行响应式断点（`sm:`、`grid-cols`、`max-h`）代码级静态审查，并更新 `.docs/Project.md`。
- **Details**：
  - 依据设计规范逐项核验 `StreamPage.tsx`、`RecordModal.tsx`、`SettingsPage.tsx`、`Navbar.tsx`、`BottomBar.tsx` 的断点类名与 touch targets；
  - 更新 `.docs/Project.md` 描述消费类型排序、二级菜单与移动端自适应约定；
  - 确保文档与代码库实际状态精确一致。
- **Acceptance Criteria**：
  - 代码级响应式类名检查无遗漏；
  - `.docs/Project.md` 已同步记录关键改动。
