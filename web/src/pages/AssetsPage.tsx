import { useState } from 'react';
import type { FC } from 'react';
import type { StatsSummary } from '../lib/api';
import { formatMoney, formatPercent } from '../lib/format.ts';
import { Panel, Skeleton, EmptyState, IconButton, Rail } from '../components/primitives';
import { WalletIcon, CreditCardIcon, EyeIcon, EyeOffIcon } from '../components/Icons';
import { donutColor } from '../components/Charts';
import { deriveAssets } from './assetsUtils.ts';

interface AssetsPageProps {
  stats: StatsSummary | null;
  loading: boolean;
  onManageChannels: () => void;
}

function AssetsSkeleton() {
  return (
    <div className="flex flex-col gap-4 pb-4" aria-hidden="true">
      <Skeleton className="h-[210px] rounded-[var(--r-xl)]" />
      <div className="grid grid-cols-1 min-[768px]:grid-cols-2 gap-4">
        <Skeleton className="h-[260px] rounded-[var(--r-lg)]" />
        <Skeleton className="h-[260px] rounded-[var(--r-lg)]" />
      </div>
    </div>
  );
}

export const AssetsPage: FC<AssetsPageProps> = ({ stats, loading, onManageChannels }) => {
  const [hideAmounts, setHideAmounts] = useState<boolean>(() => {
    return localStorage.getItem('ledger_hide_amounts') === 'true';
  });
  const [activeIndex, setActiveIndex] = useState<number | null>(null);

  if (loading || !stats) {
    return <AssetsSkeleton />;
  }

  const toggleHideAmounts = () => {
    setHideAmounts((prev) => {
      const next = !prev;
      localStorage.setItem('ledger_hide_amounts', String(next));
      return next;
    });
  };

  const renderMoney = (amount: number, opts?: { sign?: 'auto' | 'none' }) => {
    if (hideAmounts) return '••••••';
    return formatMoney(amount, opts);
  };

  const { assets, liabilities, debtRatio, credit, totalAssets, totalLiabilities, netAssets } =
    deriveAssets(stats.asset_summary);

  const netTone = netAssets >= 0 ? 'text-[var(--fg)]' : 'text-[var(--expense-text)]';
  const hasDistribution = assets.some((ch) => ch.remaining_balance > 0);

  return (
    <div className="flex flex-col gap-4 pb-4">
      {/* Hero: Net Assets */}
      <Panel variant="hero" className="p-[22px] min-[720px]:px-[26px] pb-5">
        <div className="grid grid-cols-1 min-[640px]:grid-cols-[1fr_auto] gap-5 min-[640px]:gap-6 items-end">
          <div>
            <div className="flex items-center gap-1.5 text-[12.5px] font-semibold tracking-[.01em] text-[var(--fg-3)]">
              <span>净资产</span>
              <IconButton
                label={hideAmounts ? '显示金额' : '隐藏金额'}
                pressed={hideAmounts}
                size={26}
                onClick={toggleHideAmounts}
              >
                {hideAmounts ? <EyeOffIcon size={15} /> : <EyeIcon size={15} />}
              </IconButton>
            </div>
            <div className="mt-1 flex items-baseline">
              <span className="num text-2xl font-medium text-[var(--fg-2)] mr-1">¥</span>
              <span
                className={`num text-[34px] min-[720px]:text-[40px] font-[680] tracking-[-.028em] leading-[1.1] ${netTone}`}
              >
                {netAssets < 0 && !hideAmounts ? '−' : ''}
                {renderMoney(Math.abs(netAssets), { sign: 'none' })}
              </span>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-x-7 gap-y-1.5 text-xs text-[var(--fg-3)] min-w-[220px]">
            <span>资产总计</span>
            <b className="num text-right font-semibold text-sm text-[var(--fg)]">
              {renderMoney(totalAssets, { sign: 'none' })}
            </b>
            <span>负债总计</span>
            <b className="num text-right font-semibold text-sm text-[var(--expense-text)]">
              {renderMoney(totalLiabilities, { sign: 'none' })}
            </b>
            <span>资产负债率</span>
            <b className="num text-right font-semibold text-sm text-[var(--fg)]">
              {debtRatio === null ? '—' : formatPercent(debtRatio)}
            </b>
          </div>
        </div>

        {/* 10px Stacked distribution bar */}
        {hasDistribution && (
          <div
            role="img"
            aria-label="资产分布"
            className="flex h-[10px] rounded-[var(--r-pill)] overflow-hidden gap-[2px] bg-[var(--surface-sunken)] mt-5"
          >
            {assets.map((ch, idx) => {
              if (ch.remaining_balance <= 0) return null;
              const isMuted = activeIndex !== null && activeIndex !== idx;
              return (
                <i
                  key={ch.id}
                  style={{
                    flex: ch.remaining_balance,
                    background: donutColor(idx),
                    opacity: isMuted ? 0.28 : 1,
                    transition: 'opacity var(--d2) var(--ease-out)',
                  }}
                  className="block h-full"
                />
              );
            })}
          </div>
        )}
      </Panel>

      {/* Account Panels */}
      <div className="grid grid-cols-1 min-[768px]:grid-cols-2 gap-4">
        {/* Asset Accounts */}
        <Panel className="p-[18px]">
          <div className="flex items-baseline justify-between gap-2.5 mb-3">
            <div className="flex items-baseline gap-2">
              <b className="text-sm font-[650] text-[var(--fg)]">资产账户</b>
              {assets.length > 0 && (
                <span className="num text-[11.5px] font-semibold text-[var(--fg-3)]">
                  {assets.length} 个
                </span>
              )}
            </div>
            <button
              type="button"
              onClick={onManageChannels}
              className="text-xs font-semibold text-[var(--brand-text)] px-2 py-1 rounded-[var(--r-xs)] hover:bg-[var(--brand-soft)] transition-colors cursor-pointer"
            >
              管理
            </button>
          </div>

          {assets.length === 0 ? (
            <EmptyState
              icon={<WalletIcon size={20} />}
              title="暂无资产账户"
              action={{
                label: '添加资产账户',
                onClick: onManageChannels,
              }}
            />
          ) : (
            <div className="flex flex-col">
              {assets.map((item, idx) => (
                <div
                  key={item.id}
                  // Only positive balances own a distribution-bar segment; linking a non-positive row
                  // would mute every segment while highlighting none
                  onMouseEnter={() => item.remaining_balance > 0 && setActiveIndex(idx)}
                  onMouseLeave={() => setActiveIndex(null)}
                  className="flex items-center gap-3 py-2.5 px-1.5 rounded-[10px] hover:bg-[var(--surface-hover)] transition-colors border-t border-[var(--line)] first:border-t-0"
                >
                  <div
                    aria-hidden="true"
                    className="w-8 h-8 rounded-[var(--r-sm)] bg-[var(--brand-soft)] text-[var(--brand-text)] flex items-center justify-center flex-shrink-0"
                  >
                    <WalletIcon size={16} />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="text-[13.5px] font-semibold text-[var(--fg)] truncate">
                      {item.name}
                    </div>
                    <div className="flex items-center gap-1.5 mt-0.5 text-[11.5px] text-[var(--fg-muted)] num">
                      <i
                        aria-hidden="true"
                        className="w-1.5 h-1.5 rounded-full flex-shrink-0"
                        style={{ background: donutColor(idx) }}
                      />
                      <span>{formatPercent(item.share)}</span>
                    </div>
                  </div>
                  <span
                    className={`num text-sm font-[650] whitespace-nowrap ${
                      item.remaining_balance < 0 ? 'text-[var(--expense-text)]' : 'text-[var(--fg)]'
                    }`}
                  >
                    {renderMoney(item.remaining_balance, {
                      sign: item.remaining_balance < 0 ? 'auto' : 'none',
                    })}
                  </span>
                </div>
              ))}
            </div>
          )}
        </Panel>

        {/* Liability Accounts */}
        <Panel className="p-[18px]">
          <div className="flex items-baseline justify-between gap-2.5 mb-3">
            <div className="flex items-baseline gap-2">
              <b className="text-sm font-[650] text-[var(--fg)]">负债账户</b>
              {liabilities.length > 0 && (
                <span className="num text-[11.5px] font-semibold text-[var(--expense-text)]">
                  {renderMoney(totalLiabilities, { sign: 'none' })}
                </span>
              )}
            </div>
            <button
              type="button"
              onClick={onManageChannels}
              className="text-xs font-semibold text-[var(--brand-text)] px-2 py-1 rounded-[var(--r-xs)] hover:bg-[var(--brand-soft)] transition-colors cursor-pointer"
            >
              管理
            </button>
          </div>

          {credit !== null && (
            <div className="flex items-baseline justify-between text-xs text-[var(--fg-3)] -mt-1 mb-2.5">
              <span>
                总额度使用{' '}
                <b className="num text-[var(--fg)] font-semibold">
                  {formatPercent(credit.usage)}
                </b>
              </span>
              <span className="num">
                可用 {renderMoney(credit.available, { sign: 'none' })}
              </span>
            </div>
          )}

          {liabilities.length === 0 ? (
            <EmptyState
              icon={<CreditCardIcon size={20} />}
              title="暂无负债账户"
            />
          ) : (
            <div className="flex flex-col">
              {liabilities.map((item) => {
                const hasLimit = item.credit_limit > 0;
                const usage = hasLimit ? (item.current_debt / item.credit_limit) * 100 : null;
                const isHot = usage !== null && usage >= 80;
                const tone = isHot ? 'text-[var(--expense-text)]' : 'text-[var(--fg)]';
                const available = hasLimit ? Math.max(item.credit_limit - item.current_debt, 0) : 0;

                return (
                  <div
                    key={item.id}
                    className="flex flex-col gap-1.5 py-2.5 px-1.5 rounded-[10px] hover:bg-[var(--surface-hover)] transition-colors border-t border-[var(--line)] first:border-t-0"
                  >
                    <div className="flex items-center gap-3">
                      <div
                        aria-hidden="true"
                        className="w-8 h-8 rounded-[var(--r-sm)] bg-[var(--expense-soft)] text-[var(--expense-text)] flex items-center justify-center flex-shrink-0"
                      >
                        <CreditCardIcon size={16} />
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="text-[13.5px] font-semibold text-[var(--fg)] truncate">
                          {item.name}
                        </div>
                        <div
                          className={`text-[11.5px] truncate mt-0.5 ${
                            isHot ? 'text-[var(--expense-text)]' : 'text-[var(--fg-muted)]'
                          }`}
                        >
                          {hasLimit
                            ? `可用 ${renderMoney(available, { sign: 'none' })} · 额度 ${renderMoney(
                                item.credit_limit,
                                { sign: 'none' }
                              )}`
                            : '不设额度'}
                        </div>
                      </div>
                      <span className={`num text-sm font-[650] whitespace-nowrap ${tone}`}>
                        {renderMoney(item.current_debt, { sign: 'none' })}
                      </span>
                    </div>
                    {usage !== null && (
                      <div className="pl-11">
                        <Rail
                          value={Math.min(usage, 100)}
                          color={isHot ? 'var(--expense)' : 'var(--fg-muted)'}
                        />
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </Panel>
      </div>
    </div>
  );
};
