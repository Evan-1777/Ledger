import type { FC } from 'react';
import { PlusIcon } from './Icons';

export type FilterType = 'all' | 'expense' | 'income';

interface BottomBarProps {
  showFilter: boolean;
  filter: FilterType;
  onFilterChange: (f: FilterType) => void;
  onOpenRecord: () => void;
}

export const BottomBar: FC<BottomBarProps> = ({
  showFilter,
  filter,
  onFilterChange,
  onOpenRecord,
}) => {
  return (
    <>
      {/* Bottom Floating Filter Capsule (Desktop centered, Mobile safe left-aligned) */}
      {showFilter && (
        <div className="fixed bottom-6 left-4 sm:left-1/2 sm:-translate-x-1/2 z-40 bg-[var(--color-card-bg)] rounded-full p-1 inline-flex items-center gap-1 shadow-[var(--shadow-capsule)] border border-[var(--color-neutral-stroke)] transition-all duration-200">
          <button
            type="button"
            onClick={() => onFilterChange('all')}
            className={`min-h-[40px] px-3.5 sm:px-4 py-1.5 rounded-full text-[13px] cursor-pointer transition-all duration-150 flex items-center justify-center ${
              filter === 'all'
                ? 'bg-[var(--color-canvas-bg)] text-[var(--color-neutral-fg-1)] font-semibold shadow-[0_1px_3px_rgba(0,0,0,0.06)]'
                : 'text-[var(--color-neutral-fg-3)] font-medium hover:text-[var(--color-neutral-fg-1)]'
            }`}
          >
            全部
          </button>
          <button
            type="button"
            onClick={() => onFilterChange('expense')}
            className={`min-h-[40px] px-3.5 sm:px-4 py-1.5 rounded-full text-[13px] cursor-pointer transition-all duration-150 flex items-center justify-center ${
              filter === 'expense'
                ? 'bg-[var(--color-canvas-bg)] text-[var(--color-neutral-fg-1)] font-semibold shadow-[0_1px_3px_rgba(0,0,0,0.06)]'
                : 'text-[var(--color-neutral-fg-3)] font-medium hover:text-[var(--color-neutral-fg-1)]'
            }`}
          >
            支出
          </button>
          <button
            type="button"
            onClick={() => onFilterChange('income')}
            className={`min-h-[40px] px-3.5 sm:px-4 py-1.5 rounded-full text-[13px] cursor-pointer transition-all duration-150 flex items-center justify-center ${
              filter === 'income'
                ? 'bg-[var(--color-canvas-bg)] text-[var(--color-neutral-fg-1)] font-semibold shadow-[0_1px_3px_rgba(0,0,0,0.06)]'
                : 'text-[var(--color-neutral-fg-3)] font-medium hover:text-[var(--color-neutral-fg-1)]'
            }`}
          >
            收入
          </button>
        </div>
      )}

      {/* Bottom Right Floating Action Button (FAB) */}
      <button
        type="button"
        title="记账 (快捷键 N)"
        onClick={onOpenRecord}
        className="fixed bottom-6 right-4 sm:right-8 z-40 w-[52px] h-[52px] rounded-full bg-[var(--color-brand)] text-white border-none cursor-pointer flex items-center justify-center shadow-[var(--shadow-fab)] hover:scale-105 hover:bg-[var(--color-brand-hover)] active:scale-95 transition-all duration-150"
      >
        <PlusIcon size={22} />
      </button>
    </>
  );
};
