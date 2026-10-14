import type { FC } from 'react';
import { CheckIcon, AlertIcon, InfoIcon, CloseIcon } from './Icons';

export interface ToastMessage {
  id: string;
  type: 'success' | 'error' | 'info';
  message: string;
}

interface ToastProps {
  toasts: ToastMessage[];
  onDismiss: (id: string) => void;
}

const TOAST_SEMANTICS = {
  success: { color: 'var(--income-text)', icon: <CheckIcon size={16} /> },
  error: { color: 'var(--expense-text)', icon: <AlertIcon size={16} /> },
  info: { color: 'var(--brand-text)', icon: <InfoIcon size={16} /> },
} as const;

export const Toast: FC<ToastProps> = ({ toasts, onDismiss }) => {
  if (toasts.length === 0) return null;

  return (
    <div
      aria-live="polite"
      className="fixed z-[2000] flex flex-col gap-2 pointer-events-none
        left-3 right-3 bottom-[88px] items-center
        min-[640px]:left-auto min-[640px]:right-7 min-[640px]:top-[72px] min-[640px]:bottom-auto min-[640px]:items-end"
    >
      {[...toasts].reverse().map((t) => {
        const s = TOAST_SEMANTICS[t.type];
        return (
          <div
            key={t.id}
            className="pointer-events-auto flex items-center gap-2.5 px-3.5 py-2.5 rounded-[var(--r-pill)]
              bg-[var(--surface)] border border-[var(--line)] shadow-[var(--e3)]
              text-[13px] font-medium animate-toast-in max-w-full"
          >
            <span style={{ color: s.color }} className="flex-shrink-0 flex">
              {s.icon}
            </span>
            <span className="text-[var(--fg)] truncate">{t.message}</span>
            <button
              type="button"
              aria-label="关闭通知"
              onClick={() => onDismiss(t.id)}
              className="flex-shrink-0 p-0.5 rounded text-[var(--fg-3)] hover:text-[var(--fg)] cursor-pointer transition-colors"
            >
              <CloseIcon size={13} />
            </button>
          </div>
        );
      })}
    </div>
  );
};
