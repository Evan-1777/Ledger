import type { FC } from 'react';

export interface ToastMessage {
  id: string;
  type: 'success' | 'error' | 'info';
  message: string;
}

interface ToastProps {
  toasts: ToastMessage[];
  onDismiss: (id: string) => void;
}

export const Toast: FC<ToastProps> = ({ toasts, onDismiss }) => {
  if (toasts.length === 0) return null;

  return (
    <div className="fixed top-20 right-8 z-[2000] flex flex-col gap-2 max-w-sm w-full pointer-events-none">
      {toasts.map((t) => (
        <div
          key={t.id}
          className={`pointer-events-auto flex items-center justify-between p-3.5 rounded-xl shadow-[var(--shadow-modal)] border text-[13.5px] font-medium transition-all duration-200 animate-fade-in ${
            t.type === 'error'
              ? 'bg-[var(--color-card-bg)] text-[var(--color-expense-dark)] border-[var(--color-expense-stroke)]'
              : t.type === 'success'
              ? 'bg-[var(--color-card-bg)] text-[var(--color-income-dark)] border-[var(--color-income-stroke)]'
              : 'bg-[var(--color-card-bg)] text-[var(--color-neutral-fg-1)] border-[var(--color-neutral-stroke-strong)]'
          }`}
        >
          <span>{t.message}</span>
          <button
            type="button"
            onClick={() => onDismiss(t.id)}
            className="ml-3 text-[var(--color-neutral-fg-3)] hover:text-[var(--color-neutral-fg-1)] cursor-pointer text-xs"
          >
            ✕
          </button>
        </div>
      ))}
    </div>
  );
};
