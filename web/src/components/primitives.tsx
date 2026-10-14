import { useEffect, useRef } from 'react';
import type { FC, ReactNode } from 'react';
import {
  ExpenseIcon,
  IncomeIcon,
  TransferIcon,
  RepaymentIcon,
} from './Icons';
import { resolveTone } from '../lib/format.ts';
import type { AmountTone } from '../lib/format.ts';

/* ============================== Panel ============================== */

interface PanelProps {
  variant?: 'plain' | 'hero';
  className?: string;
  children: ReactNode;
}

export const Panel: FC<PanelProps> = ({ variant = 'plain', className = '', children }) => {
  const base =
    variant === 'hero'
      ? 'bg-[var(--surface)] border border-[var(--brand-line)] shadow-[var(--e3),inset_0_1px_0_var(--highlight-top)] rounded-[var(--r-xl)]'
      : 'bg-[var(--surface)] border border-[var(--line)] shadow-[var(--e1),inset_0_1px_0_var(--highlight-top)] rounded-[var(--r-lg)]';
  return <div className={`${base} ${className}`}>{children}</div>;
};

/* ============================== IconButton ============================== */

interface IconButtonProps {
  label: string;
  tone?: 'neutral' | 'danger';
  size?: number;
  onClick?: (e: React.MouseEvent<HTMLButtonElement>) => void;
  disabled?: boolean;
  className?: string;
  children: ReactNode;
}

export const IconButton: FC<IconButtonProps> = ({
  label,
  tone = 'neutral',
  size = 34,
  onClick,
  disabled,
  className = '',
  children,
}) => (
  <button
    type="button"
    aria-label={label}
    title={label}
    disabled={disabled}
    onClick={onClick}
    style={{ width: size, height: size }}
    className={`rounded-[var(--r-sm)] flex items-center justify-center cursor-pointer transition-all duration-[var(--d1)] disabled:opacity-30 disabled:cursor-not-allowed active:scale-[.94] ${
      tone === 'danger'
        ? 'text-[var(--fg-3)] hover:text-[var(--expense-text)] hover:bg-[var(--expense-soft)]'
        : 'text-[var(--fg-3)] hover:text-[var(--fg)] hover:bg-[var(--surface-hover)]'
    } ${className}`}
  >
    {children}
  </button>
);

/* ============================== Button ============================== */

type ButtonVariant = 'primary' | 'subtle' | 'ghost' | 'danger';
type ButtonSize = 'sm' | 'md' | 'lg';

interface ButtonProps {
  variant?: ButtonVariant;
  size?: ButtonSize;
  type?: 'button' | 'submit';
  disabled?: boolean;
  onClick?: (e: React.MouseEvent<HTMLButtonElement>) => void;
  className?: string;
  /** React 19: ref passes through as a plain prop */
  ref?: React.Ref<HTMLButtonElement>;
  children: ReactNode;
}

const BUTTON_VARIANT: Record<ButtonVariant, string> = {
  primary:
    'bg-[var(--brand)] text-white hover:bg-[var(--brand-hover)] shadow-[0_2px_8px_rgba(0,120,212,0.28)]',
  subtle:
    'bg-[var(--surface-sunken)] text-[var(--fg-2)] border border-[var(--line)] hover:bg-[var(--surface-hover)] hover:text-[var(--fg)]',
  ghost: 'bg-transparent text-[var(--fg-2)] hover:bg-[var(--surface-hover)]',
  danger: 'bg-[var(--expense)] text-white hover:brightness-95',
};

const BUTTON_SIZE: Record<ButtonSize, string> = {
  sm: 'px-3 py-1.5 text-xs',
  md: 'px-4 py-2 text-[13px]',
  lg: 'px-5 py-2.5 text-sm',
};

export const Button: FC<ButtonProps> = ({
  variant = 'primary',
  size = 'md',
  type = 'button',
  disabled,
  onClick,
  className = '',
  ref,
  children,
}) => (
  <button
    ref={ref}
    type={type}
    disabled={disabled}
    onClick={onClick}
    className={`inline-flex items-center justify-center gap-1.5 rounded-[var(--r-sm)] font-semibold cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed active:scale-[.97] transition-all duration-[var(--d1)] ${BUTTON_VARIANT[variant]} ${BUTTON_SIZE[size]} ${className}`}
  >
    {children}
  </button>
);

/* ============================== SegmentedControl ============================== */

export interface SegmentedItem {
  key: string;
  label: ReactNode;
  icon?: ReactNode;
}

interface SegmentedControlProps {
  items: SegmentedItem[];
  value: string;
  onChange: (key: string) => void;
  ariaLabel?: string;
  /** compact: hide text labels below the breakpoint, icons only ('sm' = 640px, 'xs' = 400px) */
  compact?: boolean | 'xs';
  className?: string;
}

export const SegmentedControl: FC<SegmentedControlProps> = ({
  items,
  value,
  onChange,
  ariaLabel,
  compact = false,
  className = '',
}) => {
  const activeIndex = Math.max(
    0,
    items.findIndex((it) => it.key === value)
  );
  const n = items.length;
  const labelClass =
    compact === true ? 'hidden min-[640px]:inline' : compact === 'xs' ? 'hidden min-[400px]:inline' : undefined;

  return (
    <div
      role="tablist"
      aria-label={ariaLabel}
      className={`relative grid gap-[2px] p-[3px] bg-[var(--surface-sunken)] border border-[var(--line)] rounded-[var(--r-pill)] ${className}`}
      style={{ gridAutoFlow: 'column', gridAutoColumns: '1fr' }}
    >
      {/* Shared-position sliding indicator */}
      <div
        aria-hidden
        className="absolute top-[3px] bottom-[3px] left-[3px] rounded-[var(--r-pill)] bg-[var(--surface)] shadow-[var(--e1)] transition-transform duration-[var(--d2)] [transition-timing-function:var(--ease-out)]"
        style={{
          width: `calc((100% - ${2 * 3 + (n - 1) * 2}px) / ${n})`,
          transform: `translateX(calc(${activeIndex} * (100% + 2px)))`,
        }}
      />
      {items.map((it) => {
        const selected = it.key === value;
        return (
          <button
            key={it.key}
            type="button"
            role="tab"
            aria-selected={selected}
            onClick={() => onChange(it.key)}
            className={`relative z-[1] flex items-center justify-center gap-1.5 min-h-[32px] px-2.5 rounded-[var(--r-pill)] text-[13px] cursor-pointer whitespace-nowrap transition-colors duration-[var(--d1)] [transition-timing-function:var(--ease-std)] ${
              selected ? 'text-[var(--fg)] font-semibold' : 'text-[var(--fg-3)] font-medium hover:text-[var(--fg)]'
            }`}
          >
            {it.icon}
            <span className={labelClass}>{it.label}</span>
          </button>
        );
      })}
    </div>
  );
};

/* ============================== Chip / Badge ============================== */

interface ChipProps {
  tone?: 'neutral' | 'brand';
  className?: string;
  children: ReactNode;
}

export const Chip: FC<ChipProps> = ({ tone = 'neutral', className = '', children }) => (
  <span
    className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-[var(--r-pill)] text-[11.5px] font-semibold ${
      tone === 'brand'
        ? 'bg-[var(--brand-soft)] border border-[var(--brand-line)] text-[var(--brand-text)]'
        : 'bg-[var(--surface-sunken)] border border-[var(--line)] text-[var(--fg-2)]'
    } ${className}`}
  >
    {children}
  </span>
);

export const Badge = Chip;

/* ============================== Amount ============================== */

type AmountSize = 'hero' | 'lg' | 'md' | 'sm';

const AMOUNT_SIZE: Record<AmountSize, string> = {
  hero: 'text-[34px] min-[720px]:text-[40px] font-[680] tracking-[-.028em]',
  lg: 'text-[19px] font-semibold tracking-[-.02em]',
  md: 'text-[15px] font-semibold',
  sm: 'text-[12.5px] font-semibold',
};

const AMOUNT_TONE: Record<AmountTone, string> = {
  expense: 'text-[var(--expense-text)]',
  income: 'text-[var(--income-text)]',
  transfer: 'text-[var(--transfer-text)]',
  repay: 'text-[var(--repay-text)]',
};

interface AmountProps {
  value: string;
  tone?: AmountTone;
  size?: AmountSize;
  type?: string | null;
  className?: string;
}

export const Amount: FC<AmountProps> = ({ value, tone, size = 'md', type, className = '' }) => {
  const resolvedTone = tone ?? resolveTone(type);
  return <span className={`num ${AMOUNT_SIZE[size]} ${AMOUNT_TONE[resolvedTone]} ${className}`}>{value}</span>;
};

/* ============================== TypeTile ============================== */

interface TypeTileProps {
  type?: string | null;
}

export const TypeTile: FC<TypeTileProps> = ({ type }) => {
  const style: Record<AmountTone, string> = {
    expense: 'bg-[var(--expense-soft)] text-[var(--expense-text)]',
    income: 'bg-[var(--income-soft)] text-[var(--income-text)]',
    transfer: 'bg-[var(--transfer-soft)] text-[var(--transfer-text)]',
    repay: 'bg-[var(--repay-soft)] text-[var(--repay-text)]',
  };
  const tone = resolveTone(type);
  const icon =
    tone === 'expense' ? (
      <ExpenseIcon size={16} />
    ) : tone === 'income' ? (
      <IncomeIcon size={16} />
    ) : tone === 'transfer' ? (
      <TransferIcon size={16} />
    ) : (
      <RepaymentIcon size={16} />
    );
  return (
    <div
      aria-hidden
      className={`w-8 h-8 rounded-[var(--r-sm)] flex items-center justify-center flex-shrink-0 ${style[tone]}`}
    >
      {icon}
    </div>
  );
};

/* ============================== Rail ============================== */

interface RailProps {
  value: number;
  color?: string;
  className?: string;
}

export const Rail: FC<RailProps> = ({ value, color = 'var(--brand)', className = '' }) => (
  <div
    aria-hidden
    className={`h-1 rounded-[2px] bg-[var(--surface-sunken)] overflow-hidden ${className}`}
  >
    <div
      className="h-full rounded-[2px] transition-[width] duration-[var(--d3)] [transition-timing-function:var(--ease-out)]"
      style={{ width: `${Math.min(Math.max(value, 0), 100)}%`, background: color }}
    />
  </div>
);

/* ============================== Skeleton ============================== */

export const Skeleton: FC<{ className?: string }> = ({ className = '' }) => (
  <div aria-hidden className={`animate-pulse-soft bg-[var(--surface-sunken)] rounded-[var(--r-xs)] ${className}`} />
);

/** Day-group skeleton mirroring the real stream structure */
export const SkeletonList: FC<{ groups?: number }> = ({ groups = 2 }) => (
  <div aria-hidden className="flex flex-col gap-4">
    {Array.from({ length: groups }).map((_, g) => (
      <div key={g} className="bg-[var(--surface)] border border-[var(--line)] rounded-[var(--r-md)] shadow-[var(--e1)] overflow-hidden">
        <div className="flex items-center justify-between px-3.5 py-[9px] bg-[var(--surface-sunken)] border-b border-[var(--line)]">
          <Skeleton className="h-3.5 w-24" />
          <Skeleton className="h-3 w-28" />
        </div>
        <div>
          {Array.from({ length: 3 }).map((_, r) => (
            <div key={r} className="flex items-center gap-3 px-3.5 py-2.5">
              <Skeleton className="w-8 h-8 rounded-[var(--r-sm)] flex-shrink-0" />
              <div className="flex-1 flex flex-col gap-1.5">
                <Skeleton className="h-3.5 w-2/5" />
                <Skeleton className="h-3 w-3/5" />
              </div>
              <Skeleton className="h-4 w-20" />
            </div>
          ))}
        </div>
      </div>
    ))}
  </div>
);

/* ============================== EmptyState ============================== */

interface EmptyStateProps {
  icon?: ReactNode;
  title: string;
  subtitle?: string;
  action?: { label: string; onClick: () => void };
}

export const EmptyState: FC<EmptyStateProps> = ({ icon, title, subtitle, action }) => (
  <div className="flex flex-col items-center text-center gap-1 px-4 py-14">
    <div className="w-[52px] h-[52px] rounded-full bg-[var(--surface-sunken)] border border-[var(--line)] text-[var(--fg-muted)] flex items-center justify-center mb-2">
      {icon}
    </div>
    <b className="text-sm font-semibold text-[var(--fg)]">{title}</b>
    {subtitle && <span className="text-[12.5px] text-[var(--fg-3)]">{subtitle}</span>}
    {action && (
      <div className="mt-4">
        <Button variant="primary" size="md" onClick={action.onClick}>
          {action.label}
        </Button>
      </div>
    )}
  </div>
);

/* ============================== ConfirmDialog ============================== */

export interface ConfirmDialogProps {
  open: boolean;
  title: string;
  description?: string;
  detail?: string;
  confirmLabel?: string;
  cancelLabel?: string;
  tone?: 'danger' | 'neutral';
  loading?: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}

export const ConfirmDialog: FC<ConfirmDialogProps> = ({
  open,
  title,
  description,
  detail,
  confirmLabel = '确认',
  cancelLabel = '取消',
  tone = 'neutral',
  loading = false,
  onConfirm,
  onCancel,
}) => {
  const cancelRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (!open) return;
    cancelRef.current?.focus();
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onCancel();
    };
    window.addEventListener('keydown', handleKey);
    return () => window.removeEventListener('keydown', handleKey);
  }, [open, onCancel]);

  if (!open) return null;

  return (
    <div
      className="fixed inset-0 z-[1200] bg-[rgba(8,12,20,.44)] backdrop-blur-[4px] flex items-center justify-center p-3 animate-fade"
      onClick={onCancel}
    >
      <div
        role="alertdialog"
        aria-modal="true"
        aria-label={title}
        onClick={(e) => e.stopPropagation()}
        className="w-full max-w-[400px] bg-[var(--surface)] border border-[var(--line)] rounded-[var(--r-xl)] shadow-[var(--e4),inset_0_1px_0_var(--highlight-top)] animate-pop"
      >
        <div className="px-[18px] py-3.5 border-b border-[var(--line)] flex items-center">
          <b className="text-[15px] font-semibold text-[var(--fg)]">{title}</b>
        </div>
        <div className="px-[18px] py-4 flex flex-col gap-1.5">
          {description && <div className="text-[13.5px] leading-relaxed text-[var(--fg)]">{description}</div>}
          {detail && <div className="text-[12.5px] text-[var(--fg-3)]">{detail}</div>}
        </div>
        <div className="px-[18px] py-3 border-t border-[var(--line)] flex justify-end gap-2">
          <Button variant="ghost" size="md" onClick={onCancel} disabled={loading} ref={cancelRef}>
            {cancelLabel}
          </Button>
          <Button variant={tone === 'danger' ? 'danger' : 'primary'} size="md" onClick={onConfirm} disabled={loading}>
            {loading ? '处理中…' : confirmLabel}
          </Button>
        </div>
      </div>
    </div>
  );
};
