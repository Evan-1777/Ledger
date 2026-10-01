import type { FC } from 'react';
import { CalendarIcon, ClockIcon, EditIcon, TrashIcon } from '../components/Icons';
import { Transaction } from '../lib/api';

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
        <div className="w-12 h-12 rounded-2xl bg-[var(--color-hover-bg)] flex items-center justify-center mb-3">
          <CalendarIcon size={24} />
        </div>
        <span className="text-sm font-medium text-[var(--color-neutral-fg-2)] mb-1">暂无账单数据</span>
        <span className="text-xs">点击右下角 “+” 开始记录第一笔收支</span>
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

  const getDayLabel = (dateStr: string) => {
    try {
      const today = new Date();
      const pad = (n: number) => String(n).padStart(2, '0');
      const todayStr = `${today.getFullYear()}-${pad(today.getMonth() + 1)}-${pad(today.getDate())}`;

      const yesterday = new Date(today);
      yesterday.setDate(yesterday.getDate() - 1);
      const yesterdayStr = `${yesterday.getFullYear()}-${pad(yesterday.getMonth() + 1)}-${pad(yesterday.getDate())}`;

      if (dateStr === todayStr) return '今天';
      if (dateStr === yesterdayStr) return '昨天';

      const parts = dateStr.split('-');
      if (parts.length === 3) {
        const year = parseInt(parts[0], 10);
        const month = parseInt(parts[1], 10);
        const day = parseInt(parts[2], 10);
        if (year !== today.getFullYear()) {
          return `${year}年${month}月${day}日`;
        }
        return `${month}月${day}日`;
      }
      return dateStr;
    } catch {
      return dateStr;
    }
  };

  const formatTime = (isoStr: string) => {
    try {
      const d = new Date(isoStr);
      const pad = (n: number) => String(n).padStart(2, '0');
      return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
    } catch {
      return '';
    }
  };

  return (
    <div className="w-full max-w-[900px] flex flex-col gap-6 animate-fade-in pb-12">
      {sortedKeys.map((dateKey) => {
        const items = groups[dateKey];
        const dayLabel = getDayLabel(dateKey);

        // Sum group expense & income
        let groupExpense = 0;
        let groupIncome = 0;
        items.forEach((item) => {
          if (item.amount_cents < 0) {
            groupExpense += Math.abs(item.amount);
          } else {
            groupIncome += item.amount;
          }
        });

        return (
          <div key={dateKey} className="flex flex-col gap-2.5">
            {/* Group Header */}
            <div className="flex items-center justify-between px-1">
              <div className="flex items-center gap-2">
                <span className="text-[var(--color-neutral-fg-3)]">
                  <CalendarIcon size={15} />
                </span>
                <span className="text-sm font-semibold text-[var(--color-neutral-fg-1)]">
                  {dayLabel}
                </span>
                <span className="text-[11px] font-semibold px-2 py-0.5 rounded-full bg-[var(--color-hover-bg)] text-[var(--color-neutral-fg-3)] border border-[var(--color-neutral-stroke)]">
                  {items.length} 笔
                </span>
              </div>

              {/* Sub-header pills */}
              <div className="flex items-center gap-3 text-xs text-[var(--color-neutral-fg-3)]">
                {groupExpense > 0 && (
                  <span>
                    支出 <span className="tabular-num font-medium text-[var(--color-expense-dark)]">¥{groupExpense.toFixed(2)}</span>
                  </span>
                )}
                {groupIncome > 0 && (
                  <span>
                    收入 <span className="tabular-num font-medium text-[var(--color-income-dark)]">¥{groupIncome.toFixed(2)}</span>
                  </span>
                )}
              </div>
            </div>

            {/* List of cards */}
            <div className="flex flex-col gap-2">
              {items.map((item) => {
                const isExp = item.amount_cents < 0;
                const formattedAmount = `${isExp ? '-' : '+'}${Math.abs(item.amount).toFixed(2)}`;

                return (
                  <div
                    key={item.id}
                    className={`group bg-[var(--color-card-bg)] rounded-xl border border-[var(--color-neutral-stroke)] p-3.5 px-4.5 flex items-center justify-between shadow-[var(--shadow-card)] hover:shadow-[var(--shadow-card-hover)] hover:-translate-y-[1px] transition-all duration-150 ${
                      isExp ? 'border-l-4 border-l-[var(--color-expense)]' : 'border-l-4 border-l-[var(--color-income)]'
                    }`}
                  >
                    {/* Left: Category Icon & Details */}
                    <div className="flex items-center gap-3.5 flex-1 min-w-0">
                      <div className="w-9 h-9 rounded-lg bg-[var(--color-hover-bg)] text-[var(--color-neutral-fg-2)] text-sm font-semibold flex items-center justify-center flex-shrink-0">
                        {item.category_name ? item.category_name.charAt(0) : '记'}
                      </div>

                      <div className="flex flex-col gap-1 min-w-0 flex-1">
                        <div className="flex items-center gap-2 flex-wrap">
                          <span className="text-[14px] font-medium text-[var(--color-neutral-fg-1)] truncate">
                            {item.description}
                          </span>
                          <span
                            className={`text-[11px] font-medium px-1.5 py-0.5 rounded ${
                              isExp
                                ? 'bg-[var(--color-expense-bg)] text-[var(--color-expense-dark)]'
                                : 'bg-[var(--color-income-bg)] text-[var(--color-income-dark)]'
                            }`}
                          >
                            {item.category_name} · {item.tag_name}
                          </span>
                        </div>

                        <div className="flex items-center gap-1.5 text-xs text-[var(--color-neutral-fg-3)]">
                          <ClockIcon size={12} />
                          <span className="tabular-num">{formatTime(item.transacted_at)}</span>
                          <span className="opacity-40">·</span>
                          <span>{item.payment_method_name}</span>
                        </div>
                      </div>
                    </div>

                    {/* Right: Amount & Actions */}
                    <div className="flex items-center gap-4 flex-shrink-0 ml-3">
                      <span
                        className={`text-[16px] font-semibold tabular-num ${
                          isExp ? 'text-[var(--color-expense-dark)]' : 'text-[var(--color-income-dark)]'
                        }`}
                      >
                        {formattedAmount}
                      </span>

                      <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity duration-150">
                        <button
                          type="button"
                          title="编辑账单"
                          onClick={() => onEdit(item)}
                          className="w-7 h-7 rounded-md flex items-center justify-center text-[var(--color-neutral-fg-3)] hover:text-[var(--color-neutral-fg-1)] hover:bg-[var(--color-hover-bg)] cursor-pointer transition-colors"
                        >
                          <EditIcon size={14} />
                        </button>
                        <button
                          type="button"
                          title="删除账单"
                          onClick={() => onDelete(item.id)}
                          className="w-7 h-7 rounded-md flex items-center justify-center text-[var(--color-neutral-fg-3)] hover:text-[var(--color-expense-dark)] hover:bg-[var(--color-expense-bg)] cursor-pointer transition-colors"
                        >
                          <TrashIcon size={14} />
                        </button>
                      </div>
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
