export const WEEKDAYS = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'] as const;

export interface DayInfo {
  primary: string;
  sub: string;
}

export function getDayInfo(dateStr: string, baseDate: Date = new Date()): DayInfo {
  try {
    const pad = (n: number) => String(n).padStart(2, '0');
    const todayStr = `${baseDate.getFullYear()}-${pad(baseDate.getMonth() + 1)}-${pad(baseDate.getDate())}`;

    const yesterday = new Date(baseDate);
    yesterday.setDate(yesterday.getDate() - 1);
    const yesterdayStr = `${yesterday.getFullYear()}-${pad(yesterday.getMonth() + 1)}-${pad(yesterday.getDate())}`;

    const parts = dateStr.split('-');
    if (parts.length === 3) {
      const year = parseInt(parts[0], 10);
      const month = parseInt(parts[1], 10);
      const day = parseInt(parts[2], 10);
      if (Number.isNaN(year) || Number.isNaN(month) || Number.isNaN(day)) {
        return { primary: dateStr, sub: '' };
      }
      const localDate = new Date(year, month - 1, day);
      const weekday = WEEKDAYS[localDate.getDay()];

      if (dateStr === todayStr) {
        return {
          primary: '今天',
          sub: `${month}月${day}日 ${weekday}`,
        };
      }
      if (dateStr === yesterdayStr) {
        return {
          primary: '昨天',
          sub: `${month}月${day}日 ${weekday}`,
        };
      }
      if (year !== baseDate.getFullYear()) {
        return {
          primary: `${year}年${month}月${day}日`,
          sub: weekday,
        };
      }
      return {
        primary: `${month}月${day}日`,
        sub: weekday,
      };
    }
    return { primary: dateStr, sub: '' };
  } catch {
    return { primary: dateStr, sub: '' };
  }
}

export function formatTime(isoStr: string): string {
  try {
    const d = new Date(isoStr);
    if (Number.isNaN(d.getTime())) return '';
    const pad = (n: number) => String(n).padStart(2, '0');
    return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
  } catch {
    return '';
  }
}

export interface MetaItemInput {
  category_name?: string | null;
  tag_name?: string | null;
  payment_method_name?: string | null;
  source_payment_method_name?: string | null;
  type?: string | null;
  fee?: number | null;
  transacted_at?: string | null;
}

export function buildMetaParts(item: MetaItemInput): string[] {
  const metaParts: string[] = [];
  if (item.category_name) metaParts.push(item.category_name);
  if (item.tag_name) metaParts.push(item.tag_name);

  const isRepayment = item.type === 'repayment';
  const isTransfer = item.type === 'transfer';

  if (isTransfer || isRepayment) {
    if (item.source_payment_method_name && item.payment_method_name) {
      metaParts.push(`${item.source_payment_method_name} → ${item.payment_method_name}`);
    } else if (item.payment_method_name) {
      metaParts.push(`${isTransfer ? '转入' : '还入'} ${item.payment_method_name}`);
    }
  } else if (item.payment_method_name) {
    metaParts.push(item.payment_method_name);
  }

  if (isTransfer && item.fee && item.fee > 0) {
    metaParts.push(`手续费 ¥${item.fee.toFixed(2)}`);
  }

  if (item.transacted_at) {
    const timeStr = formatTime(item.transacted_at);
    if (timeStr) metaParts.push(timeStr);
  }

  return metaParts;
}

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
