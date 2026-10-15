import type { FC, ReactNode } from 'react';
import type { StatsSummary, PaymentMethodStat } from '../lib/api';
import { formatMoney, formatPercent } from '../lib/format.ts';
import { Panel, Chip, Rail, Skeleton, EmptyState } from '../components/primitives';
import { DonutChart, TrendChart } from '../components/Charts';

interface StatsPageProps {
  stats: StatsSummary | null;
  loading: boolean;
}

function StatsSkeleton() {
  return (
    <div className="flex flex-col gap-4 pb-4" aria-hidden="true">
      <Skeleton className="h-[170px] rounded-[var(--r-xl)]" />
      <Skeleton className="h-[96px] rounded-[var(--r-lg)]" />
      <div className="grid grid-cols-1 min-[768px]:grid-cols-2 gap-4">
        <Skeleton className="h-[230px] rounded-[var(--r-lg)]" />
        <Skeleton className="h-[230px] rounded-[var(--r-lg)]" />
      </div>
    </div>
  );
}

/* Metric cell inside the hairline-divided row */
const Metric: FC<{ label: string; value: ReactNode; footnote?: ReactNode; className?: string }> = ({
  label,
  value,
  footnote,
  className = '',
}) => (
  <div className={`p-4 px-[18px] ${className}`}>
    <span className="block text-xs text-[var(--fg-3)]">{label}</span>
    <b className="num block mt-1 text-[19px] font-[650] tracking-[-.02em] text-[var(--fg)]">{value}</b>
    {footnote && <small className="block mt-1.5 text-[11.5px] text-[var(--fg-muted)]">{footnote}</small>}
  </div>
);

/* Hairline dividers: 2-col grid below 720px, 4-col above */
const METRIC_BORDERS = [
  '',
  'border-l border-[var(--line)]',
  'border-t border-[var(--line)] min-[720px]:border-t-0 min-[720px]:border-l',
  'border-t border-l border-[var(--line)] min-[720px]:border-t-0',
];

/* Channel row used by payment distribution */
const ChannelRow: FC<{
  dotColor: string;
  name: string;
  balance: number;
  railValue: number | null;
  railColor: string;
  tone: string;
  subLeft: ReactNode;
  subRight: ReactNode;
}> = ({ dotColor, name, balance, railValue, railColor, tone, subLeft, subRight }) => (
  <div className="flex flex-col gap-1.5 py-2.5 border-t border-[var(--line)] first:border-t-0">
    <div className="flex items-center gap-2 text-[13px]">
      <i className="w-[7px] h-[7px] rounded-full flex-shrink-0" style={{ background: dotColor }} />
      <b className="flex-1 font-semibold text-[var(--fg)] truncate">{name}</b>
      <i className={`not-italic num font-[650] ${tone}`}>{formatMoney(balance, { sign: 'none' })}</i>
    </div>
    {railValue !== null && <Rail value={railValue} color={railColor} />}
    <div className="flex justify-between gap-2 text-[11.5px] text-[var(--fg-muted)]">
      <span className="truncate">{subLeft}</span>
      <span className="whitespace-nowrap">{subRight}</span>
    </div>
  </div>
);

export const StatsPage: FC<StatsPageProps> = ({ stats, loading }) => {
  if (loading || !stats) {
    return <StatsSkeleton />;
  }

  const currentMonth = new Date().getMonth() + 1;
  const daysPassed = Math.max(1, new Date().getDate());
  const dailyAverage = stats.month_expense / daysPassed;

  const momChange =
    stats.last_month_expense > 0
      ? ((stats.month_expense - stats.last_month_expense) / stats.last_month_expense) * 100
      : null;

  const balanceTone = stats.month_balance >= 0 ? 'text-[var(--income-text)]' : 'text-[var(--expense-text)]';
  const balanceSign = stats.month_balance >= 0 ? '+' : '−';
  const totalCashflow = stats.month_income + stats.month_expense;

  return (
    <div className="flex flex-col gap-4 pb-4">
      {/* Hero: Month Balance */}
      <Panel variant="hero" className="p-[22px] min-[720px]:px-[26px] pb-5">
        <div className="text-[12.5px] font-semibold tracking-[.01em] text-[var(--fg-3)]">
          {currentMonth} 月结余
        </div>
        <div className="mt-1 flex items-baseline">
          <span className="num text-2xl font-medium text-[var(--fg-2)] mr-1">¥</span>
          <span
            className={`num text-[34px] min-[720px]:text-[40px] font-[680] tracking-[-.028em] leading-[1.1] ${balanceTone}`}
          >
            {balanceSign}
            {formatMoney(Math.abs(stats.month_balance), { sign: 'none' })}
          </span>
        </div>

        <div className="grid grid-cols-2 gap-4 mt-4">
          <div>
            <div className="text-[11.5px] text-[var(--fg-muted)]">收入</div>
            <b className="num text-[19px] font-semibold text-[var(--income-text)]">
              {formatMoney(stats.month_income, { sign: 'none' })}
            </b>
          </div>
          <div>
            <div className="text-[11.5px] text-[var(--fg-muted)]">支出</div>
            <b className="num text-[19px] font-semibold text-[var(--expense-text)]">
              {formatMoney(stats.month_expense, { sign: 'none' })}
            </b>
          </div>
        </div>

        {totalCashflow > 0 && (
          <div
            role="img"
            aria-label="收支比例"
            className="flex h-[6px] rounded-[var(--r-pill)] overflow-hidden gap-[2px] bg-[var(--surface-sunken)] mt-3"
          >
            {stats.month_income > 0 && (
              <i
                style={{ flex: stats.month_income, background: 'var(--income)' }}
                className="block h-full"
              />
            )}
            {stats.month_expense > 0 && (
              <i
                style={{ flex: stats.month_expense, background: 'var(--expense)' }}
                className="block h-full"
              />
            )}
          </div>
        )}

        <div className="flex items-center gap-2 mt-3">
          <Chip>储蓄率 {formatPercent(stats.savings_rate)}</Chip>
        </div>
      </Panel>

      {/* Metrics Row (hairline divided) */}
      <Panel className="grid grid-cols-2 min-[720px]:grid-cols-4 overflow-hidden">
        <Metric
          className={METRIC_BORDERS[0]}
          label="本周花费"
          value={formatMoney(stats.week_expense, { sign: 'none' })}
        />
        <Metric
          className={METRIC_BORDERS[1]}
          label="当月花费"
          value={<span className="text-[var(--expense-text)]">{formatMoney(stats.month_expense, { sign: 'none' })}</span>}
          footnote={
            momChange !== null ? (
              <span>
                较上月 {momChange >= 0 ? '+' : '−'}
                {formatPercent(Math.abs(momChange))}
              </span>
            ) : undefined
          }
        />
        <Metric
          className={METRIC_BORDERS[2]}
          label="上月花费"
          value={formatMoney(stats.last_month_expense, { sign: 'none' })}
        />
        <Metric
          className={METRIC_BORDERS[3]}
          label="日均花费"
          value={formatMoney(dailyAverage, { sign: 'none' })}
        />
      </Panel>

      {/* Category Donut + Trend */}
      <div className="grid grid-cols-1 min-[768px]:grid-cols-2 gap-4">
        <Panel className="p-[18px]">
          <div className="flex items-baseline justify-between gap-2.5 mb-3.5">
            <b className="text-sm font-[650] text-[var(--fg)]">当月支出构成</b>
            <span className="num text-[12.5px] text-[var(--fg-3)]">
              {formatMoney(stats.month_expense, { sign: 'none' })}
            </span>
          </div>
          {stats.category_distribution.length === 0 ? (
            <EmptyState title="当月暂无分类支出" subtitle="记录支出后这里会展示构成" />
          ) : (
            <DonutChart data={stats.category_distribution} />
          )}
        </Panel>

        <Panel className="p-[18px] flex flex-col">
          <div className="flex items-baseline justify-between gap-2.5 mb-3">
            <b className="text-sm font-[650] text-[var(--fg)]">近 6 个月收支</b>
            <span className="flex gap-2.5 items-center text-[11px] text-[var(--fg-3)]">
              <span className="flex gap-1 items-center">
                <i className="block w-2 h-2 rounded-[var(--r-nano)] bg-[var(--expense)]" />
                支出
              </span>
              <span className="flex gap-1 items-center">
                <i className="block w-2 h-2 rounded-[var(--r-nano)] bg-[var(--income)]" />
                收入
              </span>
            </span>
          </div>
          {stats.monthly_trends.length === 0 ? (
            <EmptyState title="暂无趋势数据" />
          ) : (
            <div className="mt-1">
              <TrendChart data={stats.monthly_trends} />
            </div>
          )}
        </Panel>
      </div>

      {/* Payment Method Distribution */}
      <Panel className="p-[18px]">
        <div className="flex items-baseline justify-between gap-2.5 mb-3">
          <b className="text-sm font-[650] text-[var(--fg)]">当月支付途径分布</b>
          <span className="num text-[12.5px] text-[var(--fg-3)]">
            {formatMoney(stats.month_expense, { sign: 'none' })}
          </span>
        </div>
        {stats.payment_distribution.length === 0 ? (
          <EmptyState title="当月暂无渠道支出" subtitle="记录支出后这里会展示分布" />
        ) : (
          stats.payment_distribution.map((pm: PaymentMethodStat) => (
            <ChannelRow
              key={pm.id}
              dotColor="var(--brand)"
              name={pm.name}
              balance={pm.amount}
              railValue={Math.min(pm.percentage, 100)}
              railColor="var(--brand)"
              tone="text-[var(--fg)]"
              subLeft="占当月支出"
              subRight={formatPercent(pm.percentage)}
            />
          ))
        )}
      </Panel>
    </div>
  );
};
