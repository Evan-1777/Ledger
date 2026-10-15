# Tasks：收支统计与资产概览人民币符号去重

状态：DONE（2026-10-15，回归测试 `make test` 全绿）

| 编号 | 状态 | 执行主体 | 描述 | 验收标准 |
|------|------|---------|------|---------|
| T1 | DONE | 主线 | `web/src/lib/format.ts`：`formatMoney` 的 opts 增加 `currency?: boolean`（默认 `true`），为 `false` 时返回值不含 `¥` | 既有调用不传该参数时行为不变；`currency: false` 输出无 `¥` |
| T2 | DONE | 主线 | `web/test/format.test.ts`：补充 `currency: false` 用例（正数 / 负数 / 零） | 用例覆盖三种取值且通过 |
| T3 | DONE | 主线 | `StatsPage.tsx`：新增局部 `money()` 辅助（`sign:'none'` + `currency:false`），替换全部 formatMoney 调用；Hero 手写 `¥` span 保留 | 页面仅 Hero 出现一次 `¥`；双符号消除 |
| T4 | DONE | 主线 | `AssetsPage.tsx`：`renderMoney` 默认合并 `currency: false`；Hero 手写 `¥` span 保留 | 页面仅 Hero 出现一次 `¥` |
| T5 | DONE | 主线 | `Charts.tsx` DonutChart：4 处 formatMoney 追加 `currency: false` | 环形图面板内无 `¥` |
| T6 | DONE | 主线 | 执行 `make test` 并同步 Project.md 决策记录 | 测试全绿；Project.md 含本次变更记录 |

依赖：T3/T4/T5 依赖 T1；T6 依赖 T1–T5。
