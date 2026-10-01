import { useState } from 'react';
import type { FC } from 'react';
import { StatsSummary } from '../lib/api';

interface StatsPageProps {
  stats: StatsSummary | null;
  loading: boolean;
}

export const StatsPage: FC<StatsPageProps> = ({ stats, loading }) => {
  const [selectedCatId, setSelectedCatId] = useState<number | null>(null);

  if (loading || !stats) {
    return (
      <div className="w-full max-w-[900px] flex flex-col items-center justify-center py-20 text-[var(--color-neutral-fg-3)]">
        <div className="w-8 h-8 border-2 border-[var(--color-brand)] border-t-transparent rounded-full animate-spin mb-3" />
        <span className="text-xs">加载统计数据中...</span>
      </div>
    );
  }

  // Calculate max value for trend bar scaling
  const maxTrendVal = Math.max(
    ...stats.monthly_trends.map((t) => Math.max(t.expense, t.income)),
    100
  );

  const selectedCategory = stats.category_distribution.find((c) => c.id === selectedCatId);

  return (
    <div className="w-full max-w-[900px] flex flex-col gap-5 animate-fade-in pb-16">
      {/* 4 KPI Cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-3.5">
        {/* KPI 1: Week Expense */}
        <div className="bg-[var(--color-card-bg)] rounded-xl border border-[var(--color-neutral-stroke)] p-4 shadow-[var(--shadow-card)] flex flex-col gap-1.5">
          <span className="text-xs text-[var(--color-neutral-fg-3)] font-medium">本周花费</span>
          <span className="text-2xl font-bold tabular-num text-[var(--color-neutral-fg-1)]">
            ¥{stats.week_expense.toFixed(2)}
          </span>
          <span className="text-[11px] text-[var(--color-neutral-fg-subtle)]">自然周统计</span>
        </div>

        {/* KPI 2: Month Expense */}
        <div className="bg-[var(--color-card-bg)] rounded-xl border border-[var(--color-neutral-stroke)] p-4 shadow-[var(--shadow-card)] flex flex-col gap-1.5">
          <span className="text-xs text-[var(--color-neutral-fg-3)] font-medium">当月花费</span>
          <span className="text-2xl font-bold tabular-num text-[var(--color-expense-dark)]">
            ¥{stats.month_expense.toFixed(2)}
          </span>
          <span className="text-[11px] text-[var(--color-neutral-fg-subtle)]">当月累计支出</span>
        </div>

        {/* KPI 3: Last Month Expense */}
        <div className="bg-[var(--color-card-bg)] rounded-xl border border-[var(--color-neutral-stroke)] p-4 shadow-[var(--shadow-card)] flex flex-col gap-1.5">
          <span className="text-xs text-[var(--color-neutral-fg-3)] font-medium">上月花费</span>
          <span className="text-2xl font-bold tabular-num text-[var(--color-neutral-fg-1)]">
            ¥{stats.last_month_expense.toFixed(2)}
          </span>
          <span className="text-[11px] text-[var(--color-neutral-fg-subtle)]">上一自然月全量</span>
        </div>

        {/* KPI 4: Month Balance */}
        <div className="bg-[var(--color-card-bg)] rounded-xl border border-[var(--color-neutral-stroke)] p-4 shadow-[var(--shadow-card)] flex flex-col gap-1.5">
          <span className="text-xs text-[var(--color-neutral-fg-3)] font-medium">当月结余</span>
          <span
            className={`text-2xl font-bold tabular-num ${
              stats.month_balance >= 0
                ? 'text-[var(--color-income-dark)]'
                : 'text-[var(--color-expense-dark)]'
            }`}
          >
            {stats.month_balance >= 0 ? '+' : ''}¥{stats.month_balance.toFixed(2)}
          </span>
          <div className="flex items-center gap-1.5">
            <span
              className={`text-[11px] font-semibold px-1.5 py-0.2 rounded ${
                stats.savings_rate >= 0
                  ? 'bg-[var(--color-income-bg)] text-[var(--color-income-dark)]'
                  : 'bg-[var(--color-expense-bg)] text-[var(--color-expense-dark)]'
              }`}
            >
              储蓄率 {stats.savings_rate.toFixed(1)}%
            </span>
          </div>
        </div>
      </div>

      {/* Category Expense Distribution with Drilldown */}
      <div className="bg-[var(--color-card-bg)] rounded-2xl border border-[var(--color-neutral-stroke)] p-5.5 shadow-[var(--shadow-card)]">
        <div className="flex items-center justify-between mb-4">
          <h4 className="text-base font-semibold text-[var(--color-neutral-fg-1)]">
            当月支出分类占比
          </h4>
          <span className="text-xs text-[var(--color-neutral-fg-3)]">
            点击分类查看细分标签下钻
          </span>
        </div>

        {stats.category_distribution.length === 0 ? (
          <div className="text-center py-10 text-xs text-[var(--color-neutral-fg-3)]">
            当月暂无分类支出数据
          </div>
        ) : (
          <div className="flex flex-col gap-2">
            {stats.category_distribution.map((cat) => {
              const isSelected = selectedCatId === cat.id;
              return (
                <div
                  key={cat.id}
                  onClick={() => setSelectedCatId(isSelected ? null : cat.id)}
                  className={`p-2.5 px-3 rounded-xl cursor-pointer border transition-all ${
                    isSelected
                      ? 'bg-[var(--color-brand-light)] border-[var(--color-brand-stroke)]'
                      : 'border-transparent hover:bg-[var(--color-hover-bg)]'
                  }`}
                >
                  <div className="flex items-center justify-between mb-1.5 text-xs">
                    <span className="font-semibold text-[var(--color-neutral-fg-1)]">
                      {cat.name}
                    </span>
                    <div className="flex items-center gap-2">
                      <span className="font-bold tabular-num text-[var(--color-neutral-fg-1)]">
                        ¥{cat.amount.toFixed(2)}
                      </span>
                      <span className="text-[var(--color-neutral-fg-3)] tabular-num w-11 text-right">
                        {cat.percentage.toFixed(1)}%
                      </span>
                    </div>
                  </div>

                  {/* Progress rail */}
                  <div className="h-1.5 w-full bg-[var(--color-canvas-bg)] rounded-full overflow-hidden">
                    <div
                      className="h-full bg-[var(--color-brand)] rounded-full transition-all duration-300"
                      style={{ width: `${Math.min(cat.percentage, 100)}%` }}
                    />
                  </div>
                </div>
              );
            })}

            {/* Drilldown Subtag Cluster */}
            {selectedCategory && (
              <div className="mt-3 p-4 rounded-xl bg-[var(--color-hover-bg)] border border-[var(--color-neutral-stroke)] animate-fade-in">
                <div className="text-xs font-semibold text-[var(--color-neutral-fg-2)] mb-2 flex items-center justify-between">
                  <span>{selectedCategory.name} · 细分标签消费明细</span>
                  <button
                    type="button"
                    onClick={(e) => {
                      e.stopPropagation();
                      setSelectedCatId(null);
                    }}
                    className="text-xs text-[var(--color-neutral-fg-3)] hover:text-[var(--color-neutral-fg-1)] cursor-pointer"
                  >
                    收起
                  </button>
                </div>

                {selectedCategory.tags.length === 0 ? (
                  <div className="text-xs text-[var(--color-neutral-fg-subtle)]">
                    该分类下暂无细分标签支出
                  </div>
                ) : (
                  <div className="flex flex-wrap gap-2">
                    {selectedCategory.tags.map((tg) => (
                      <div
                        key={tg.id}
                        className="bg-[var(--color-card-bg)] border border-[var(--color-neutral-stroke)] px-3 py-1.5 rounded-lg text-xs flex items-center gap-2"
                      >
                        <span className="font-medium text-[var(--color-neutral-fg-1)]">
                          {tg.name}
                        </span>
                        <span className="tabular-num font-semibold text-[var(--color-brand)]">
                          ¥{tg.amount.toFixed(2)}
                        </span>
                        <span className="text-[10px] text-[var(--color-neutral-fg-subtle)] tabular-num">
                          {tg.percentage.toFixed(1)}%
                        </span>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            )}
          </div>
        )}
      </div>

      {/* 6-Month Trend & Payment Method Distribution */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {/* Trend Chart */}
        <div className="bg-[var(--color-card-bg)] rounded-2xl border border-[var(--color-neutral-stroke)] p-5 shadow-[var(--shadow-card)] flex flex-col justify-between">
          <div className="flex items-center justify-between mb-4">
            <h4 className="text-sm font-semibold text-[var(--color-neutral-fg-1)]">
              近 6 个月收支趋势
            </h4>
            <div className="flex items-center gap-3 text-[11px] text-[var(--color-neutral-fg-3)]">
              <span className="flex items-center gap-1">
                <span className="w-2.5 h-2.5 rounded-sm bg-[var(--color-expense)]" />
                支出
              </span>
              <span className="flex items-center gap-1">
                <span className="w-2.5 h-2.5 rounded-sm bg-[var(--color-income)]" />
                收入
              </span>
            </div>
          </div>

          <div className="h-[140px] flex items-end justify-between gap-3 pt-4">
            {stats.monthly_trends.map((item) => {
              const expHeight = Math.max((item.expense / maxTrendVal) * 90, item.expense > 0 ? 6 : 0);
              const incHeight = Math.max((item.income / maxTrendVal) * 90, item.income > 0 ? 6 : 0);
              const label = item.month.substring(5); // e.g. "05" or "10"

              return (
                <div key={item.month} className="flex-1 flex flex-col items-center gap-1.5 h-full justify-end">
                  <div className="flex items-end gap-1 h-[100px]">
                    {/* Expense bar */}
                    <div
                      title={`支出: ¥${item.expense.toFixed(2)}`}
                      className="w-3 rounded-t-sm bg-[var(--color-expense)] transition-all duration-300 hover:opacity-85"
                      style={{ height: `${expHeight}px` }}
                    />
                    {/* Income bar */}
                    <div
                      title={`收入: ¥${item.income.toFixed(2)}`}
                      className="w-3 rounded-t-sm bg-[var(--color-income)] transition-all duration-300 hover:opacity-85"
                      style={{ height: `${incHeight}px` }}
                    />
                  </div>
                  <span className="text-[11px] text-[var(--color-neutral-fg-3)] tabular-num">
                    {label}月
                  </span>
                </div>
              );
            })}
          </div>
        </div>

        {/* Payment Methods Breakdown */}
        <div className="bg-[var(--color-card-bg)] rounded-2xl border border-[var(--color-neutral-stroke)] p-5 shadow-[var(--shadow-card)]">
          <h4 className="text-sm font-semibold text-[var(--color-neutral-fg-1)] mb-4">
            当月支付途径分布
          </h4>

          {stats.payment_distribution.length === 0 ? (
            <div className="text-center py-10 text-xs text-[var(--color-neutral-fg-3)]">
              暂无渠道支出记录
            </div>
          ) : (
            <div className="flex flex-col gap-2.5">
              {stats.payment_distribution.map((pm) => (
                <div key={pm.id} className="flex flex-col gap-1">
                  <div className="flex items-center justify-between text-xs">
                    <span className="font-medium text-[var(--color-neutral-fg-2)]">{pm.name}</span>
                    <div className="flex items-center gap-2">
                      <span className="tabular-num font-semibold text-[var(--color-neutral-fg-1)]">
                        ¥{pm.amount.toFixed(2)}
                      </span>
                      <span className="text-[var(--color-neutral-fg-3)] tabular-num w-10 text-right">
                        {pm.percentage.toFixed(1)}%
                      </span>
                    </div>
                  </div>
                  <div className="h-1.5 w-full bg-[var(--color-canvas-bg)] rounded-full overflow-hidden">
                    <div
                      className="h-full bg-[var(--color-brand)] rounded-full"
                      style={{ width: `${Math.min(pm.percentage, 100)}%` }}
                    />
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
};
