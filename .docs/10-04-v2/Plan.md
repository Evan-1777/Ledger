# Plan：复审问题修复与移动端边界适配 (Quick)

**状态**：DONE  
**日期**：2026-10-04  
**版本**：v1.0  
**回归测试结论**：全部通过（`make test` 全绿，前后端测试与静态检查 100% 通过；`make build` 编译单二进制成功）

---

## 1. 背景与目标

对照 10-04-v1 交付复审报告，修复以下 4 项质量问题：
1. **老数据回填作用域治理**：将 `migrateCategoriesColumns` 的一次性回填移入 `!hasType` 分支，杜绝每次重启覆盖用户在设置页手动纠错的分类类型；
2. **同名分类升级状态一致性**：在 `ensureSystemTransferCategory` 和 `ensureSystemRepaymentCategory` 获取 ID 后显式确保 `type='system'`，解决老库升级时自建同名分类未被标记为系统的状态脱节；
3. **移动端底部筛选胶囊防重叠**：调整 `BottomBar.tsx` 移动端内边距为 `px-2.5` 且 `gap-0.5`，胶囊总宽收缩至 248px，彻底消除 ≤375px 小屏下与右侧 FAB 的边缘重叠；
4. **文档结构排版修正**：移除 `.docs/Project.md` 目录树中重复的 `├─ internal/` 行。

---

## 2. 变更范围与验证

- `internal/db/db.go`：回填作用域收敛，显式设置系统分类 `type='system'`；
- `internal/db/db_test.go`：新增用户纠错重启保护单测与同名系统分类升级单测；
- `web/src/components/BottomBar.tsx`：移动端内边距调整与间距微调；
- `.docs/Project.md`：清理目录树冗余行并更新决策记录。
