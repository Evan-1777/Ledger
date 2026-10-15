import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import {
  formatAmount,
  formatMoney,
  formatPercent,
  resolveTone,
  toLocalInputValue,
  fromLocalInputValue,
} from '../src/lib/format.ts';

describe('format - formatMoney', () => {
  test('adds explicit minus sign for negative values', () => {
    assert.strictEqual(formatMoney(-1234.5), '−¥1,234.50');
  });

  test('adds plus sign for positive values by default', () => {
    assert.strictEqual(formatMoney(0.5), '+¥0.50');
  });

  test('suppresses sign when requested', () => {
    assert.strictEqual(formatMoney(-42, { sign: 'none' }), '¥42.00');
  });

  test('renders zero without a sign', () => {
    assert.strictEqual(formatMoney(0), '¥0.00');
  });

  test('omits currency symbol when requested', () => {
    assert.strictEqual(formatMoney(1234.5, { sign: 'none', currency: false }), '1,234.50');
    assert.strictEqual(formatMoney(-42, { sign: 'none', currency: false }), '42.00');
    assert.strictEqual(formatMoney(0, { sign: 'none', currency: false }), '0.00');
  });
});

describe('format - formatPercent', () => {
  test('formats finite ratio with one decimal', () => {
    assert.strictEqual(formatPercent(13.75), '13.8%');
  });

  test('falls back to placeholder for non-finite input', () => {
    assert.strictEqual(formatPercent(Number.NaN), '--');
    assert.strictEqual(formatPercent(1 / 0), '--');
  });
});

describe('format - resolveTone', () => {
  test('maps known transaction types to semantic tones', () => {
    assert.strictEqual(resolveTone('income'), 'income');
    assert.strictEqual(resolveTone('transfer'), 'transfer');
    assert.strictEqual(resolveTone('repayment'), 'repay');
  });

  test('falls back to expense for unknown or missing types', () => {
    assert.strictEqual(resolveTone('expense'), 'expense');
    assert.strictEqual(resolveTone('weird'), 'expense');
    assert.strictEqual(resolveTone(null), 'expense');
  });
});

describe('format - date round-trip', () => {
  test('converts ISO to local input value and back', () => {
    const local = new Date(2026, 9, 14, 12, 40);
    const input = toLocalInputValue(local.toISOString());
    assert.strictEqual(input, '2026-10-14T12:40');
    const back = new Date(fromLocalInputValue(input));
    assert.strictEqual(back.getFullYear(), 2026);
    assert.strictEqual(back.getMonth(), 9);
    assert.strictEqual(back.getDate(), 14);
    assert.strictEqual(back.getHours(), 12);
    assert.strictEqual(back.getMinutes(), 40);
  });

  test('returns empty string for invalid inputs', () => {
    assert.strictEqual(toLocalInputValue('garbage'), '');
    assert.strictEqual(fromLocalInputValue('garbage'), '');
  });
});

describe('format - formatAmount re-export parity', () => {
  test('formatAmount keeps original contract', () => {
    const res = formatAmount(45.5, 'expense', -4550);
    assert.strictEqual(res.formattedText, '−¥45.50');
  });
});
