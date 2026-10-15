export interface FormattedAmount {
  sign: string;
  amountStr: string;
  formattedText: string;
}

export function formatAmount(
  amount: number,
  type?: string | null,
  amountCents?: number | null
): FormattedAmount {
  const isRepayment = type === 'repayment';
  const isTransfer = type === 'transfer';
  const isNeutral = isRepayment || isTransfer;
  const isExp = type === 'expense' || (!type && (amountCents ?? 0) < 0);

  const absAmount = Math.abs(amount);
  const amountStr = absAmount.toLocaleString('zh-CN', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
  const sign = isNeutral ? '' : isExp ? '−' : '+';
  return {
    sign,
    amountStr,
    formattedText: `${sign}¥${amountStr}`,
  };
}

export function formatMoney(
  value: number,
  opts?: { sign?: 'auto' | 'none'; withCurrency?: boolean }
): string {
  const sign = opts?.sign === 'none' ? '' : value < 0 ? '−' : value > 0 ? '+' : '';
  const abs = Math.abs(value);
  const amountStr = abs.toLocaleString('zh-CN', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
  return `${sign}${opts?.withCurrency === false ? '' : '¥'}${amountStr}`;
}

export function formatPercent(value: number, digits: number = 1): string {
  if (!Number.isFinite(value)) return '--';
  return `${value.toFixed(digits)}%`;
}

export type AmountTone = 'expense' | 'income' | 'transfer' | 'repay';

export function resolveTone(type?: string | null): AmountTone {
  switch (type) {
    case 'income':
      return 'income';
    case 'transfer':
      return 'transfer';
    case 'repayment':
      return 'repay';
    default:
      return 'expense';
  }
}

/** ISO string → `YYYY-MM-DDTHH:mm` for datetime-local inputs */
export function toLocalInputValue(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

/** `YYYY-MM-DDTHH:mm` from a datetime-local input → ISO string (or '' when invalid) */
export function fromLocalInputValue(str: string): string {
  const d = new Date(str);
  if (Number.isNaN(d.getTime())) return '';
  return d.toISOString();
}
