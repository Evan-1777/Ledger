# 移动端体验优化、收入分类逻辑重构与账户转账功能设计方案

> 本文为 Ledger 系统在移动端交互适配、收支分类体系分离以及双向账户转账闭环的功能设计方案。旨在向记账爱好者与项目开发者系统化阐述财务模型、交互设计与系统实现路径。

---

## 1. 业务背景与财务逻辑常识

个人记账的核心诉求是真实、精准地反映财务状态的流动与存量。为了让非财务专业背景的记账爱好者轻松理解本次三大改动的本质，我们先通过通俗的生活场景建立清晰的认知基准：

<div style="border: 1px solid #e1dfdd; border-radius: 8px; padding: 18px; margin: 16px 0; background: #ffffff; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;">
  <div style="font-weight: 600; font-size: 14px; color: #201f1e; margin-bottom: 12px; display: flex; align-items: center; gap: 8px;">
    <span style="display: inline-block; width: 4px; height: 16px; background: #0078d4; border-radius: 2px;"></span>
    记账三大核心场景：资金流向与净资产关系矩阵
  </div>
  <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 12px;">
    <div style="border: 1px solid #edebe9; border-radius: 6px; padding: 12px; background: #faf9f8;">
      <div style="font-weight: 600; font-size: 13px; color: #a4262c; margin-bottom: 4px;">1. 消费支出 (Expense)</div>
      <div style="font-size: 12px; color: #605e5c; line-height: 1.5;">资金流向外部商户（如午餐、超市）。<br><strong>结果：</strong>个人总资产减少，净资产减少。</div>
    </div>
    <div style="border: 1px solid #edebe9; border-radius: 6px; padding: 12px; background: #faf9f8;">
      <div style="font-weight: 600; font-size: 13px; color: #107c10; margin-bottom: 4px;">2. 劳动/收益收入 (Income)</div>
      <div style="font-size: 12px; color: #605e5c; line-height: 1.5;">外部资金流入资产渠道（如工资、奖金）。<br><strong>结果：</strong>个人总资产增加，净资产增加。</div>
    </div>
    <div style="border: 1px solid #edebe9; border-radius: 6px; padding: 12px; background: #eff6fc;">
      <div style="font-weight: 600; font-size: 13px; color: #0078d4; margin-bottom: 4px;">3. 内部调拨/转账 (Transfer)</div>
      <div style="font-size: 12px; color: #605e5c; line-height: 1.5;">资金在自有账户间流动（如银行卡转微信）。<br><strong>结果：</strong>总资产不变，净资产绝对守恒。</div>
    </div>
  </div>
</div>

> [!NOTE] **为什么「转账」和「还款」绝不能算作支出或收入？**  
> 举个简单的例子：如果您从银行卡提现 1000 元放入钱包，您的口袋里多了 1000 元现金，银行卡少了 1000 元存款，您个人的总财富没有任何增减。如果系统将这次取现记为“支出 1000 元”，月末报表就会出现 1000 元的虚假消费，导致损益报表严重失真。同理，从银行卡偿还信用卡欠款（还款），也是负债与资产等额双消，净资产保持守恒。

---

## 2. 核心功能点与系统痛点深度剖析

针对当前系统的三大核心诉求，我们对照代码实现与真实移动端使用场景进行根因溯源：

### 2.1 移动端改动/记账弹窗展示不全（截断与滚动死锁）

<div style="border: 1px solid #e1dfdd; border-radius: 8px; padding: 16px; margin: 16px 0; background: #ffffff;">
  <div style="font-weight: 600; font-size: 13px; color: #323130; margin-bottom: 10px;">移动端截断根因排查与解法对照</div>
  <div style="display: flex; flex-direction: column; gap: 8px;">
    <div style="display: flex; align-items: flex-start; gap: 10px; font-size: 12px; padding: 8px; background: #fff4ce; border-radius: 4px;">
      <span style="font-weight: 600; color: #797775; min-width: 70px;">根因 1：视口高度</span>
      <span style="color: #323130;">原实现使用 <code>max-h-[90vh]</code>。移动端浏览器顶底常驻地址栏与工具条，实际视口高度动态变化，导致弹窗底部超出了可见区域。<strong>解法：</strong>全面适配 <code>max-h-[calc(100dvh-24px)]</code>（动态视口 dvh 规范），杜绝系统底栏遮挡。</span>
    </div>
    <div style="display: flex; align-items: flex-start; gap: 10px; font-size: 12px; padding: 8px; background: #fff4ce; border-radius: 4px;">
      <span style="font-weight: 600; color: #797775; min-width: 70px;">根因 2：操作区被埋</span>
      <span style="color: #323130;">“保存修改”和“取消”按钮被放在可滚动表单的最底部。小屏打开弹窗或键盘弹起时，必须滑动到底才能点击保存。<strong>解法：</strong>操作栏抽离为 Flex 结构固定的常驻 Footer（<code>flex-shrink-0 border-t</code>），永远常驻弹窗底部，触手可及。</span>
    </div>
    <div style="display: flex; align-items: flex-start; gap: 10px; font-size: 12px; padding: 8px; background: #fff4ce; border-radius: 4px;">
      <span style="font-weight: 600; color: #797775; min-width: 70px;">根因 3：浮层覆盖与死锁</span>
      <span style="color: #323130;">原分类选择采用 <code>absolute top-[100%] h-[220px]</code> 绝对定位悬浮展开，其遮挡了下方的账户按钮，且其内部嵌套两个独立滚动条，在触屏上极易触发滚动手势冲突。<strong>解法：</strong>平滑内联展开（Inline Flow），分类展开时自然推移下方内容，单滚动条通畅滑动。</span>
    </div>
  </div>
</div>

---

### 2.2 完善收入记账填写逻辑（收支分类混杂痛点）

当前系统中，`categories` 表未声明业务类型，导致以下怪象：
1. **荒谬的默认值**：当用户在记账弹窗中切换到「+ 收入」时，默认选中的分类仍然是排在第一位的支出分类「餐饮美食 · 午餐」，记一笔工资却默认扣在“午餐”上；
2. **选择器分类污染**：在记收入时，下拉菜单中展开的全是“餐饮”、“交通”、“居家”、“娱乐”等消费支出类别，用户需要翻找才能找到“职业收入”；记支出时，下拉菜单又混入“职业收入”；
3. **入账渠道已收敛，本次保持**：在现行实现中，收入模式已限定仅展示资产渠道（`assetMethods`），本次改动须完整维持该约束，确保资金仅能存入资产账户。

<div style="border: 1px solid #d0d7de; border-radius: 8px; padding: 14px; margin: 16px 0; background: #f6f8fa;">
  <div style="font-weight: 600; font-size: 13px; color: #24292f; margin-bottom: 8px;">收支分类体系分离模型</div>
  <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 12px; font-size: 12px;">
    <div style="border: 1px solid #d0d7de; border-radius: 6px; padding: 10px; background: #ffffff;">
      <div style="font-weight: 600; color: #cf222e; margin-bottom: 6px;">支出专用分类 (type = 'expense')</div>
      <div style="color: #57606a; line-height: 1.6;">
        • 餐饮美食（午餐、晚餐、咖啡奶茶、超市买菜）<br>
        • 交通出行（地铁、打车出租、公交）<br>
        • 居家生活（房租月供、物业水暖、日用百货）<br>
        • 休闲娱乐（电影演出、数字游戏、运动健身）
      </div>
    </div>
    <div style="border: 1px solid #d0d7de; border-radius: 6px; padding: 10px; background: #ffffff;">
      <div style="font-weight: 600; color: #1a7f37; margin-bottom: 6px;">收入专用分类 (type = 'income')</div>
      <div style="color: #57606a; line-height: 1.6;">
        • 职业收入（主业工资、年终奖金、兼职报酬）<br>
        <span style="font-size: 11px; color: #8c959f;">（注：系统默认仅预置「职业收入」，「投资理财」「其他收入」等更多收入分类可由用户在基础设置中按需自行创建并维护）</span>
      </div>
    </div>
  </div>
</div>

---

### 2.3 支持账户之间的转账（资金内部调拨闭环）

在日常生活中，“转账”是高频资金调度行为（如银行卡转到微信用于发红包、从支付宝提现到招行卡）。支持转账需构建完整的业务闭环：

<div style="border: 1px solid #e1dfdd; border-radius: 8px; padding: 16px; margin: 16px 0; background: #ffffff;">
  <div style="font-weight: 600; font-size: 13px; color: #201f1e; margin-bottom: 12px;">转账资金流转与物理守恒机制</div>
  <div style="display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 10px; padding: 12px; background: #eff6fc; border-radius: 6px;">
    <div style="text-align: center; flex: 1; min-width: 120px;">
      <div style="font-size: 11px; color: #605e5c;">转出账户（资产渠道 A）</div>
      <div style="font-weight: 600; font-size: 13px; color: #a4262c; margin-top: 2px;">招商银行储蓄卡</div>
      <div style="font-size: 12px; color: #a4262c; font-family: monospace;">- ¥ 1,000.00</div>
    </div>
    <div style="font-size: 18px; color: #0078d4; font-weight: bold;">➔</div>
    <div style="text-align: center; flex: 1; min-width: 120px;">
      <div style="font-size: 11px; color: #605e5c;">转入账户（资产渠道 B）</div>
      <div style="font-weight: 600; font-size: 13px; color: #107c10; margin-top: 2px;">微信支付零钱</div>
      <div style="font-size: 12px; color: #107c10; font-family: monospace;">+ ¥ 1,000.00</div>
    </div>
    <div style="border-left: 2px dashed #0078d4; padding-left: 12px; text-align: left; min-width: 150px;">
      <div style="font-size: 11px; color: #605e5c;">宏观会计核算：</div>
      <div style="font-size: 12px; font-weight: 600; color: #0078d4;">净变动 = ¥ 0.00</div>
      <div style="font-size: 11px; color: #605e5c;">净资产与总资产物理守恒</div>
    </div>
  </div>
</div>

---

## 3. 四大业务模式全景对照矩阵

将系统的记账类型扩充为四个清晰的原子模式：

| 业务维度 | − 支出 (Expense) | + 收入 (Income) | ⇄ 转账 (Transfer) | ↺ 还款 (Repayment) |
|---|---|---|---|---|
| **业务本质** | 生活消费支出 | 劳动或资本所得 | 资产间内部调拨 | 偿还信用欠款 |
| **净资产变动** | 减少（Net Assets ↓） | 增加（Net Assets ↑） | 严格守恒（恒为 0） | 严格守恒（恒为 0） |
| **分类与标签** | 自由选择【支出分类】 | 自由选择【收入分类】 | 🔒 自动锁定【账户转账·资金互转】 | 🔒 自动锁定【债务偿还·负债还款】 |
| **渠道候选池** | 支出渠道（资产/负债） | 存入渠道（资产账户） | 转出资产账户 + 转入资产账户 | 转入负债账户 + 转出资产账户 |
| **损益报表计入** | 计入周/月消费支出 | 计入月度收入与结余 | 严格排除（不污染损益） | 严格排除（不污染损益） |
| **流水列表标记** | `-¥xx`（赤字色） | `+¥xx`（收入绿色） | `¥xx`（品牌蓝流向：A → B） | `¥xx`（品牌蓝流向：A → 信用卡） |
| **日分组小计** | 计入当日支出小计 | 计入当日收入小计 | 严格排除，不计入小计 | 严格排除，不计入小计 |

---

## 4. 前端交互与界面视觉架构（Microsoft Fluent 2 规范）

依据工程纪律与 Fluent 2 视觉语言规范，界面保持纯净克制，无冗余噪声。

### 4.1 记账模态窗（RecordModal）架构演进

<div style="border: 1px solid #e1dfdd; border-radius: 8px; padding: 16px; margin: 16px 0; background: #ffffff;">
  <div style="font-weight: 600; font-size: 13px; color: #201f1e; margin-bottom: 12px;">模态弹窗垂直分层物理模型 (Layer 3)</div>
  <div style="display: flex; flex-direction: column; gap: 8px; font-size: 12px;">
    <div style="border: 1px solid #0078d4; background: #eff6fc; padding: 10px; border-radius: 6px; display: flex; justify-content: space-between; align-items: center;">
      <span style="font-weight: 600; color: #0078d4;">1. Header 顶栏（常驻，flex-shrink-0）</span>
      <span style="color: #605e5c;">标题（记账 / 编辑账单）+ 右上角关闭图标按钮</span>
    </div>
    <div style="border: 1px dashed #8a8886; background: #faf9f8; padding: 12px; border-radius: 6px; display: flex; flex-direction: column; gap: 6px;">
      <span style="font-weight: 600; color: #323130;">2. Body 可滚动内容区（flex-1 overflow-y-auto）</span>
      <span style="color: #605e5c;">• 顶部 4 段平滑胶囊滑块（支出 / 收入 / 转账 / 还款）</span>
      <span style="color: #605e5c;">• 金额输入盒（大号等宽数字，¥ 前缀）</span>
      <span style="color: #605e5c;">• 用途说明输入框</span>
      <span style="color: #605e5c;">• 分类与细分标签（收支动态分流，内联展开）</span>
      <span style="color: #605e5c;">• 渠道网格（支出全渠道、收入资产渠道、转账双资产渠道、还款负债+资产）</span>
      <span style="color: #605e5c;">• 记账时间选择器</span>
    </div>
    <div style="border: 1px solid #107c10; background: #dff6dd; padding: 10px; border-radius: 6px; display: flex; justify-content: space-between; align-items: center;">
      <span style="font-weight: 600; color: #107c10;">3. Footer 底部操作栏（常驻，flex-shrink-0 border-t）</span>
      <span style="color: #323130;">「取消」+「记录此账单 / 保存修改」主按钮（无论何时均可见）</span>
    </div>
  </div>
</div>

1. **四段胶囊滑块**：
   - 切换为 `grid-cols-4`：`− 支出` | `+ 收入` | `⇄ 转账` | `↺ 还款`；
   - 采用标准 CSS `transform: translateX(...)` GPU 硬件加速平滑滑动；
   - 编辑已有账单（`initialTransaction`）时置为锁定态，防止篡改账务类型导致跨类型结构撕裂。
2. **转账与还款系统分类锁定卡片**：
   - 转账时展示：`账户转账 · 资金互转` + 🔒 固定图标；
   - 还款时展示：`债务偿还 · 负债还款` + 🔒 固定图标；
   - 均无需用户额外手动点击挑选，减轻认知负担。
3. **转账渠道双选体验**：
   - 提供「转出账户」（资产账户）和「转入账户」（资产账户）；
   - 前置互斥防重：选定转出账户后，转入账户候选池中该同名项自动置灰禁用，杜绝非法状态可选；服务端同步配置 400 校验作为最终防御兜底。

### 4.2 底部筛选胶囊（BottomBar）
- 筛选胶囊扩展为 5 档位：`全部` | `支出` | `收入` | `转账` | `还款`；
- 小屏下维持靠左自适应避让右下角加号 FAB，单手可达。

---

## 5. 数据流、数据库与 API 演进方案

### 5.1 数据库结构升级（探针热迁移）

遵循轻量无侵入的探针热迁移约定（Probe-based Hot Migration），老数据库启动时自动平滑升级：

1. **`categories` 表增加 `type` 列**：
   ```sql
   ALTER TABLE categories ADD COLUMN type TEXT NOT NULL DEFAULT 'expense';
   ```
   - 初始化或老库迁移时：将「职业收入」分类更新为 `type = 'income'`；将「债务偿还」分类更新为 `type = 'system'`；其余默认保持 `type = 'expense'`。
2. **预置系统级转账分类与标签**：
   - 注入系统分类「账户转账」（`type = 'system'`）与系统标签「资金互转」；
   - 将分类 ID 与标签 ID 分别持久化至 `system_meta` 表（键：`system_category_transfer_id` 与 `system_tag_transfer_id`）；
   - 在 `settings.go` 中，增加针对转账系统分类/标签的不可变守卫（禁止修改名称、禁止删除），防止底层引用击穿。

### 5.2 后端交易校验契约（`transactions.go`）

扩展 `validateTransactionInput`：
- `type` 允许取值：`'expense'`、`'income'`、`'repayment'`、`'transfer'`；
- 当 `type == 'transfer'` 时：
  1. 金额必须为大于 0 的正数（`amount > 0`）；
  2. 目标账户（`payment_method_id`）必须为资产渠道（`type == 'asset'`）；
  3. 来源账户（`source_payment_method_id`）为必填项，且必须为资产渠道（`type == 'asset'`）；
  4. 来源账户与目标账户不能相同（`payment_method_id != source_payment_method_id`）；
  5. 自动绑定系统转账分类与标签 ID。

### 5.3 宏观统计核算规则（`stats.go`）

在宏观资产负债汇总计算中：
- 资产渠道余额公式更新：
  $$\text{RemainingBalance} = \text{InitialBalance} + \text{TxSum} - \text{SourceRepayments} - \text{SourceTransfers}$$
  其中：
  - `TxSum` 包含：存入该渠道的收入（`+`）、消费（`-`）、以及作为转账目标的转入金额（`+`）；
  - `SourceTransfers`：作为转出方转给其他资产渠道的金额累计；
  - `SourceRepayments`：作为还款转出方偿还信用卡的金额累计。
- 净资产会计恒等式：
  $$\text{NetAssets} = \text{TotalAssets} - \text{TotalLiabilities}$$
  转账发生时，转出方减 $X$，转入方加 $X$，总资产变动为 0，净资产绝对守恒。
- 周/月收支损益与趋势图：
  严格维持 `type = 'expense'` 与 `type = 'income'`，转账记录被完全隔离，不产生任何收支报表失真。

---

## 6. 实施路线与演进规划

<div style="border: 1px solid #d0d7de; border-radius: 8px; padding: 16px; margin: 16px 0; background: #ffffff;">
  <div style="font-weight: 600; font-size: 13px; color: #24292f; margin-bottom: 12px;">四阶段原子交付路线图</div>
  <div style="display: flex; flex-direction: column; gap: 8px; font-size: 12px;">
    <div style="border-left: 3px solid #0078d4; padding-left: 10px;">
      <strong>Phase 1：数据层与探针迁移</strong> —— categories 表增加 type 字段，预置系统转账分类/标签，持久化 system_meta 并构建 ID 级不可变守卫。
    </div>
    <div style="border-left: 3px solid #0078d4; padding-left: 10px;">
      <strong>Phase 2：服务端业务契约与统计核算</strong> —— 扩展 transactions 的 transfer 类型校验与双资产渠道规则，更新 stats 资产渠道核算公式与守恒验证。
    </div>
    <div style="border-left: 3px solid #0078d4; padding-left: 10px;">
      <strong>Phase 3：前端交互与移动端体验重塑</strong> —— 弹窗常驻 Footer 与 dvh 动态视口高度改造，分类与标签收支动态分离与内联流式展开，四段滑块与转账全链路接通。
    </div>
    <div style="border-left: 3px solid #0078d4; padding-left: 10px;">
      <strong>Phase 4：全流程回归与文档维护</strong> —— 单元测试与集成测试覆盖，验证移动端自适应与资产守恒，更新 Project.md 与阶段归档。
    </div>
  </div>
</div>
