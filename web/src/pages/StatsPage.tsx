import type { FC, ReactNode } from 'react';
import { StatsSummary, AssetChannelStat, LiabilityChannelStat } from '../lib/api';
import { formatMoney } from '../lib/format.ts';
import { Panel, Chip, Rail, Skeleton, EmptyState } from '../components/primitives';
import { DonutChart, TrendChart } from '../components/Charts';
import { WalletIcon } from '../components/Icons';

interface StatsPageProps {
  stats: StatsSummary | null;
  loading: boolean;
}

function StatsSkeleton() {
  return (
    <div className="flex flex-col gap-4" aria-hidden>
      <Skeleton className="h-[150px] rounded-[var(--r-xl)]" />
      <Skeleton className="h-[110px] rounded-[var(--r-lg)]" />
      <div className="grid grid-cols-1 min-[768px]:grid-cols-2 gap-4">
        <Skeleton className="h-[190px] rounded-[var(--r-lg)]" />
        <Skeleton className="h-[190px] rounded-[var(--r-lg)]" />
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

/* Channel row shared by asset & liability panels */
const ChannelRow: FC<{
  dotColor: string;
  name: string;
  balance: number;
  /** null → no meaningful ratio, rail is not rendered */
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

  const assetSummary = stats.asset_summary;
  const { total_assets: totalAssets, total_liabilities: totalLiabilities, net_assets: netAssets } = assetSummary;

  // Derivations — all zero-denominator safe, no invented data
  const debtRatio = totalAssets > 0 ? (totalLiabilities / totalAssets) * 100 : null;
  const channelCount = assetSummary.asset_channels.length + assetSummary.liability_channels.length;
  const momChange =
    stats.last_month_expense > 0
      ? ((stats.month_expense - stats.last_month_expense) / stats.last_month_expense) * 100
      : null;

  const netTone = netAssets >= 0 ? 'text-[var(--fg)]' : 'text-[var(--expense-text)]';

  return (
    <div className="flex flex-col gap-4 pb-4">
      {/* ===== Hero: Net Assets ===== */}
      <Panel variant="hero" className="p-[22px] pt-[22px] pb-5 min-[720px]:grid min-[720px]:grid-cols-[1fr_auto] min-[720px]:gap-[18px] min-[720px]:px-[26px]">
        <div>
          <div className="text-[12.5px] font-semibold tracking-[.01em] text-[var(--fg-3)]">净资产</div>
          <div className="flex items-baseline gap-1 mt-1.5">
            <span className="num text-2xl font-medium text-[var(--fg-2)]">¥</span>
            <span className={`num text-[34px] min-[720px]:text-[40px] font-[680] tracking-[-.028em] leading-[1.1] ${netTone}`}>
              {netAssets < 0 ? '−' : ''}
              {formatMoney(Math.abs(netAssets), { sign: 'none' })}
            </span>
          </div>
          <div className="flex items-center gap-2.5 mt-3 flex-wrap">
            {debtRatio !== null && <Chip>资产负债率 {debtRatio.toFixed(1)}%</Chip>}
            {channelCount > 0 && <Chip>{channelCount} 个在用渠道</Chip>}
          </div>
        </div>

        {/* ≥720px: asset / liability side column with liability ratio rail */}
        <div className="flex flex-col gap-2.5 min-w-[210px] mt-4 min-[720px]:mt-0">
          <div className="flex items-baseline justify-between gap-2.5">
            <span className="text-xs text-[var(--fg-3)]">资产总计</span>
            <b className="num text-sm font-[650] text-[var(--fg)]">
              {formatMoney(totalAssets, { sign: 'none' })}
            </b>
          </div>
          <div className="flex items-baseline justify-between gap-2.5">
            <span className="text-xs text-[var(--fg-3)]">负债总计</span>
            <b className="num text-sm font-[650] text-[var(--expense-text)]">
              {formatMoney(totalLiabilities, { sign: 'none' })}
            </b>
          </div>
          {debtRatio !== null && (
            <>
              <Rail value={debtRatio} color="var(--expense)" />
              <div className="flex justify-between text-[11.5px] text-[var(--fg-muted)]">
                <span>负债 / 资产</span>
                <span className="num">{debtRatio.toFixed(1)}%</span>
              </div>
            </>
          )}
        </div>
      </Panel>

      {/* ===== Metrics Row (hairline divided) ===== */}
      <Panel className="grid grid-cols-2 min-[720px]:grid-cols-4 overflow-hidden">
        <Metric className={METRIC_BORDERS[0]} label="本周花费" value={formatMoney(stats.week_expense, { sign: 'none' })} />
        <Metric
          className={METRIC_BORDERS[1]}
          label="当月花费"
          value={<span className="text-[var(--expense-text)]">{formatMoney(stats.month_expense, { sign: 'none' })}</span>}
          footnote={
            momChange !== null ? (
              <span>
                较上月 {momChange >= 0 ? '+' : '−'}
                {Math.abs(momChange).toFixed(1)}%
              </span>
            ) : undefined
          }
        />
        <Metric className={METRIC_BORDERS[2]} label="上月花费" value={formatMoney(stats.last_month_expense, { sign: 'none' })} />
        <Metric
          className={METRIC_BORDERS[3]}
          label="当月结余"
          value={
            <span className={stats.month_balance >= 0 ? 'text-[var(--income-text)]' : 'text-[var(--expense-text)]'}>
              {formatMoney(stats.month_balance)}
            </span>
          }
          footnote={`储蓄率 ${stats.savings_rate.toFixed(1)}%`}
        />
      </Panel>

      {/* ===== Channel Panels ===== */}
      <div className="grid grid-cols-1 min-[768px]:grid-cols-2 gap-4">
        <Panel className="p-[18px]">
          <div className="flex items-baseline justify-between gap-2.5 mb-3">
            <b className="text-sm font-[650] text-[var(--fg)]">资产渠道</b>
            <span className="num text-[12.5px] text-[var(--fg-3)]">{formatMoney(totalAssets, { sign: 'none' })}</span>
          </div>
          {assetSummary.asset_channels.length === 0 ? (
            <EmptyState icon={<WalletIcon size={20} />} title="暂无资产渠道" subtitle="在「基础设置」中添加资产渠道后开始统计" />
          ) : (
            assetSummary.asset_channels.map((ac: AssetChannelStat) => (
              <ChannelRow
                key={ac.id}
                dotColor="var(--brand)"
                name={ac.name}
                balance={ac.remaining_balance}
                railValue={Math.min(ac.percentage, 100)}                railColor="var(--brand)"
                tone="text-[var(--fg)]"
                subLeft={`初始 ${formatMoney(ac.initial_balance, { sign: 'none' })}`}
                subRight={`占资产 ${ac.percentage.toFixed(1)}%`}
              />
            ))
          )}
        </Panel>

        <Panel className="p-[18px]">
          <div className="flex items-baseline justify-between gap-2.5 mb-3">
            <b className="text-sm font-[650] text-[var(--fg)]">负债渠道</b>
            <span className="num text-[12.5px] text-[var(--expense-text)]">
              {formatMoney(totalLiabilities, { sign: 'none' })}
            </span>
          </div>
          {assetSummary.liability_channels.length === 0 ? (
            <EmptyState icon={<WalletIcon size={20} />} title="暂无负债渠道" subtitle="在「基础设置」中添加负债渠道后开始统计" />
          ) : (
            assetSummary.liability_channels.map((lc: LiabilityChannelStat) => {
              // ≥80% credit usage flips the whole row into warning semantics
              const hot = lc.credit_limit > 0 && lc.usage_rate >= 80;
              const tone = hot ? 'text-[var(--expense-text)]' : 'text-[var(--fg)]';
              return (
                <ChannelRow
                  key={lc.id}
                  dotColor="var(--expense)"
                  name={lc.name}
                  balance={lc.current_debt}
                  railValue={lc.credit_limit > 0 ? Math.min(lc.usage_rate, 100) : null}
                  railColor="var(--expense)"
                  tone={tone}
                  subLeft={
                    <span className={hot ? 'text-[var(--expense-text)]' : undefined}>
                      {lc.credit_limit > 0
                        ? `剩余可用 ${formatMoney(lc.remaining_credit, { sign: 'none' })}`
                        : '不设额度上限'}
                    </span>
                  }
                  subRight={
                    <span className={hot ? 'text-[var(--expense-text)]' : undefined}>
                      {lc.credit_limit > 0
                        ? `额度 ${formatMoney(lc.credit_limit, { sign: 'none' })} · ${lc.usage_rate.toFixed(1)}%`
                        : `初始欠款 ${formatMoney(lc.initial_debt, { sign: 'none' })}`}
                    </span>
                  }
                />
              );
            })
          )}
        </Panel>
      </div>

      {/* ===== Category Donut + Trend ===== */}
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
                <i className="block w-2 h-2 rounded-[2px] bg-[var(--expense)]" />
                支出
              </span>
              <span className="flex gap-1 items-center">
                <i className="block w-2 h-2 rounded-[2px] bg-[var(--income)]" />
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
    </div>
  );
};
