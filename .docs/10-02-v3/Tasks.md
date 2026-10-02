# Tasks：基础数据持久化、移动端顶栏去噪与设置页分层抽屉重构

**关联 Plan**：[`Plan.md`](file:///home/dev/projects/Ledger/Plan.md) —— 基础数据持久化、移动端顶栏去噪与设置页分层抽屉重构 v1.2  
**总计 Task**：8 个

---

## Phase 1：种子数据持久化、老库平滑升级与事务保护

### TASK-001：在 internal/db/db.go 中新增 system_meta 表与事务级智能种子注入

- **Status**：DONE
- **Executor**：主线
- **Description**：在 SQLite 数据库中建表 `system_meta`，并在 `migrateAndSeed` 中利用显式数据库事务（`BeginTx`）保证建表、老库探测、种子注入与状态标记的原子性，彻底消除容器重启时误复活已删除数据的问题。
- **Details**：
  - 在 `migrateAndSeed` 中执行建表 SQL：
    ```sql
    CREATE TABLE IF NOT EXISTS system_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
    );
    ```
  - 开启显式事务 `tx, err := db.Begin()`，所有探测与数据写入在 `tx` 内执行（异常时统一 `tx.Rollback()`，成功统一 `tx.Commit()`）；
  - 查询 `system_meta` 是否已存在 `key = 'seed_initialized'`：
    - 若已存在且值为 `'true'`，提交事务直接返回 `nil`。
    - 若不存在该记录，查询核心表（`payment_methods`、`categories`、`transactions`）行数：
      - 若任一表中已存在数据（`COUNT > 0`），判定为老版本数据库无缝升级场景，在 `tx` 中执行 `INSERT INTO system_meta (key, value) VALUES ('seed_initialized', 'true')`，不执行默认种子插入，保护用户已删除的数据不被强行恢复；
      - 若三张表均为空（`COUNT == 0`），判定为全新数据库，在 `tx` 中注入默认支付途径、消费类型与细分标签，随后写入 `INSERT INTO system_meta (key, value) VALUES ('seed_initialized', 'true')`。
- **Acceptance Criteria**：
  - 新数据库文件首次启动，原子写入 4 个支付途径、5 个分类与 16 个标签，并在 `system_meta` 中写入标记；
  - 迁移与初始化逻辑置于显式事务内，杜绝中断产生脏状态；
  - 已有数据的数据库重启或再次调用 `InitDB` 时，绝对不执行默认种子写入。

### TASK-002：在 internal/db/db_test.go 中扩充防复活与老库无 meta 表升级单元测试

- **Status**：DONE
- **Executor**：主线
- **Description**：在数据库单测中分别构建“全新库删除后重启防复活”与“老版本已有数据库平滑升级”两个严密测试用例。
- **Details**：
  - **用例 1（防复活测试）**：在干净测试数据库上执行 `InitDB`；随后删除支付途径「现金钞票」与分类「休闲娱乐」；二次调用 `InitDB` 打开同一数据库，断言已删除项计数为 0，未被再次注入。
  - **用例 2（老库升级测试）**：手动在临时数据库中仅创建老版本表结构（不创建 `system_meta` 表），写入 1 个自定义支付途径（如“自定义卡”）和 1 个自定义分类；随后调用 `InitDB` 执行升级逻辑；断言 `system_meta` 成功创建并标记 `seed_initialized = 'true'`，且数据库中仅包含预置的自定义项，绝对未被强制注入默认的 4 种支付途径或 5 种分类。
- **Acceptance Criteria**：
  - `go test -v ./internal/db/...` 包含上述双用例且测试全部通过。

---

## Phase 2：顶栏响应式文本折叠与移动端深度适配

### TASK-003：重构 web/src/components/Navbar.tsx 胶囊导航（移动端图标化，桌面端保留文字）

- **Status**：DONE
- **Executor**：主线
- **Description**：对齐既有代码响应式断点规范（如登出按钮与管理员标识），为顶栏中央胶囊导航文字配置 `hidden sm:inline`，小屏下只展示纯 SVG 图标，大屏下保留完整图标加文字。
- **Details**：
  - 在 `Navbar.tsx` 中为 `<StreamIcon />`、`<StatsIcon />`、`<SettingsIcon />` 后方的 `<span>` 标签添加 `className="hidden sm:inline"`；
  - 为 3 个胶囊按钮添加标准 `title` 与 `aria-label`（如 `title="账目流水" aria-label="账目流水"`）；
  - 调整胶囊按钮触控热区：在 `< 640px` 移动端为 `w-9 h-8.5` 均等正方形触控区，在 `≥ 640px` 桌面端自适应包裹图标与文字；激活态保留 Fluent 2 品牌高亮与微弱阴影。
- **Acceptance Criteria**：
  - 在 `< 640px` 移动端视口下，胶囊导航仅渲染 3 个纯 SVG 图标，无文字折行与挤压；
  - 在 `≥ 640px` 桌面端视口下，自适应呈现图标与文字，保持良好易用性。

### TASK-004：规范移动端顶栏两端操作簇与安全视口尺寸

- **Status**：DONE
- **Executor**：主线
- **Description**：统一移动端右侧主题切换按钮与登出按钮尺寸，消除横向滚动条。
- **Details**：
  - 统一右侧主题切换按钮与登出按钮的尺寸为 `w-[34px] h-[34px]` 圆角图标按钮；
  - 登出按钮保持 `title="退出登录"` 与 `aria-label="退出登录"`，文字部分已具备 `hidden sm:inline`；
  - 校验 `<header>` 水平内边距（移动端 `px-3`，桌面端 `px-8`），确保在 320px 极端窄屏下无任何水平溢出。
- **Acceptance Criteria**：
  - 在移动端（375px/390px/414px）及 320px 视口下，顶栏各元素单行自适应排开，无任何溢出或重叠。

---

## Phase 3：设置页双核心空间分段与细分标签专属抽屉重构

### TASK-005：重构 web/src/pages/SettingsPage.tsx 为双核心区域分段导航并保留轻量内联新增表单

- **Status**：DONE
- **Executor**：主线
- **Description**：将设置页从一级页面平铺展示重构为清晰的双分段切片（「分类与标签」、「支付途径」），彻底剔除无后端 API 支撑的静态占位卡片；新增操作继续沿用轻量内联展开表单，不引入遮挡视图的模态弹窗。
- **Details**：
  - 顶部页面主标题为「设置」，下方设立双段分段切换按钮（Segmented Tabs）：
    1. **分类与标签**：管理记账消费与收入分类，提供调序、重命名、删除及细分标签管理入口；
    2. **支付途径**：管理收付款渠道，支持卡片化展示与删除保护；
  - 彻底剔除无后端支持的“系统与存储状态”静态虚构占位，剔除无底层字段支持的“快速启闭”描述；
  - 新增分类与新增途径继续沿用 `showAddCatInput` 与 `showAddPmInput` 的就地轻量内联展开表单（输入框 + 确定 + 取消），不引入遮挡视图的 Layer 3 全屏模态弹窗；
  - 分类列表中完整保留：分类名称、细分标签计数 Badge、上移/下移调序按钮、上下文操作菜单（MoreVerticalIcon，包含同构内联重命名与删除），以及「管理标签」专属行动按钮。
- **Acceptance Criteria**：
  - 设置页顶部具备「分类与标签」和「支付途径」双分段平滑切换；
  - 界面纯净无占位噪声，新增分类与新增途径表单轻量可用；
  - 分类行完整保留调序与重命名功能。

### TASK-006：在设置页中实现分类细分标签专属管理抽屉（Layer 3 抽屉容器，基于 SSOT 动态派生）

- **Status**：DONE
- **Executor**：主线
- **Description**：创建右侧滑入式细分标签管理抽屉（Drawer / Subview），实现细分标签的渐进式披露；以 `activeCategoryId` 保持与 `App.tsx` 的单一事实来源（SSOT）绑定，严禁本地脱节拷贝。
- **Details**：
  - 在 `SettingsPage.tsx` 中定义 `activeCategoryId: number | null` 状态；
  - 点击分类行中的「管理标签」或该分类行时，设置 `activeCategoryId = cat.id`，唤起专属滑入抽屉（带半透明毛玻璃背景遮罩）；
  - 抽屉内的数据严格通过 `categories.find(c => c.id === activeCategoryId)` 动态派生，严禁维护断开绑定的独立本地标签数组；
  - 抽屉顶部展示该分类名称与关闭按钮；
  - 抽屉顶部内嵌新增标签输入框，输入后调用父级 `onAddTag`，具备同级重名预校验；
  - 抽屉主体展示该分类所有细分标签，每项支持同构内联重命名表单（`editingTagId`）与删除按钮；删除操作调用父级 `onDeleteTag` 并维持已有的 409 引用拦截 Toast 提示；
  - 严禁退化使用原生 `window.prompt` 或 `window.confirm`；
  - 支持点击背景遮罩、关闭按钮或按下 ESC 键安全收起抽屉。
- **Acceptance Criteria**：
  - 点击「管理标签」平滑呼出抽屉，无任何状态脱节；
  - 抽屉内可顺畅进行标签的新增、内联重命名、删除操作，数据变动实时联动父级 `App.tsx`；
  - 409 引用拦截和重名预校验正常生效。

---

## Phase 4：全流程回归验证与测试用例扩充

### TASK-007：执行后端全量单元测试与接口集成回归

- **Status**：DONE
- **Executor**：主线
- **Description**：运行后端测试集，验证数据持久化、老库无缝升级、分类与标签 CRUD、409 引用拦截及账目统计功能无任何回归。
- **Details**：
  - 运行 `go test -v -race ./internal/...`；
  - 重点核对 `db_test.go`（含老库升级与防复活双用例）与 `server_test.go` 的全用例执行结果。
- **Acceptance Criteria**：
  - 后端测试通过率 100%，无竞态，无回归。

### TASK-008：执行前端 TypeScript 编译检查与单二进制全流程构建

- **Status**：DONE
- **Executor**：主线
- **Description**：执行前端类型检查与项目全局打包，确认单二进制交付链路畅通。
- **Details**：
  - 进入 `web/` 执行 `npm run build` 或在根目录执行 `make test`；
  - 确认 TypeScript 编译零错误，Vite 构建产物成功注入 `web/embed.go`；
  - 执行 `make build` 验证单二进制 `bin/ledger` 编译成功。
- **Acceptance Criteria**：
  - `make test` 零报错；
  - `make build` 生成可独立运行的 `bin/ledger` 二进制文件。
