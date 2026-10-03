# 个人记账系统：资产与负债体系功能设计规范

> **文档定位**：面向技术爱好者与个人开发者的轻量级财务模型设计规范。系统以 Microsoft Fluent 2 视觉语言与 Go + SQLite 单二进制架构为基础，规范资产渠道、负债渠道、资金流向代数模型与前端无噪呈现。

---

## 1. 业务心智与核心模型

在个人记账实践中，许多记录者常将“账户渠道”（如微信、支付宝、银行卡）仅视作打在支出记录上的一个纯文本标签，从而遗漏了对现实中**资产存量**与**债务敞口**的动态追踪。

本系统将既有的“支付途径（Payment Methods）”升级为具备完整财务语义的**一等公民渠道账户系统（Channel Account System）**，解耦为两大平行账户类型：**资产渠道（Asset Channel）**与**负债渠道（Liability Channel）**。

<div style="border: 1px solid #e1dfdd; border-radius: 8px; padding: 20px; margin: 18px 0; background: #faf9f8; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
  <div style="font-size: 14px; font-weight: 600; color: #201f1e; margin-bottom: 14px;">个人财务三大核心要素关系图</div>
  <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 14px;">
    <div style="background: #ffffff; border: 1px solid #edebe9; border-top: 3px solid #0078d4; border-radius: 6px; padding: 14px; box-shadow: 0 1.6px 3.6px rgba(0,0,0,0.04);">
      <div style="font-size: 13px; font-weight: 600; color: #0078d4;">资产渠道 (Assets)</div>
      <div style="font-size: 12px; color: #605e5c; margin-top: 6px; line-height: 1.5;">你实际拥有的真金白银。包含储蓄卡、微信零钱、支付宝余额、现金等。</div>
      <div style="margin-top: 10px; font-size: 11px; color: #323130; background: #f3f2f1; padding: 4px 8px; border-radius: 4px; font-family: monospace;">余额 = 初始余额 + 累计收入 - 累计支出</div>
    </div>
    <div style="background: #ffffff; border: 1px solid #edebe9; border-top: 3px solid #d83b01; border-radius: 6px; padding: 14px; box-shadow: 0 1.6px 3.6px rgba(0,0,0,0.04);">
      <div style="font-size: 13px; font-weight: 600; color: #d83b01;">负债渠道 (Liabilities)</div>
      <div style="font-size: 12px; color: #605e5c; margin-top: 6px; line-height: 1.5;">预支或借入的待还款项。包含信用卡、花呗、白条、消费分期、借款等。</div>
      <div style="margin-top: 10px; font-size: 11px; color: #323130; background: #f3f2f1; padding: 4px 8px; border-radius: 4px; font-family: monospace;">欠款 = 初始欠款 + 累计借出 - 累计还款</div>
    </div>
    <div style="background: #ffffff; border: 1px solid #edebe9; border-top: 3px solid #107c10; border-radius: 6px; padding: 14px; box-shadow: 0 1.6px 3.6px rgba(0,0,0,0.04);">
      <div style="font-size: 13px; font-weight: 600; color: #107c10;">净资产 (Net Worth)</div>
      <div style="font-size: 12px; color: #605e5c; margin-top: 6px; line-height: 1.5;">清偿全部债务后个人真正留存的财务身家。衡量财务健康度的根本指标。</div>
      <div style="margin-top: 10px; font-size: 11px; color: #323130; background: #f3f2f1; padding: 4px 8px; border-radius: 4px; font-family: monospace;">净资产 = 目前总资产 - 目前总负债</div>
    </div>
  </div>
</div>

---

## 2. 统一账户数学模型与资金流向

### 2.1 底账金额与符号代数公理

为了杜绝 JavaScript 与 Go 中浮点数运算产生的 `0.1 + 0.2 = 0.30000000000000004` 精度漂移，系统在数据库层一律使用**带符号 64 位整数分（`cents`）**进行持久化存储与底层累加，仅在向前端返回 JSON 响应时除以 100 转换为浮点元。

<div style="border: 1px solid #e1dfdd; border-radius: 8px; padding: 16px; margin: 16px 0; background: #ffffff; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
  <div style="font-size: 13px; font-weight: 600; color: #201f1e; margin-bottom: 12px;">账户模型字段与代数含义映射</div>
  <table style="width: 100%; border-collapse: collapse; font-size: 12px; text-align: left;">
    <thead>
      <tr style="border-bottom: 2px solid #edebe9; color: #605e5c;">
        <th style="padding: 8px 6px;">账户类型 (type)</th>
        <th style="padding: 8px 6px;">初始底账 (initial_balance_cents)</th>
        <th style="padding: 8px 6px;">信用额度 (credit_limit_cents)</th>
        <th style="padding: 8px 6px;">交易流累加 (Σ amount_cents)</th>
        <th style="padding: 8px 6px;">当前展示金额 (Display Amount)</th>
      </tr>
    </thead>
    <tbody>
      <tr style="border-bottom: 1px solid #f3f2f1;">
        <td style="padding: 8px 6px; font-weight: 600; color: #0078d4;">资产 (asset)</td>
        <td style="padding: 8px 6px;">初始存量（≥ 0 分）</td>
        <td style="padding: 8px 6px; color: #8a8886;">无（恒定 0）</td>
        <td style="padding: 8px 6px;">支出为负，收入为正</td>
        <td style="padding: 8px 6px; font-family: monospace; font-weight: 600;">剩余金额 = initial + Σ tx</td>
      </tr>
      <tr>
        <td style="padding: 8px 6px; font-weight: 600; color: #d83b01;">负债 (liability)</td>
        <td style="padding: 8px 6px;">初始欠款（≥ 0 分）</td>
        <td style="padding: 8px 6px;">授信上限（可选，0 表示不限）</td>
        <td style="padding: 8px 6px;">消费为负，还款为正</td>
        <td style="padding: 8px 6px; font-family: monospace; font-weight: 600;">当前欠款 = initial - Σ tx</td>
      </tr>
    </tbody>
  </table>
</div>

<details style="margin: 14px 0; border: 1px solid #edebe9; border-radius: 6px; padding: 10px 14px; background: #faf9f8;">
  <summary style="font-size: 12.5px; font-weight: 600; color: #323130; cursor: pointer;">爱好者批注：为什么负债的当前欠款计算公式是减去交易和（initial - Σ tx）？</summary>
  <div style="font-size: 12px; color: #605e5c; margin-top: 8px; line-height: 1.6;">
    在现有交易系统中，用户支出记录的 <code>amount_cents</code> 统一记录为负整数（例如刷信用卡消费 100 元，记录为 <code>-10000</code> 分）。<br />
    当我们在负债渠道消费 100 元时，欠款应当增加 100 元：<br />
    <code>欠款增加量 = -(-10000) = +10000 分（100 元）</code>。<br />
    反之，当用户向信用卡还款或充值时（若作为正向资金流入 <code>+10000</code> 分）：<br />
    <code>欠款减少量 = -(+10000) = -10000 分（-100 元）</code>。<br />
    这种数学对称性保证了整套系统无需特判正负符号，完全通过代数累加自然闭环。
  </div>
</details>

### 2.2 循环信用渠道的额度监控机制

对于诸如**信用卡**、**蚂蚁花呗**、**京东白条**等循环授信渠道，用户不仅关心当前欠了多少钱，还关心**剩余可用额度**以及**信用占用率**。

<div style="border: 1px solid #e1dfdd; border-radius: 8px; padding: 16px; margin: 16px 0; background: #ffffff; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
  <div style="font-size: 13px; font-weight: 600; color: #201f1e; margin-bottom: 12px;">循环信用额度状态流转模型</div>
  <div style="display: flex; flex-direction: column; gap: 8px; font-size: 12px;">
    <div style="display: flex; justify-content: space-between; align-items: center; background: #f3f2f1; padding: 10px 14px; border-radius: 6px;">
      <span style="font-weight: 600; color: #323130;">1. 设定总额度 (Credit Limit)</span>
      <span style="font-family: monospace; color: #605e5c;">例如：¥20,000.00</span>
    </div>
    <div style="display: flex; justify-content: space-between; align-items: center; background: #fdf3f2; border-left: 3px solid #d83b01; padding: 10px 14px; border-radius: 0 6px 6px 0;">
      <span style="font-weight: 600; color: #d83b01;">2. 发生消费支出 (Transactions &lt; 0)</span>
      <span style="font-family: monospace; color: #d83b01;">欠款 = 初始欠款 + 消费金额 (例如 ¥4,500.00)</span>
    </div>
    <div style="display: flex; justify-content: space-between; align-items: center; background: #f1f8f3; border-left: 3px solid #107c10; padding: 10px 14px; border-radius: 0 6px 6px 0;">
      <span style="font-weight: 600; color: #107c10;">3. 派生剩余可用额度 (Remaining Credit)</span>
      <span style="font-family: monospace; color: #107c10;">可用 = 总额度 - 当前欠款 (例如 ¥15,500.00)</span>
    </div>
  </div>
</div>

---

## 3. 统计看板与界面信息架构设计

根据项目工程纪律与 `production-frontend` 规范，界面面向最终使用，**默认用户已知功能入口，严禁出现任何说教式、解释性或指引性冗余文案**。所有排版严格对齐 Microsoft Fluent 2 视觉规范。

### 3.1 统计页（StatsPage）层级演进

统计界面分为两大视觉板块：
1. **顶层宏观资产/负债看板**：即时呈现净资产、总资产与总负债三核 KPI；
2. **渠道存量与负债明细矩阵**：呈现各个资产渠道的当前结余金额，以及负债渠道的待还欠款与额度监控条。

<div style="border: 1px solid #edebe9; border-radius: 12px; padding: 18px; margin: 18px 0; background: #faf9f8; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
  <div style="font-size: 13px; font-weight: 600; color: #201f1e; margin-bottom: 12px;">统计页面 Z 轴物理布局拓扑 (Layer 0 ~ Layer 2)</div>
  <div style="display: flex; flex-direction: column; gap: 12px;">
    <!-- 资产宏观看板 -->
    <div style="background: #ffffff; border: 1px solid #edebe9; border-radius: 8px; padding: 14px; box-shadow: 0 2px 4px rgba(0,0,0,0.03);">
      <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px;">
        <span style="font-size: 12px; font-weight: 600; color: #605e5c;">资产总览 KPI 矩阵 (Layer 1)</span>
      </div>
      <div style="display: grid; grid-template-columns: 1.2fr 1fr 1fr; gap: 10px;">
        <div style="background: #f8fbfd; border: 1px solid #c7e0f4; border-radius: 6px; padding: 10px;">
          <div style="font-size: 11px; color: #0078d4; font-weight: 600;">净资产</div>
          <div style="font-size: 18px; font-weight: 700; color: #201f1e; font-family: monospace; margin-top: 4px;">¥38,700.00</div>
        </div>
        <div style="background: #fdfcfb; border: 1px solid #edebe9; border-radius: 6px; padding: 10px;">
          <div style="font-size: 11px; color: #605e5c; font-weight: 600;">资产总额</div>
          <div style="font-size: 16px; font-weight: 700; color: #201f1e; font-family: monospace; margin-top: 4px;">¥45,200.00</div>
        </div>
        <div style="background: #fffdfd; border: 1px solid #edebe9; border-radius: 6px; padding: 10px;">
          <div style="font-size: 11px; color: #d83b01; font-weight: 600;">负债总额</div>
          <div style="font-size: 16px; font-weight: 700; color: #d83b01; font-family: monospace; margin-top: 4px;">¥6,500.00</div>
        </div>
      </div>
    </div>
    <!-- 渠道存量与负债详情 -->
    <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 12px;">
      <!-- 资产渠道明细 -->
      <div style="background: #ffffff; border: 1px solid #edebe9; border-radius: 8px; padding: 14px; box-shadow: 0 2px 4px rgba(0,0,0,0.03);">
        <div style="font-size: 12px; font-weight: 600; color: #201f1e; margin-bottom: 8px;">资产渠道余额</div>
        <div style="display: flex; flex-direction: column; gap: 8px; font-size: 12px;">
          <div style="display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #f3f2f1; padding-bottom: 6px;">
            <span style="color: #323130;">招商银行卡</span>
            <span style="font-family: monospace; font-weight: 600; color: #201f1e;">¥35,000.00</span>
          </div>
          <div style="display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #f3f2f1; padding-bottom: 6px;">
            <span style="color: #323130;">微信零钱</span>
            <span style="font-family: monospace; font-weight: 600; color: #201f1e;">¥10,200.00</span>
          </div>
        </div>
      </div>
      <!-- 负债渠道明细 -->
      <div style="background: #ffffff; border: 1px solid #edebe9; border-radius: 8px; padding: 14px; box-shadow: 0 2px 4px rgba(0,0,0,0.03);">
        <div style="font-size: 12px; font-weight: 600; color: #201f1e; margin-bottom: 8px;">负债渠道欠款</div>
        <div style="display: flex; flex-direction: column; gap: 10px; font-size: 12px;">
          <div>
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 4px;">
              <span style="color: #323130;">招行信用卡</span>
              <span style="font-family: monospace; font-weight: 600; color: #d83b01;">¥4,500.00</span>
            </div>
            <div style="height: 4px; background: #edebe9; border-radius: 2px; overflow: hidden;">
              <div style="height: 100%; width: 22.5%; background: #d83b01;"></div>
            </div>
            <div style="display: flex; justify-content: space-between; font-size: 10px; color: #8a8886; margin-top: 3px;">
              <span>剩余额度: ¥15,500.00</span>
              <span>额度: ¥20,000.00</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>

### 3.2 设置页（SettingsPage）渠道分段管理

在设置中心中，将既有的单一“支付途径”板块升级为**统一渠道管理工作台**：
- **双分类并列管理**：分为“资产渠道”与“负债渠道”独立网格容器，主次清晰；
- **轻量内联新增表单**：
  - 点击“新增资产渠道”：仅展开名称与可选初始余额输入框，就地保存；
  - 点击“新增负债渠道”：仅展开名称、可选初始欠款与可选信用额度输入框，就地保存；
- **编辑与删除守卫**：
  - 支持直接就地编辑渠道名称、底账与额度；
  - 删除操作严格受后端 409 Conflict 事务守卫（已有关联交易记录的渠道禁止删除，由前端弹出轻量 Toast 拦截提示）。

---

## 4. 数据库升级方案与接口契约规范

### 4.1 SQLite 数据库平滑演进与幂等升级

在 `internal/db/db.go` 中，升级既有的 `payment_methods` 表结构。考虑到用户可能基于已有老库运行，系统必须执行基于列探针（PRAGMA table_info）的自动平滑热迁移：

```sql
-- 若字段不存在，增量追加字段，默认保持向后兼容为 'asset'
ALTER TABLE payment_methods ADD COLUMN type TEXT NOT NULL DEFAULT 'asset';
ALTER TABLE payment_methods ADD COLUMN initial_balance_cents INTEGER NOT NULL DEFAULT 0;
ALTER TABLE payment_methods ADD COLUMN credit_limit_cents INTEGER NOT NULL DEFAULT 0;
```

<div style="border: 1px solid #d0d7de; border-radius: 6px; padding: 12px; margin: 14px 0; background: #f6f8fa; font-size: 12px;">
  <strong>数据库兼容性不变性（Invariant）保证</strong>：<br />
  1. <strong>迁移执行时机</strong>：列探测热迁移必须在 <code>system_meta</code> 的 <code>seed_initialized</code> 早退判断之前无条件执行，确保已有数据的生产老库启动时无缝补齐新列；<br />
  2. <strong>历史数据纳管</strong>：对于历史遗留数据，默认注入 <code>type = 'asset'</code> 且 <code>initial_balance_cents = 0</code>，历史交易流水无需任何数据回填即可正常计算，绝不产生破坏性断裂升级。
</div>

### 4.2 RESTful API 契约设计

#### 1. 渠道列表与新增更新端点

- `GET /api/payment-methods`
  - 返回完整渠道定义数组，包含 `type`（`asset` / `liability`）、`initial_balance`（元）、`credit_limit`（元）。
- `POST /api/payment-methods`
  - 请求体：
    ```json
    {
      "name": "招商信用卡",
      "type": "liability",
      "initial_balance": 0.0,
      "credit_limit": 20000.0,
      "sort_order": 5
    }
    ```
- `PUT /api/payment-methods/{id}`
  - 支持修改渠道名称、类型、底账与额度。
- `DELETE /api/payment-methods/{id}`
  - 若在 `transactions` 中存在引用，严格返回 `409 Conflict` 错误：`{"error": "该渠道已有关联账单，禁止删除"}`。

#### 2. 统计看板汇总端点扩充

- `GET /api/stats/summary`
  - 在既有周消费、月支出、分类下钻、趋势图基础上，扩展 `asset_summary` 聚合对象：
    ```json
    {
      "week_expense": 328.50,
      "month_expense": 4200.00,
      "last_month_expense": 3950.00,
      "month_income": 12500.00,
      "month_balance": 8300.00,
      "savings_rate": 66.4,
      "category_distribution": [...],
      "payment_distribution": [...],
      "monthly_trends": [...],
      "asset_summary": {
        "total_assets": 45200.00,
        "total_liabilities": 6500.00,
        "net_assets": 38700.00,
        "asset_channels": [
          {
            "id": 1,
            "name": "招商银行卡",
            "type": "asset",
            "remaining_balance": 35000.00,
            "initial_balance": 20000.00,
            "percentage": 77.4
          }
        ],
        "liability_channels": [
          {
            "id": 5,
            "name": "招行信用卡",
            "type": "liability",
            "current_debt": 4500.00,
            "initial_debt": 0.00,
            "credit_limit": 20000.00,
            "remaining_credit": 15500.00,
            "usage_rate": 22.5
          }
        ]
      }
    }
    ```

---

## 5. 边界场景与容错策略

<div style="border: 1px solid #e1dfdd; border-radius: 8px; padding: 16px; margin: 16px 0; background: #ffffff; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;">
  <div style="font-size: 13px; font-weight: 600; color: #201f1e; margin-bottom: 12px;">极端边界场景与系统响应规范</div>
  <table style="width: 100%; border-collapse: collapse; font-size: 12px; text-align: left;">
    <thead>
      <tr style="border-bottom: 2px solid #edebe9; color: #605e5c;">
        <th style="padding: 8px 6px;">边界场景</th>
        <th style="padding: 8px 6px;">潜在风险</th>
        <th style="padding: 8px 6px;">系统防御与规范响应</th>
      </tr>
    </thead>
    <tbody>
      <tr style="border-bottom: 1px solid #f3f2f1;">
        <td style="padding: 8px 6px; font-weight: 600;">资产渠道透支（余额为负）</td>
        <td style="padding: 8px 6px;">借记卡因未计初始底账导致余额跌破 0</td>
        <td style="padding: 8px 6px;">系统如实以负数呈现（如 <code>-¥150.00</code>），数值标红，不抛出异常阻断用户。</td>
      </tr>
      <tr style="border-bottom: 1px solid #f3f2f1;">
        <td style="padding: 8px 6px; font-weight: 600;">负债渠道超额（欠款超过额度）</td>
        <td style="padding: 8px 6px;">分期或超额刷卡导致已用欠款大于授信额度</td>
        <td style="padding: 8px 6px;">额度占用条宽度封顶 100%，剩余额度以负值清晰呈现，避免进度条溢出破卡。</td>
      </tr>
      <tr style="border-bottom: 1px solid #f3f2f1;">
        <td style="padding: 8px 6px; font-weight: 600;">删除已有流水的渠道</td>
        <td style="padding: 8px 6px;">破坏外键一致性导致孤儿交易产生</td>
        <td style="padding: 8px 6px;">数据库与应用层双重拦截，返回 409 Conflict，前端 Toast 友好提示。</td>
      </tr>
      <tr style="border-bottom: 1px solid #f3f2f1;">
        <td style="padding: 8px 6px; font-weight: 600;">渠道类型翻转（asset ↔ liability 切换）</td>
        <td style="padding: 8px 6px;">已有流水在类型切换后历史代数语义反转</td>
        <td style="padding: 8px 6px;">显式允许修改（个人记账工具保持轻量自由，由用户自担历史语义转变，避免过度复杂状态机锁死误操作纠正）。</td>
      </tr>
      <tr>
        <td style="padding: 8px 6px; font-weight: 600;">净资产为负（资不抵债）</td>
        <td style="padding: 8px 6px;">总负债大于总资产导致总净值为负</td>
        <td style="padding: 8px 6px;">净资产 KPI 卡片采用 <code>--color-expense-dark</code> 红色调警示，数值完整展示带符号金额。</td>
      </tr>
    </tbody>
  </table>
</div>

---

## 6. 修订日志与后续展望

- **v1.0 (2026-10-03)**：初版功能设计完成。确立资产/负债统一账户抽象、符号代数模型、SQLite 热迁移规范与无噪声前端看板方案。
- **后续规划 (Roadmap)**：在渠道系统成熟后，可正交引入“账户间划转（Transfer）”记账模式，支持储蓄卡直接对信用卡一键平账还款。
