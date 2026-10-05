import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import {
  getDayInfo,
  formatTime,
  buildMetaParts,
  formatAmount,
} from '../src/pages/streamUtils.ts';

describe('streamUtils - getDayInfo', () => {
  // Base date: 2026-10-04 (Sunday)
  const baseDate = new Date(2026, 9, 4, 12, 0, 0);

  test('correctly identifies "今天" and derives local weekday', () => {
    const info = getDayInfo('2026-10-04', baseDate);
    assert.strictEqual(info.primary, '今天');
    assert.strictEqual(info.sub, '10月4日 周日');
  });

  test('correctly identifies "昨天" and derives local weekday', () => {
    const info = getDayInfo('2026-10-03', baseDate);
    assert.strictEqual(info.primary, '昨天');
    assert.strictEqual(info.sub, '10月3日 周六');
  });

  test('formats same-year dates as M月D日 with weekday', () => {
    const info = getDayInfo('2026-09-15', baseDate);
    assert.strictEqual(info.primary, '9月15日');
    assert.strictEqual(info.sub, '周二');
  });

  test('formats cross-year dates as YYYY年M月D日 with weekday', () => {
    const info = getDayInfo('2025-12-31', baseDate);
    assert.strictEqual(info.primary, '2025年12月31日');
    assert.strictEqual(info.sub, '周三');
  });

  test('gracefully handles malformed or incomplete date strings', () => {
    const info = getDayInfo('invalid-date', baseDate);
    assert.strictEqual(info.primary, 'invalid-date');
    assert.strictEqual(info.sub, '');
  });
});

describe('streamUtils - formatTime', () => {
  test('formats valid ISO time string to HH:mm', () => {
    const d = new Date(2026, 9, 4, 9, 5);
    const timeStr = formatTime(d.toISOString());
    assert.strictEqual(timeStr, '09:05');
  });

  test('returns empty string for invalid date', () => {
    assert.strictEqual(formatTime('invalid'), '');
  });
});

describe('streamUtils - buildMetaParts', () => {
  test('builds full 4-part meta for standard expense/income', () => {
    const parts = buildMetaParts({
      category_name: '餐饮美食',
      tag_name: '午餐',
      payment_method_name: '招商银行',
      transacted_at: new Date(2026, 9, 4, 12, 30).toISOString(),
    });
    assert.deepStrictEqual(parts, ['餐饮美食', '午餐', '招商银行', '12:30']);
  });

  test('builds bilateral flow for transfer with source and target', () => {
    const parts = buildMetaParts({
      category_name: '账户转账',
      type: 'transfer',
      source_payment_method_name: '工商银行',
      payment_method_name: '招商银行',
    });
    assert.deepStrictEqual(parts, ['账户转账', '工商银行 → 招商银行']);
  });

  test('builds fallback flow for transfer with target only', () => {
    const parts = buildMetaParts({
      type: 'transfer',
      payment_method_name: '招商银行',
    });
    assert.deepStrictEqual(parts, ['转入 招商银行']);
  });

  test('builds bilateral flow for repayment with source and target', () => {
    const parts = buildMetaParts({
      type: 'repayment',
      source_payment_method_name: '招商银行',
      payment_method_name: '花呗',
    });
    assert.deepStrictEqual(parts, ['招商银行 → 花呗']);
  });

  test('excludes null or empty fields without producing blank items', () => {
    const parts = buildMetaParts({
      category_name: '工资',
      tag_name: null,
      payment_method_name: '',
      transacted_at: null,
    });
    assert.deepStrictEqual(parts, ['工资']);
  });

  test('builds bilateral flow with fee for transfer before time', () => {
    const parts = buildMetaParts({
      category_name: '账户转账',
      tag_name: '资金互转',
      type: 'transfer',
      source_payment_method_name: '招商银行',
      payment_method_name: '微信零钱',
      fee: 2.0,
      transacted_at: new Date(2026, 9, 4, 15, 30).toISOString(),
    });
    assert.deepStrictEqual(parts, ['账户转账', '资金互转', '招商银行 → 微信零钱', '手续费 ¥2.00', '15:30']);
  });

  test('does not output fee when fee is 0 or null', () => {
    const parts = buildMetaParts({
      category_name: '账户转账',
      tag_name: '资金互转',
      type: 'transfer',
      source_payment_method_name: '招商银行',
      payment_method_name: '微信零钱',
      fee: 0,
      transacted_at: new Date(2026, 9, 4, 15, 30).toISOString(),
    });
    assert.deepStrictEqual(parts, ['账户转账', '资金互转', '招商银行 → 微信零钱', '15:30']);
  });
});

describe('streamUtils - formatAmount', () => {
  test('formats expense with minus sign and two decimal places', () => {
    const res = formatAmount(45.5, 'expense', -4550);
    assert.strictEqual(res.sign, '−');
    assert.strictEqual(res.amountStr, '45.50');
    assert.strictEqual(res.formattedText, '−¥45.50');
  });

  test('formats legacy expense with negative amount_cents when type is missing', () => {
    const res = formatAmount(-120, undefined, -12000);
    assert.strictEqual(res.sign, '−');
    assert.strictEqual(res.amountStr, '120.00');
    assert.strictEqual(res.formattedText, '−¥120.00');
  });

  test('formats income with plus sign', () => {
    const res = formatAmount(8000, 'income', 800000);
    assert.strictEqual(res.sign, '+');
    assert.strictEqual(res.amountStr, '8,000.00');
    assert.strictEqual(res.formattedText, '+¥8,000.00');
  });

  test('formats transfer and repayment neutrally without sign', () => {
    const transfer = formatAmount(500, 'transfer');
    assert.strictEqual(transfer.sign, '');
    assert.strictEqual(transfer.formattedText, '¥500.00');

    const repayment = formatAmount(1500.8, 'repayment');
    assert.strictEqual(repayment.sign, '');
    assert.strictEqual(repayment.formattedText, '¥1,500.80');
  });

  test('formats large numbers with proper comma grouping', () => {
    const res = formatAmount(1234567.89, 'income');
    assert.strictEqual(res.amountStr, '1,234,567.89');
    assert.strictEqual(res.formattedText, '+¥1,234,567.89');
  });
});
