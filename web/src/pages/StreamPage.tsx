import { useState, useEffect, type FC } from 'react';
import {
  CalendarIcon,
  ExpenseIcon,
  IncomeIcon,
  TransferIcon,
  RepaymentIcon,
  MoreVerticalIcon,
} from '../components/Icons';
import { Transaction } from '../lib/api';
import { getDayInfo, buildMetaParts, formatAmount } from './streamUtils';

interface StreamPageProps {
  transactions: Transaction[];
  loading: boolean;
  onEdit: (tx: Transaction) => void;
  onDelete: (id: number) => void;
}

export const StreamPage: FC<StreamPageProps> = ({
  transactions,
  loading,
  onEdit,
  onDelete,
}) => {
  const [openMenuTxId, setOpenMenuTxId] = useState<number | null>(null);

  // Close flyout on outside click or Escape key
  useEffect(() => {
    if (openMenuTxId === null) return;
    const handleDocClick = () => {
      setOpenMenuTxId(null);
    };
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        setOpenMenuTxId(null);
      }
    };
    document.addEventListener('click', handleDocClick);
    document.addEventListener('keydown', handleKeyDown);
    return () => {
      document.removeEventListener('click', handleDocClick);
      document.removeEventListener('keydown', handleKeyDown);
    };
  }, [openMenuTxId]);

  if (loading) {
    return (
      <div className="w-full max-w-[900px] flex flex-col items-center justify-center py-20 text-[var(--color-neutral-fg-3)]">
        <div className="w-8 h-8 border-2 border-[var(--color-brand)] border-t-transparent rounded-full animate-spin mb-3" />
        <span className="text-xs">加载账目流水中...</span>
      </div>
    );
  }

  if (transactions.length === 0) {
    return (
      <div className="w-full max-w-[900px] flex flex-col items-center justify-center py-24 text-[var(--color-neutral-fg-3)]">
        <div className="text-[var(--color-neutral-fg-subtle)] mb-3">
          <CalendarIcon size={28} />
        </div>
        <span className="text-sm font-medium text-[var(--color-neutral-fg-2)] mb-1">暂无账单数据</span>
        <span className="text-xs">点击右下角 “+” 开始记账</span>
      </div>
    );
  }

  // Group transactions by date string (YYYY-MM-DD)
  const groups: { [dateKey: string]: Transaction[] } = {};
  transactions.forEach((tx) => {
    let key = '其他';
    try {
      const d = new Date(tx.transacted_at);
      if (!isNaN(d.getTime())) {
        const pad = (n: number) => String(n).padStart(2, '0');
        key = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
      }
    } catch {
      key = '其他';
    }
    if (!groups[key]) groups[key] = [];
    groups[key].push(tx);
  });

  const sortedKeys = Object.keys(groups).sort((a, b) => b.localeCompare(a));

  return (
    <div className="w-full max-w-[900px] flex flex-col gap-6 animate-fade-in pb-12">
      {sortedKeys.map((dateKey) => {
        const items = groups[dateKey];
        const dayInfo = getDayInfo(dateKey);

        // Sum group expense & income (strictly exclude repayment & transfer to prevent pollution)
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
          <div
            key={dateKey}
            className="bg-[var(--color-card-bg)] border border-[var(--color-neutral-stroke)] rounded-xl shadow-[var(--shadow-card)]"
          >
            {/* Day Header */}
            <div className="flex items-baseline justify-between gap-x-3 gap-y-1 flex-wrap px-4 py-3 bg-[var(--color-subtle-bg)] border-b border-[var(--color-neutral-stroke)] rounded-t-[11px]">
              <div className="flex items-baseline gap-1.5 text-[13px] font-semibold text-[var(--color-neutral-fg-1)] tracking-tight">
                <span>{dayInfo.primary}</span>
                {dayInfo.sub && (
                  <span className="text-[11px] font-normal text-[var(--color-neutral-fg-subtle)]">
                    {dayInfo.sub}
                  </span>
                )}
              </div>

              {/* Day Subtotals */}
              <div className="flex items-baseline gap-3.5 text-xs text-[var(--color-neutral-fg-3)] whitespace-nowrap">
                {groupExpense > 0 && (
                  <span>
                    支出{' '}
                    <b className="font-semibold tabular-num text-[var(--color-expense-dark)]">
                      ¥{groupExpense.toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                    </b>
                  </span>
                )}
                {groupIncome > 0 && (
                  <span>
                    收入{' '}
                    <b className="font-semibold tabular-num text-[var(--color-income-dark)]">
                      ¥{groupIncome.toLocaleString('zh-CN', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
                    </b>
                  </span>
                )}
              </div>
            </div>

            {/* List of Rows */}
            <div className="divide-y divide-[var(--color-neutral-stroke)]">
              {items.map((item) => {
                const isRepayment = item.type === 'repayment';
                const isTransfer = item.type === 'transfer';
                const isNeutral = isRepayment || isTransfer;
                const isExp = item.type === 'expense' || (!item.type && item.amount_cents < 0);

                // Build meta parts: category · tag · account / flow · time
                const metaParts = buildMetaParts(item);

                // Unified contract: ${sign}¥${amount}
                const { formattedText: formattedAmountText } = formatAmount(
                  item.amount,
                  item.type,
                  item.amount_cents
                );

                const isMenuOpen = openMenuTxId === item.id;

                return (
                  <div
                    key={item.id}
                    className="group flex items-center gap-3 px-4 py-2 sm:py-2.5 hover:bg-[var(--color-hover-bg)] last:rounded-b-[11px] transition-colors duration-150"
                  >
                    {/* Left: 32px Type Icon Tile */}
                    <div
                      className={`w-8 h-8 rounded-lg flex-shrink-0 flex items-center justify-center ${
                        isNeutral
                          ? 'bg-[var(--color-brand-light)] text-[var(--color-brand)]'
                          : isExp
                          ? 'bg-[var(--color-expense-bg)] text-[var(--color-expense-dark)]'
                          : 'bg-[var(--color-income-bg)] text-[var(--color-income-dark)]'
                      }`}
                    >
                      {isRepayment ? (
                        <RepaymentIcon size={16} />
                      ) : isTransfer ? (
                        <TransferIcon size={16} />
                      ) : isExp ? (
                        <ExpenseIcon size={16} />
                      ) : (
                        <IncomeIcon size={16} />
                      )}
                    </div>

                    {/* Center: Description & Four-part Meta */}
                    <div className="flex-1 min-w-0 flex flex-col gap-0.5">
                      <div className="text-[15px] leading-5 font-medium text-[var(--color-neutral-fg-1)] truncate">
                        {item.description}
                      </div>
                      <div className="text-xs leading-4 text-[var(--color-neutral-fg-3)] truncate">
                        {metaParts.map((part, pIdx) => (
                          <span key={pIdx}>
                            {pIdx > 0 && (
                              <span className="text-[var(--color-neutral-fg-subtle)] px-1">·</span>
                            )}
                            {part}
                          </span>
                        ))}
                      </div>
                    </div>

                    {/* Right: Aligned Amount */}
                    <div
                      className={`min-w-[76px] sm:min-w-[88px] text-right font-semibold text-[15px] sm:text-base tabular-num flex-shrink-0 whitespace-nowrap ${
                        isNeutral
                          ? 'text-[var(--color-brand)]'
                          : isExp
                          ? 'text-[var(--color-expense-dark)]'
                          : 'text-[var(--color-income-dark)]'
                      }`}
                    >
                      {formattedAmountText}
                    </div>

                    {/* Action: Single More Entry with Secondary Flyout */}
                    <div className="relative flex-shrink-0">
                      <button
                        type="button"
                        title="更多操作"
                        aria-label="更多操作"
                        aria-haspopup="true"
                        aria-expanded={isMenuOpen}
                        onClick={(e) => {
                          e.stopPropagation();
                          setOpenMenuTxId(isMenuOpen ? null : item.id);
                        }}
                        className={`w-7 h-7 rounded-md flex items-center justify-center cursor-pointer transition-all duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-brand)] ${
                          isMenuOpen
                            ? 'opacity-100 bg-[var(--color-hover-bg)] text-[var(--color-neutral-fg-1)]'
                            : 'text-[var(--color-neutral-fg-3)] hover:text-[var(--color-neutral-fg-1)] hover:bg-[var(--color-hover-bg)] opacity-60 sm:opacity-0 sm:group-hover:opacity-100 group-focus-within:opacity-100'
                        }`}
                      >
                        <MoreVerticalIcon size={14} />
                      </button>

                      {isMenuOpen && (
                        <div
                          onClick={(e) => e.stopPropagation()}
                          className="absolute right-0 top-[calc(100%+4px)] w-28 bg-[var(--color-card-bg)] border border-[var(--color-neutral-stroke-strong)] rounded-lg shadow-[var(--shadow-flyout)] py-1 z-30 flex flex-col text-xs animate-fade-in"
                        >
                          <button
                            type="button"
                            onClick={() => {
                              setOpenMenuTxId(null);
                              onEdit(item);
                            }}
                            className="px-3 py-1.5 text-left text-[var(--color-neutral-fg-1)] hover:bg-[var(--color-hover-bg)] cursor-pointer transition-colors"
                          >
                            编辑账单
                          </button>
                          <button
                            type="button"
                            onClick={() => {
                              setOpenMenuTxId(null);
                              onDelete(item.id);
                            }}
                            className="px-3 py-1.5 text-left text-[var(--color-expense-dark)] hover:bg-[var(--color-expense-bg)] cursor-pointer transition-colors"
                          >
                            删除账单
                          </button>
                        </div>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        );
      })}
    </div>
  );
};
