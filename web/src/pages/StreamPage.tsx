import type { FC } from 'react';
import { CalendarIcon, EditIcon, TrashIcon } from '../components/Icons';
import { TypeTile, Amount, Panel, SkeletonList, EmptyState, IconButton } from '../components/primitives';
import { Transaction } from '../lib/api';
import { formatMoney, formatPercent } from '../lib/format.ts';
import { getDayInfo, buildMetaParts, formatAmount } from './streamUtils';

interface StreamPageProps {
  transactions: Transaction[];
  /** Unfiltered source (limit=100) dedicated to the month headline, immune to the bottom filter */
  monthTransactions: Transaction[];
  loading: boolean;
  onEdit: (tx: Transaction) => void;
  onDelete: (id: number) => void;
  onAddRecord: () => void;
}

/** Local-timezone `YYYY-MM-DD` key from an ISO timestamp */
function toDateKey(iso: string): string | null {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

interface MonthHeadline {
  expense: number;
  income: number;
  balance: number;
  ratio: number | null;
  label: string;
}

/** Current-calendar-month aggregation, strictly excluding transfer & repayment */
function computeMonthHeadline(transactions: Transaction[]): MonthHeadline {
  const now = new Date();
  const monthPrefix = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
  let expense = 0;
  let income = 0;
  transactions.forEach((tx) => {
    const key = toDateKey(tx.transacted_at);
    if (!key || !key.startsWith(monthPrefix)) return;
    if (tx.type === 'expense' || (!tx.type && tx.amount_cents < 0)) {
      expense += Math.abs(tx.amount);
    } else if (tx.type === 'income' || (!tx.type && tx.amount_cents > 0)) {
      income += tx.amount;
    }
  });
  const denom = expense + income;
  return {
    expense,
    income,
    balance: income - expense,
    ratio: denom > 0 ? (expense / denom) * 100 : null,
    label: `${now.getMonth() + 1}月支出`,
  };
}

export const StreamPage: FC<StreamPageProps> = ({
  transactions,
  monthTransactions,
  loading,
  onEdit,
  onDelete,
  onAddRecord,
}) => {
  if (loading) {
    return (
      <div className="flex flex-col gap-4">
        {/* Headline placeholder keeps the layout rhythm */}
        <div className="flex items-end justify-between mb-1">
          <div className="flex gap-5">
            <div className="w-24 h-9 rounded bg-[var(--surface-sunken)] animate-pulse-soft" />
            <div className="w-20 h-7 rounded bg-[var(--surface-sunken)] animate-pulse-soft" />
          </div>
          <div className="w-[132px] h-1 rounded-full bg-[var(--surface-sunken)] animate-pulse-soft" />
        </div>
        <SkeletonList groups={2} />
      </div>
    );
  }

  const headline = computeMonthHeadline(monthTransactions);

  // Group transactions by local date
  const groups: { [dateKey: string]: Transaction[] } = {};
  transactions.forEach((tx) => {
    const key = toDateKey(tx.transacted_at) ?? '其他';
    if (!groups[key]) groups[key] = [];
    groups[key].push(tx);
  });
  const sortedKeys = Object.keys(groups).sort((a, b) => b.localeCompare(a));

  if (transactions.length === 0) {
    return (
      <EmptyState
        icon={<CalendarIcon size={22} />}
        title="本月还没有记账"
        subtitle="从第一笔开始，流水会按日自动归集"
        action={{ label: '记一笔', onClick: onAddRecord }}
      />
    );
  }

  return (
    <div className="flex flex-col pb-4">
      {/* Month Headline — canvas-level, no card chrome */}
      <div className="flex items-end justify-between gap-4 flex-wrap mb-[18px]">
        <div className="flex gap-[22px] items-end">
          <div className="flex flex-col gap-0.5">
            <span className="text-xs text-[var(--fg-3)]">{headline.label}</span>
            <Amount value={formatMoney(headline.expense, { sign: 'none' })} tone="expense" size="lg" className="!text-[22px]" />
          </div>
          <div className="flex flex-col gap-0.5">
            <span className="text-xs text-[var(--fg-3)]">收入</span>
            <Amount value={formatMoney(headline.income, { sign: 'none' })} tone="income" className="!text-[17px] !font-semibold" />
          </div>
          <div className="flex flex-col gap-0.5">
            <span className="text-xs text-[var(--fg-3)]">结余</span>
            <span
              className={`num text-[17px] font-semibold ${
                headline.balance >= 0 ? 'text-[var(--fg)]' : 'text-[var(--expense-text)]'
              }`}
            >
              {headline.balance >= 0
                ? formatMoney(headline.balance, { sign: 'none' })
                : formatMoney(headline.balance)}
            </span>
          </div>
        </div>
        {/* Expense/Income ratio rail — hidden when there is nothing to divide */}
        {headline.ratio !== null && (
          <div
            className="w-[132px] h-1 rounded-[var(--r-nano)] overflow-hidden flex bg-[var(--income)] mb-1.5"
            title="收支比例"
            role="img"
            aria-label={`支出占收支合计 ${formatPercent(headline.ratio)}`}
          >
            <i className="block h-full bg-[var(--expense)]" style={{ width: `${headline.ratio}%` }} />
          </div>
        )}
      </div>

      {/* Day Surfaces */}
      <div className="flex flex-col gap-4">
        {sortedKeys.map((dateKey) => {
          const items = groups[dateKey];
          const dayInfo = getDayInfo(dateKey);

          // Day subtotals strictly exclude transfer & repayment
          let groupExpense = 0;
          let groupIncome = 0;
          items.forEach((item) => {
            if (item.type === 'expense' || (!item.type && item.amount_cents < 0)) {
              groupExpense += Math.abs(item.amount);
            } else if (item.type === 'income' || (!item.type && item.amount_cents > 0)) {
              groupIncome += item.amount;
            }
          });

          return (
            <Panel key={dateKey} className="overflow-hidden">
              {/* Day Header */}
              <div className="flex items-baseline justify-between gap-3 flex-wrap px-3.5 py-[9px] bg-[var(--surface-sunken)] border-b border-[var(--line)]">
                <div className="flex items-baseline gap-1.5">
                  <b className="text-[13px] font-[650] tracking-[-.01em] text-[var(--fg)]">{dayInfo.primary}</b>
                  {dayInfo.sub && <em className="not-italic text-[11.5px] text-[var(--fg-muted)]">{dayInfo.sub}</em>}
                </div>
                <div className="flex gap-3.5 text-xs text-[var(--fg-3)] whitespace-nowrap">
                  {groupExpense > 0 && (
                    <span>
                      支出{' '}
                      <b className="num font-semibold text-[var(--expense-text)]">
                        {formatMoney(groupExpense, { sign: 'none' })}
                      </b>
                    </span>
                  )}
                  {groupIncome > 0 && (
                    <span>
                      收入{' '}
                      <b className="num font-semibold text-[var(--income-text)]">
                        {formatMoney(groupIncome, { sign: 'none' })}
                      </b>
                    </span>
                  )}
                </div>
              </div>

              {/* Rows */}
              <div>
                {items.map((item, idx) => {
                  const metaParts = buildMetaParts(item);
                  const { formattedText } = formatAmount(item.amount, item.type, item.amount_cents);

                  return (
                    <div
                      key={item.id}
                      className={`group flex items-center gap-3 px-3.5 py-2 transition-colors duration-[var(--d1)] [transition-timing-function:var(--ease-std)] hover:bg-[var(--surface-hover)] ${
                        idx > 0 ? 'border-t border-[var(--line)]' : ''
                      }`}
                    >
                      <TypeTile type={item.type} />

                      {/* Title & Meta */}
                      <div className="flex-1 min-w-0 flex flex-col">
                        <div className="text-sm font-medium text-[var(--fg)] truncate">{item.description}</div>
                        <div className="text-xs text-[var(--fg-3)] truncate mt-px">
                          {metaParts.map((part, pIdx) => (
                            <span key={pIdx}>
                              {pIdx > 0 && <span className="text-[var(--fg-muted)] px-1">·</span>}
                              {part}
                            </span>
                          ))}
                        </div>
                      </div>

                      {/* Amount */}
                      <Amount
                        value={formattedText}
                        type={item.type}
                        className="min-w-[76px] min-[640px]:min-w-[88px] text-right whitespace-nowrap flex-shrink-0 !text-[14px] min-[640px]:!text-[15px]"
                      />

                      {/* Row Actions */}
                      <div className="flex gap-0.5 flex-shrink-0 opacity-100 min-[640px]:opacity-55 min-[640px]:group-hover:opacity-100 min-[640px]:group-focus-within:opacity-100 transition-opacity duration-[var(--d1)]">
                        <IconButton label="编辑" size={28} onClick={() => onEdit(item)}>
                          <EditIcon size={14} />
                        </IconButton>
                        <IconButton label="删除" tone="danger" size={28} onClick={() => onDelete(item.id)}>
                          <TrashIcon size={14} />
                        </IconButton>
                      </div>
                    </div>
                  );
                })}
              </div>
            </Panel>
          );
        })}
      </div>
    </div>
  );
};
