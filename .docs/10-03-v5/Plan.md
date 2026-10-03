# Plan：前端美学缺陷修复与设计体系对齐

**状态**：DONE  
**日期**：2026-10-03  
**版本**：v1.0  
**回归测试结论**：全量测试通过（Go 11 个单元与集成测试全部 PASS，前端 Vite 编译与 tsc 类型检查 0 错误）

---

## 1. 背景与目标

针对前端审计报告（80 分）提出的实锤缺陷、设计规范红线与宣称偏差，依据 `engineering-discipline`（工程纪律）、`SCOPE.md`（个人轻量自用、消除冗余）与 `ponytail`（最短有效差分、拒绝未经请求的抽象）进行批判性吸收，制定整改实施方案。

<div style="margin: 16px 0; border: 1px solid #e2e8f0; border-radius: 8px; padding: 16px; background-color: #f8fafc; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;">
  <div style="font-weight: 600; font-size: 14px; margin-bottom: 12px; color: #0f172a;">审阅建议吸收与决策矩阵</div>
  <table style="width: 100%; border-collapse: collapse; font-size: 13px; text-align: left;">
    <thead>
      <tr style="border-bottom: 1px solid #cbd5e1; color: #475569;">
        <th style="padding: 6px 8px; width: 12%;">审计问题</th>
        <th style="padding: 6px 8px; width: 34%;">审阅建议</th>
        <th style="padding: 6px 8px; width: 14%;">处置方式</th>
        <th style="padding: 6px 8px; width: 40%;">工程纪律与决策依据</th>
      </tr>
    </thead>
    <tbody>
      <tr style="border-bottom: 1px solid #e2e8f0;">
        <td style="padding: 6px 8px; font-weight: 500;">1. 暗色令牌遗漏</td>
        <td style="padding: 6px 8px; color: #334155;">.dark-mode 补齐 brand-light/stroke 令牌</td>
        <td style="padding: 6px 8px;"><span style="display: inline-block; padding: 2px 6px; border-radius: 4px; background: #dcfce7; color: #166534; font-size: 11px; font-weight: 600;">完全采纳</span></td>
        <td style="padding: 6px 8px; color: #64748b;">实锤缺陷：解决深色模式下选中态刺眼亮蓝底色，治本于 CSS 根因处。</td>
      </tr>
      <tr style="border-bottom: 1px solid #e2e8f0;">
        <td style="padding: 6px 8px; font-weight: 500;">2. 负债进度条恒红</td>
        <td style="padding: 6px 8px; color: #334155;">按额度使用率分档（&lt;80% 灰阶，&ge;80% 红色）</td>
        <td style="padding: 6px 8px;"><span style="display: inline-block; padding: 2px 6px; border-radius: 4px; background: #dcfce7; color: #166534; font-size: 11px; font-weight: 600;">完全采纳</span></td>
        <td style="padding: 6px 8px; color: #64748b;">契约对齐：恢复 Project.md 已记录的“语义色彩映射额度使用率”决策。</td>
      </tr>
      <tr style="border-bottom: 1px solid #e2e8f0;">
        <td style="padding: 6px 8px; font-weight: 500;">3. 悬浮层无材质</td>
        <td style="padding: 6px 8px; color: #334155;">Navbar/BottomBar 增加 backdrop-blur 与半透背景</td>
        <td style="padding: 6px 8px;"><span style="display: inline-block; padding: 2px 6px; border-radius: 4px; background: #dcfce7; color: #166534; font-size: 11px; font-weight: 600;">完全采纳</span></td>
        <td style="padding: 6px 8px; color: #64748b;">规范对齐：建立 Layer 2 悬浮物理材质层级，消除滚动重叠生硬感。</td>
      </tr>
      <tr style="border-bottom: 1px solid #e2e8f0;">
        <td style="padding: 6px 8px; font-weight: 500;">4. 令牌体系定性</td>
        <td style="padding: 6px 8px; color: #334155;">二选一：改文档宣称 或 全量切换为 Fluent 纯灰</td>
        <td style="padding: 6px 8px;"><span style="display: inline-block; padding: 2px 6px; border-radius: 4px; background: #e0e7ff; color: #3730a3; font-size: 11px; font-weight: 600;">采纳改文档</span></td>
        <td style="padding: 6px 8px; color: #64748b;"><b>驳回全量重写</b>：现状 Slate 色阶美观自洽，全量改纯灰属过度重构；修正文档定位为混合体系（Fluent-Slate Hybrid）符合最短有效差分。</td>
      </tr>
      <tr style="border-bottom: 1px solid #e2e8f0;">
        <td style="padding: 6px 8px; font-weight: 500;">5. 字号碎片化</td>
        <td style="padding: 6px 8px; color: #334155;">全站强制统一为 11/12/14/16 四档</td>
        <td style="padding: 6px 8px;"><span style="display: inline-block; padding: 2px 6px; border-radius: 4px; background: #fef3c7; color: #92400e; font-size: 11px; font-weight: 600;">克制收敛</span></td>
        <td style="padding: 6px 8px; color: #64748b;">归一化 12.5px/13.5px 半档字号，但严格保持 320px 移动端单行不溢出契约，防过度翻新。</td>
      </tr>
      <tr style="border-bottom: 1px solid #e2e8f0;">
        <td style="padding: 6px 8px; font-weight: 500;">6. py-0.2 笔误</td>
        <td style="padding: 6px 8px; color: #334155;">修正为 py-0.5</td>
        <td style="padding: 6px 8px;"><span style="display: inline-block; padding: 2px 6px; border-radius: 4px; background: #dcfce7; color: #166534; font-size: 11px; font-weight: 600;">完全采纳</span></td>
        <td style="padding: 6px 8px; color: #64748b;">笔误修正：消除 0.8px 异常贴边内边距。</td>
      </tr>
      <tr style="border-bottom: 1px solid #e2e8f0;">
        <td style="padding: 6px 8px; font-weight: 500;">7. 废话副标题</td>
        <td style="padding: 6px 8px; color: #334155;">移除自然周统计/当月累计支出/上一自然月全量</td>
        <td style="padding: 6px 8px;"><span style="display: inline-block; padding: 2px 6px; border-radius: 4px; background: #dcfce7; color: #166534; font-size: 11px; font-weight: 600;">完全采纳</span></td>
        <td style="padding: 6px 8px; color: #64748b;">界面去噪：主标题已完整表意，移除废话使收支卡与宏观卡排版高度对称。</td>
      </tr>
      <tr style="border-bottom: 1px solid #e2e8f0;">
        <td style="padding: 6px 8px; font-weight: 500;">8. 触控目标偏小</td>
        <td style="padding: 6px 8px; color: #334155;">移动端编辑/删除按钮从 28px 提升至 32px</td>
        <td style="padding: 6px 8px;"><span style="display: inline-block; padding: 2px 6px; border-radius: 4px; background: #dcfce7; color: #166534; font-size: 11px; font-weight: 600;">完全采纳</span></td>
        <td style="padding: 6px 8px; color: #64748b;">可达性改善：w-8 h-8 满足小屏防误触规范。</td>
      </tr>
      <tr style="border-bottom: 1px solid #e2e8f0;">
        <td style="padding: 6px 8px; font-weight: 500;">9. 键盘焦点态</td>
        <td style="padding: 6px 8px; color: #334155;">补充 focus-visible 焦点高亮环</td>
        <td style="padding: 6px 8px;"><span style="display: inline-block; padding: 2px 6px; border-radius: 4px; background: #fef3c7; color: #92400e; font-size: 11px; font-weight: 600;">聚焦主线</span></td>
        <td style="padding: 6px 8px; color: #64748b;"><b>拒绝全站泛滥</b>：聚焦 Navbar 胶囊、BottomBar 筛选、FAB 等核心导航交互，不向全量边缘小图标蔓延。</td>
      </tr>
      <tr style="border-bottom: 1px solid #e2e8f0;">
        <td style="padding: 6px 8px; font-weight: 500;">10. 抽屉无入场动效</td>
        <td style="padding: 6px 8px; color: #334155;">SettingsPage Layer 3 抽屉面板平滑从右滑入</td>
        <td style="padding: 6px 8px;"><span style="display: inline-block; padding: 2px 6px; border-radius: 4px; background: #dcfce7; color: #166534; font-size: 11px; font-weight: 600;">完全采纳</span></td>
        <td style="padding: 6px 8px; color: #64748b;">微动效补全：CSS translateX 硬件加速，消除面板瞬现生硬感。</td>
      </tr>
      <tr style="border-bottom: 1px solid #e2e8f0;">
        <td style="padding: 6px 8px; font-weight: 500;">11. 残留代码清理</td>
        <td style="padding: 6px 8px; color: #334155;">清理 index.html body 死代码与未用 ChevronRightIcon</td>
        <td style="padding: 6px 8px;"><span style="display: inline-block; padding: 2px 6px; border-radius: 4px; background: #dcfce7; color: #166534; font-size: 11px; font-weight: 600;">完全采纳</span></td>
        <td style="padding: 6px 8px; color: #64748b;">死代码清理：消除无效覆盖与零引用图标。</td>
      </tr>
      <tr>
        <td style="padding: 6px 8px; font-weight: 500;">12. 硬编码 rgba 绕过</td>
        <td style="padding: 6px 8px; color: #334155;">还款滑块与标签纳入 brand-light/stroke 体系</td>
        <td style="padding: 6px 8px;"><span style="display: inline-block; padding: 2px 6px; border-radius: 4px; background: #dcfce7; color: #166534; font-size: 11px; font-weight: 600;">完全采纳</span></td>
        <td style="padding: 6px 8px; color: #64748b;">令牌归位：消除散落 rgba，与暗色模式统一联动。</td>
      </tr>
    </tbody>
  </table>
</div>

---

## 2. 阶段划分

<div style="margin: 16px 0; border: 1px solid #e2e8f0; border-radius: 8px; padding: 16px; background-color: #ffffff;">
  <div style="font-weight: 600; font-size: 13px; color: #0f172a; margin-bottom: 8px;">阶段演进流水线</div>
  <div style="display: flex; align-items: center; justify-content: space-between; gap: 8px; flex-wrap: wrap;">
    <div style="flex: 1; min-width: 140px; padding: 10px; background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 6px; text-align: center;">
      <div style="font-size: 11px; color: #64748b; font-weight: 600;">PHASE 1</div>
      <div style="font-size: 12px; color: #0f172a; font-weight: 600; margin-top: 4px;">令牌适配与物理材质</div>
    </div>
    <div style="color: #94a3b8; font-weight: bold;">&rarr;</div>
    <div style="flex: 1; min-width: 140px; padding: 10px; background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 6px; text-align: center;">
      <div style="font-size: 11px; color: #64748b; font-weight: 600;">PHASE 2</div>
      <div style="font-size: 12px; color: #0f172a; font-weight: 600; margin-top: 4px;">排版去噪与状态映射</div>
    </div>
    <div style="color: #94a3b8; font-weight: bold;">&rarr;</div>
    <div style="flex: 1; min-width: 140px; padding: 10px; background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 6px; text-align: center;">
      <div style="font-size: 11px; color: #64748b; font-weight: 600;">PHASE 3</div>
      <div style="font-size: 12px; color: #0f172a; font-weight: 600; margin-top: 4px;">触达可达性与动效</div>
    </div>
    <div style="color: #94a3b8; font-weight: bold;">&rarr;</div>
    <div style="flex: 1; min-width: 140px; padding: 10px; background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 6px; text-align: center;">
      <div style="font-size: 11px; color: #64748b; font-weight: 600;">PHASE 4</div>
      <div style="font-size: 12px; color: #0f172a; font-weight: 600; margin-top: 4px;">构建验证与文档校准</div>
    </div>
  </div>
</div>

### Phase 1：视觉令牌暗色适配与物理材质层级重塑

| 项目 | 内容 |
|---|---|
| **输入** | `web/src/index.css`、`RecordModal.tsx`、`StreamPage.tsx`、`Navbar.tsx`、`BottomBar.tsx` |
| **输出** | 暗色品牌令牌补齐、还款滑块与标签令牌归位、Navbar 与 BottomBar 毛玻璃层级材质 |
| **验收标准** | 暗黑模式下渠道与标签选中态背景转为半透深蓝（rgba(0,120,212,0.16)），无刺眼浅蓝高亮；还款滑块与标签使用令牌驱动；Navbar 滚动悬浮半透明模糊生效 |

### Phase 2：排版去噪、状态映射与细节缺陷修复

| 项目 | 内容 |
|---|---|
| **输入** | `web/src/pages/StatsPage.tsx`、`web/src/components/BottomBar.tsx`、`web/src/components/Toast.tsx`、`web/index.html`、`web/src/components/Icons.tsx` |
| **输出** | 负债进度条额度使用率颜色分档、py-0.2 笔误修正、KPI 卡片废话副标题移除、BottomBar 筛选项 map 收敛、残留死代码清理 |
| **验收标准** | 负债渠道使用率 &lt; 80% 渲染中性灰导轨、&ge; 80% 渲染赤字警示红；储蓄率徽章内边距自然紧凑；KPI 卡片无废话副标题；`index.html` body 无冗余类名 |

### Phase 3：触达可达性与动效补全

| 项目 | 内容 |
|---|---|
| **输入** | `web/src/pages/StreamPage.tsx`、`web/src/components/Navbar.tsx`、`web/src/components/BottomBar.tsx`、`web/src/pages/SettingsPage.tsx`、`web/src/index.css` |
| **输出** | 流水移动端操作按钮增大至 32px、关键导航按钮键盘焦点态（focus-visible）、设置页细分标签抽屉从右滑入动画 |
| **验收标准** | 移动端编辑与删除按钮具有 32px 舒适触控面；Tab 键导航时胶囊项具备品牌色焦点环；展开细分标签抽屉时平滑平移滑入无闪烁 |

### Phase 4：全流程编译验证与设计规范文档校准

| 项目 | 内容 |
|---|---|
| **输入** | 全量修改后代码、`.docs/Project.md` |
| **输出** | 前端 Vite 静态资源编译产物、TypeScript 严格类型检查、后端端点回归测试、Project.md 设计体系定性同步 |
| **验收标准** | `make test` 全量通过；`npm run build` 成功无告警；`Project.md` 约束与宣称如实更新为 Fluent-Slate Hybrid 规范 |

---

## 3. 架构与设计决策

| 决策项 | 选择 | 理由 | 替代方案（为何不选） |
|---|---|---|---|
| **暗色品牌色令牌** | `rgba(0,120,212,0.16)` 与 `rgba(71,158,245,0.4)` | 与现有的 income/expense 暗色 rgba 方案完全对齐，模型对称且自洽 | 引入复杂十六进制色板（增加维护成本与不必要的抽象） |
| **设计体系定性** | 修正 Project.md 为“Fluent 品牌蓝 + Tailwind Slate 精细灰混合体系” | 最短有效差分；Slate 色调与深色画布自洽现代，修改文档消除名实不符根因 | 全量重写为 Fluent 纯灰与尖锐圆角（违背 YAGNI，破坏现有视觉体验，极易造成大面积回归） |
| **负债进度条映射** | 以 80% 额度使用率为界，&lt;80% 中性灰，&ge;80% 赤字红 | 严格恢复 2026-10-03 既有决策契约，消除低使用率无谓焦虑 | 连续渐变色阶计算（增加代码复杂度与计算开销，信息量反降） |
| **半档字号收敛** | 仅收敛 12.5px/13.5px 到 text-xs (12px) / text-sm (14px) / 13px | 消除手工微调带来的漂移，且严格保证 320px 移动端单行自适应排开 | 全局机械替换为 Fluent 5 档 Type Ramp（易击穿移动端狭窄视口导致换行溢出） |
| **键盘可达性范围** | 聚焦 Navbar 胶囊、BottomBar 筛选、FAB 与模态核心按钮 | 聚焦核心键盘导航路径，改动克制有效 | 全站所有微小标签与边缘图标全量注入 focus-visible（产生海量冗余 diff，增加样式污染风险） |
| **同构结构收敛** | 仅对 BottomBar 4 按钮用 map 局部收敛 | 消除 30 行平铺模板重复，收益明显且零风险 | 对 RecordModal 渠道按钮与 SettingsPage 双列表单强行抽象公共组件（违背 YAGNI，各表单存在正交业务差异） |

---

## 4. 风险清单

| 风险 | 等级 | 缓解措施 |
|---|---|---|
| 悬浮层 `backdrop-blur-md` 在不支持的浏览器中退化 | 🟢 低 | 保留半透明背景底色（通过 `color-mix` 或半透明类），退化时依然保持高对比度与可读性 |
| 移动端 32px 按钮在紧凑屏幕下导致操作区占宽过大 | 🟢 低 | 仅针对移动端加大，桌面端维持紧凑 `sm:w-7 sm:h-7`，保证桌面空间排版紧致 |
| 暗黑模式下品牌半透边框与文字对比度不足 | 🟢 低 | 使用 0.4 透明度提亮边框并继承高对比度品牌高亮文字，符合 WCAG AA 标准 |

---

## 5. Phase 依赖关系

```
Phase 1 ──→ Phase 2 ──→ Phase 3 ──→ Phase 4
```

各阶段依次递进，聚焦不同层次问题，最终在 Phase 4 完成全流程编译与文档同步。

---

## 6. Subagent 协同规划

对照三维效益模型（任务复杂度、上下文关联度、经济与时间效益）评估：

| 阶段 | 上下文依赖 | 并行收益 | 执行主体 | 决策理由 |
|---|---|---|---|---|
| Phase 1：令牌与物理材质 | 强（涉及全局 CSS 令牌与组件样式对齐） | 低（串行基础） | 主线 | 差分小（约 15 行），主线连续修改无冷加载重载开销 |
| Phase 2：排版去噪与状态 | 强（涉及 StatsPage 与业务语义对齐） | 低（依赖前序状态） | 主线 | 局部精准修改，主线可直接完成 |
| Phase 3：触达与动效 | 强（涉及响应式视口验证与动画衔接） | 低（代码联动） | 主线 | 跨组件微调，主线更具全局把控度 |
| Phase 4：验证与文档校准 | 强（涉及 Project.md 决策落盘与全量测试） | 低（收束验收） | 主线 | 统一执行并推进归档 |

> **协同结论**：本次改动属于高度内聚的前端细节重塑与文档校准，总修改行数约 60-80 行，强依赖上下文且跨文件交互紧密。全部保留由主线串行推进，避免子 Agent 隔离加载上下文带来的额外消耗。

---

> ### Task 拆解预览
>
> 详见 `Tasks.md`，共划分为 11 个原子化 Task，涵盖令牌暗色补齐、材质升级、进度条语义分档、去噪与动效补全。
