# Plan：移动端通知修复与转账手续费可选闭环

**状态**：DONE  
**日期**：2026-10-05  
**完成日期**：2026-10-05  
**版本**：v1.1（吸收外部评审反馈，裁定纯资产调整口径，修正函数契约与定位方案）  
**设计哲学**：Microsoft Fluent 2（纯净光感、四层 Z 轴材质、精细灰阶 Slate、克制去噪、极简渐进披露）

---

## 1. 背景与目标

本次迭代聚焦解决移动端界面显示缺陷与转账业务模型演进：

1. **移动端通知提示裁剪 Bug 修复**：用户反馈在移动端操作后，变动弹窗提示（Toast）左侧文本被屏幕左边缘截断（仅露"...账成功"）。
   - **根因确认**：[Toast.tsx](file:///home/dev/projects/Ledger/web/src/components/Toast.tsx#L18) 使用了 `fixed top-20 right-8 max-w-sm w-full`。在窄屏设备（如 360px–392px 移动端）中，`w-full` 将容器宽度拉至 100vw，搭配 `right: 2rem`（32px）的右侧绝对偏移，在 CSS 绝对定位盒模型计算下导致左侧边界落入负坐标（`-32px`），首字「记」及左侧边框被硬性挤出屏幕。
   - **解法**：采用 `fixed top-20 left-1/2 -translate-x-1/2 sm:translate-x-0 sm:left-auto sm:right-8 z-[2000] flex flex-col gap-2 w-[calc(100vw-32px)] sm:w-full max-w-sm`。移动端利用水平居中与 16px 视口安全边距彻底消除偏移截断；桌面端保持右上锚定；保留 `top-20`（80px）与 60px 顶栏维持 20px 安全间距。

2. **转账手续费可选项扩展（纯资产调整闭环）**：真实生活中银行卡跨行或提现转账可能产生小额手续费。
   - **资深用户去噪原则**：默认状态不常驻手续费输入框，不呈现任何操作指引文案；仅在「账单金额」卡片标题栏右上角保留微型文本触发 `+ 手续费`，点开即内联展开输入框，支持一键清除关闭。
   - **核算口径裁定（纯资产调整）**：遵循系统既有收支隔离不变式（`Project.md:138`），转账不计入收支损益表（周/月/上月/趋势/分类分布）。手续费作为 `transactions.fee_cents` 一等公民纳管，转出资产渠道结余扣除 `本金 + 手续费`，转入资产渠道增加 `本金`，净资产核算精确自然扣减 `手续费`，杜绝孤儿支出记录与分类分布百分比失真。

<div style="border: 1px solid #d0d7de; border-radius: 8px; padding: 16px; margin: 16px 0; background: #ffffff; font-family: sans-serif;">
  <div style="font-weight: 600; margin-bottom: 12px; color: #24292f;">迭代核心目标架构图</div>
  <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 16px;">
    <div style="border: 1px solid #e1e4e8; border-radius: 6px; padding: 12px; background: #f6f8fa;">
      <div style="font-weight: 600; color: #0969da; font-size: 13px; margin-bottom: 6px;">1. 移动端 Toast 视口自适应</div>
      <div style="font-size: 12px; color: #57606a; line-height: 1.5;">
        消除 <code>right-8 w-full</code> 负坐标越界根因。<br/>
        移动端：<code>left-1/2 -translate-x-1/2 w-[calc(100vw-32px)]</code> 绝对居中安全留白。<br/>
        桌面端：<code>sm:left-auto sm:right-8 sm:translate-x-0</code> 精确右上锚定。
      </div>
    </div>
    <div style="border: 1px solid #e1e4e8; border-radius: 6px; padding: 12px; background: #f6f8fa;">
      <div style="font-weight: 600; color: #1a7f37; font-size: 13px; margin-bottom: 6px;">2. 转账手续费纯资产核算</div>
      <div style="font-size: 12px; color: #57606a; line-height: 1.5;">
        数据层：<code>transactions.fee_cents</code> 探针热迁移。<br/>
        核算层：转出资产 <code>source_transfer_sum = amount + fee</code>，净资产守恒。<br/>
        损益层：严格隔离周/月收支与分类分布，保持报表与断言严格对账。
      </div>
    </div>
  </div>
</div>

---

## 2. 阶段划分

### Phase 1：移动端变动通知 (Toast) 视口自适应修复

| 项目 | 内容 |
|------|------|
| **输入** | `web/src/components/Toast.tsx` |
| **输出** | 响应式自适应居中与桌面端右上锚定的 Toast 容器 |
| **验收标准** | 在 320px–414px 窄屏移动视口与桌面视口下，Toast 完全处于可视区域内，左右无溢出截断，与 Navbar 保持安全间隙，淡入动效与关闭按钮交互正常 |

### Phase 2：转账手续费数据模型与服务端核算闭环

| 项目 | 内容 |
|------|------|
| **输入** | `internal/db/db.go`, `internal/server/transactions.go`, `internal/server/stats.go` |
| **输出** | SQLite 探针热迁移、API 契约扩展与纯资产守恒核算 |
| **验收标准** | `transactions` 增加 `fee_cents`（默认 0，老库零迁移成本）；转账创建/更新支持校验 `fee >= 0`；资产统计中转出方资产准确扣除本金与手续费（`source_transfer_sum = amount_cents + fee_cents`），净资产扣减手续费；月度收支与分类分布保持对转账完全隔离；全量 Go 测试用例通过 |

### Phase 3：前端记账模态窗转账手续费交互与流水展示

| 项目 | 内容 |
|------|------|
| **输入** | `web/src/lib/api.ts`, `web/src/App.tsx`, `web/src/components/RecordModal.tsx`, `web/src/pages/streamUtils.ts` |
| **输出** | 模态窗金额卡片 Header 重构与内联展开、类型契约对齐、流水明细手续费呈现与自动化单测 |
| **验收标准** | 方案 A 落地：金额卡片标题栏右上角嵌入微型 `+ 手续费`，展开后可录入手续费，收起/清空传入 0；三处 `onSubmit` 载荷签名（api/RecordModal/App）统一追加 `fee?: number`；流水元信息展示 `手续费 ¥X.XX`；Node 原生单测全绿 |

### Phase 4：全链路回归验证与工程文档维护

| 项目 | 内容 |
|------|------|
| **输入** | 前序阶段修改之代码库与文档 |
| **输出** | `make test` 构建验证产物与更新后的 `.docs/Project.md` |
| **验收标准** | `make test`（Go 测试 + 前端 tsc）零警告零报错；`Project.md` 记录本次架构演进、探针迁移与纯资产核算决策 |

---

## 3. 架构决策与方案比对

<div style="border: 1px solid #d0d7de; border-radius: 8px; padding: 16px; margin: 16px 0; background: #ffffff; font-family: sans-serif;">
  <div style="font-weight: 600; margin-bottom: 12px; color: #24292f;">前端界面设计方案比对矩阵 (Frontend Variants)</div>
  <table style="width: 100%; border-collapse: collapse; font-size: 12px; text-align: left;">
    <thead>
      <tr style="border-bottom: 2px solid #d0d7de; background: #f6f8fa;">
        <th style="padding: 8px 12px;">对比维度</th>
        <th style="padding: 8px 12px; color: #0969da;">方案 A（已选定）：金额卡片内嵌式</th>
        <th style="padding: 8px 12px; color: #57606a;">方案 B：账户流向下挂独立行</th>
      </tr>
    </thead>
    <tbody>
      <tr style="border-bottom: 1px solid #e1e4e8;">
        <td style="padding: 8px 12px; font-weight: 600;">入口位置</td>
        <td style="padding: 8px 12px;">位于「账单金额」卡片标题栏右上角（重构为 flex 布局）</td>
        <td style="padding: 8px 12px;">位于「转入资产账户」网格下方右侧</td>
      </tr>
      <tr style="border-bottom: 1px solid #e1e4e8;">
        <td style="padding: 8px 12px; font-weight: 600;">收起态视觉干扰</td>
        <td style="padding: 8px 12px;">极低（复用金额卡片 Header 行高，0 额外垂直纵深）</td>
        <td style="padding: 8px 12px;">较低（独占一行微型文本按钮）</td>
      </tr>
      <tr style="border-bottom: 1px solid #e1e4e8;">
        <td style="padding: 8px 12px; font-weight: 600;">展开态信息聚集</td>
        <td style="padding: 8px 12px;">高（转账本金与附加费用于同一金额卡片内核算，心智模型统一）</td>
        <td style="padding: 8px 12px;">中（本金与手续费被用途与账户选择截断，上下割裂）</td>
      </tr>
      <tr>
        <td style="padding: 8px 12px; font-weight: 600;">Demo 静态原型</td>
        <td style="padding: 8px 12px;"><code>temp/transfer-fee-variant-a.html</code></td>
        <td style="padding: 8px 12px;"><code>temp/transfer-fee-variant-b.html</code></td>
      </tr>
    </tbody>
  </table>
</div>

### 关键系统决策项

| 决策项 | 选择 | 理由 | 替代方案（为何不选） |
|--------|------|------|----------------------|
| **核算口径（已裁定假设）** | 纯资产调整（Pure Asset Adjustment） | **核心理由**：契合转账本质与既有 P&L 隔离不变式（`Project.md:138`），转出资产准确扣减本金与费用，净资产精确减少手续费；避免分类分布分母被撑大导致的百分比失真与断言反转。<br/>**产品代价披露**：在纯资产口径下，净资产减少 `fee`，而月度支出与结余（P&L）不计入转账，二者在当期存在微小发散（即当期净资产变动 = 月结余 - 转账手续费合计）。此为权衡后确定的规范设计，彻底保护分类看板不被系统转账分类污染。 | 计入月度支出：破坏收支与转账隔离契约，导致分类分布无对应分类承载手续费、百分比失真，且需推翻既有测试断言 |
| **手续费数据模型** | `transactions.fee_cents` 单笔事务一等公民 | 溯源根因与 SSOT 契约。转账与手续费原子存取，编辑、删除与回溯自然联动 | 双记录模式（1转账+1支出）：产生悬空孤儿支出记录，编辑转账时无法联动修改手续费 |
| **Toast 居中方案** | `left-1/2 -translate-x-1/2` 搭配 `w-[calc(100vw-32px)]` | 数学上绝对可靠的视口居中与 16px 安全留白，彻底拔除单侧固定偏移导致的负坐标越界根因 | 单纯设置 `left-4 right-4 mx-auto`（在非绝对受限视口下受 LTR 限制呈现左偏） |

---

## 4. 风险清单

| 风险 | 等级 | 缓解措施 |
|------|------|----------|
| 老旧数据库升级缺列报错 | 🟢 低 | `migrateTransactionsColumns` 使用 `PRAGMA table_info` 热探针，幂等按需 `ALTER TABLE` |
| 转账手续费输入负数或非法字符串 | 🟡 中 | 服务端与前端双层校验 `fee >= 0`，非数字自动拦截并回显错误提示 |
| 历史转账账单在编辑时手续费丢失 | 🟢 低 | `api.ts` 与 `RecordModal` 在 `initialTransaction` 存在时自动回填已有 `fee` |

---

## 5. Phase 依赖关系

<div style="border: 1px solid #d0d7de; border-radius: 8px; padding: 16px; margin: 16px 0; background: #ffffff; font-family: sans-serif;">
  <div style="font-weight: 600; margin-bottom: 12px; color: #24292f;">执行阶段流转拓扑</div>
  <div style="display: flex; align-items: center; gap: 8px; flex-wrap: wrap; font-size: 12px;">
    <div style="border: 1px solid #0969da; background: #ddf4ff; color: #0969da; padding: 6px 10px; border-radius: 6px; font-weight: 600;">Phase 1: Toast 修复</div>
    <div style="color: #57606a;">➔</div>
    <div style="border: 1px solid #1a7f37; background: #dafbe1; color: #1a7f37; padding: 6px 10px; border-radius: 6px; font-weight: 600;">Phase 2: 服务端模型与核算</div>
    <div style="color: #57606a;">➔</div>
    <div style="border: 1px solid #9a6700; background: #fff8c5; color: #9a6700; padding: 6px 10px; border-radius: 6px; font-weight: 600;">Phase 3: 前端交互与流水</div>
    <div style="color: #57606a;">➔</div>
    <div style="border: 1px solid #8250df; background: #fbefff; color: #8250df; padding: 6px 10px; border-radius: 6px; font-weight: 600;">Phase 4: 回归与文档维护</div>
  </div>
</div>

---

## 6. Subagent 协同规划

对照三维效益模型（任务复杂度、上下文关联度、经济与时间效益）评估本阶段委托需求：

| 阶段 | 上下文依赖 | 并行收益 | 执行主体 | 决策理由 |
|------|-----------|---------|----------|----------|
| **Phase 1：Toast 修复** | 弱（单个 UI 组件的样式微调） | 无（单文件 1 行差分） | 主线 | 最短有效差分，主线修改即时生效，无子会话重载开销 |
| **Phase 2：服务端模型与核算** | 强（涉及 SQLite 事务、SQL 聚合与财务守恒） | 无（需与 Phase 3 紧密前后衔接） | 主线 | 保证热迁移与统计逻辑一致性，主线闭环无通信损耗 |
| **Phase 3：前端交互与流水** | 强（依赖 Phase 2 接口契约，涉及 Fluent 模态交互） | 无（依赖 Phase 2 完成） | 主线 | 主线处理前端状态流转最直接，且便于本地热重载调试 |
| **Phase 4：回归与文档维护** | 弱（只读验证全库编译与文档记录） | 低 | 主线 | 仅执行 `make test` 与 `Project.md` 增量更新，主线极速完成，派发 Subagent 启动开销反而大于任务本身 |

> **协同结论**：本任务涉及核心数据模型热迁移、全链路守恒核算与精准移动端视口适配，上下文紧密耦合且链路清晰，全部保留由主线高效完成。

---

> ### Task 拆解预览
>
> 详见根目录 `Tasks.md`。总计拆解为 11 项原子 Task，各 Task 具备可机械验证之验收标准。

---

## 7. 交付与回归结论

- **完成日期**：2026-10-05
- **回归测试结论**：
  1. 后端：`go test -v ./...` 全绿（涵盖 DB 探针热迁移、设置守卫、转账全流程、手续费纯资产核算与收支隔离）；
  2. 前端：`tsc -b --noEmit` 零类型警告，`node --test test/*.test.ts` 19 项纯函数测试 100% 通过（涵盖手续费元信息构建）；
  3. 整体构建：`make test` 退出码 0，端到端业务闭环正常。

