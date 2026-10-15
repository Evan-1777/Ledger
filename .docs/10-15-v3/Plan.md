# Plan：收支统计与资产概览人民币符号去重

状态：DONE（2026-10-15，回归测试 `make test` 全绿：Go 测试 + 前端 tsc + node:test 38/38，format 套件 12/12 含新增 currency 用例）

## 背景与根因

- `web/src/lib/format.ts:37` 的 `formatMoney` 无条件返回 `${sign}¥${amountStr}`。
- `StatsPage.tsx` 与 `AssetsPage.tsx` 中约 16 处调用该函数，每处数字均携带 `¥`。
- 两页 Hero 已手写 `¥` 前缀 span（StatsPage.tsx:98、AssetsPage.tsx:75），紧跟其后的主数值再带 `¥`，形成「¥ +¥1,234.56」双符号缺陷。
- 结果：全页人民币符号大量重复，视觉噪声高。

## 方案

采用「每页 ¥ 仅锚定一次于 Hero」的金融看板惯例：

1. `formatMoney` 增加可选 `currency?: boolean`（默认 `true`），为 `false` 时省略 `¥`。默认值保证 StreamPage / SettingsPage / RecordModal / Charts 既有行为与测试契约零影响。
2. `StatsPage.tsx`：定义局部 `money()` 辅助（`sign: 'none'` + `currency: false`），替换全部 10 处调用；Hero 保留手写 `¥` span，消除双符号。
3. `AssetsPage.tsx`：`renderMoney` 默认合并 `currency: false`；Hero 保留手写 `¥` span。
4. `Charts.tsx`（DonutChart 仅 StatsPage 消费）：4 处调用追加 `currency: false`。
5. `web/test/format.test.ts` 补充 `currency: false` 用例。

## 风险与决策

- 不改后端；不改 `formatAmount`（流水页契约，测试覆盖中）。
- 默认 `currency: true` 保证既有调用方零回归。
- 驳回方案：改 `sign: 'none'` 语义顺带去掉 ¥ —— 隐式耦合，破坏既有语义且需改全部调用方，改动面更大。

## 验收标准

- 收支统计页与资产概览页各自仅在 Hero 出现一次 `¥`；其余数字无 `¥`。
- Hero 不再出现连续双 `¥`。
- StreamPage / SettingsPage / RecordModal 展示行为不变。
- `make test` 通过（Go + 前端 tsc + node:test）。
