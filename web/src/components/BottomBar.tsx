import type { FC } from 'react';
import { PlusIcon } from './Icons';

export type FilterType = 'all' | 'expense' | 'income' | 'transfer' | 'repayment';

interface BottomBarProps {
  showFilter: boolean;
  filter: FilterType;
  onFilterChange: (f: FilterType) => void;
  onOpenRecord: () => void;
}

const FILTER_OPTIONS: { key: FilterType; label: string }[] = [
  { key: 'all', label: '全部' },
  { key: 'expense', label: '支出' },
  { key: 'income', label: '收入' },
  { key: 'transfer', label: '转账' },
  { key: 'repayment', label: '还款' },
];

export const BottomBar: FC<BottomBarProps> = ({
  showFilter,
  filter,
  onFilterChange,
  onOpenRecord,
}) => {
  return (
    <>
      {/* Floating Filter Capsule: glass + blur; ≥640px centered, <640px left-safe */}
      {showFilter && (
        <div
          role="tablist"
          aria-label="流水筛选"
          className="fixed bottom-[18px] left-3 z-40 flex gap-[2px] p-1 rounded-[var(--r-pill)]
            bg-[var(--glass)] backdrop-blur-[18px] saturate-150
            border border-[var(--line)] shadow-[var(--e3),inset_0_1px_0_var(--highlight-top)]
            min-[640px]:left-1/2 min-[640px]:right-auto min-[640px]:-translate-x-1/2"
        >
          {FILTER_OPTIONS.map((opt) => {
            const selected = filter === opt.key;
            return (
              <button
                key={opt.key}
                type="button"
                role="tab"
                aria-selected={selected}
                onClick={() => onFilterChange(opt.key)}
                className={`min-h-[36px] px-2.5 min-[640px]:px-[11px] rounded-[var(--r-pill)] text-[13px] cursor-pointer whitespace-nowrap transition-colors duration-[var(--d1)] ${
                  selected
                    ? 'bg-[var(--surface-sunken)] text-[var(--fg)] font-semibold'
                    : 'text-[var(--fg-3)] font-medium hover:text-[var(--fg)]'
                }`}
              >
                {opt.label}
              </button>
            );
          })}
        </div>
      )}

      {/* FAB */}
      <button
        type="button"
        aria-label="记账"
        title="记账 (快捷键 N)"
        onClick={onOpenRecord}
        className="fixed bottom-[18px] right-4 min-[640px]:right-7 z-40 w-[52px] h-[52px] rounded-full
          bg-[var(--brand)] text-white border-none cursor-pointer flex items-center justify-center
          shadow-[0_4px_14px_rgba(0,120,212,.38),0_2px_6px_rgba(16,24,40,.12),inset_0_1px_0_rgba(255,255,255,.22)]
          hover:bg-[var(--brand-hover)] hover:scale-105 active:scale-[.94]
          transition-all duration-[var(--d1)] [transition-timing-function:var(--ease-out)]"
      >
        <PlusIcon size={22} />
      </button>
    </>
  );
};
