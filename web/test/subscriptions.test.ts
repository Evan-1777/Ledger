import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import {
  buildSubscriptionSections,
  calendarDayDiff,
  formatRenewalDate,
  nextRenewalDate,
  summarizeSubscriptions,
} from '../src/pages/subscriptionsUtils.ts';
import type { Subscription, SubscriptionGroup } from '../src/lib/api.ts';

const sub = (
  id: number,
  name: string,
  groupId: number | null,
  amountCents: number,
  billingDay: number,
  status: 'active' | 'paused' = 'active'
): Subscription => ({
  id,
  group_id: groupId,
  name,
  amount_cents: amountCents,
  amount: amountCents / 100,
  billing_day: billingDay,
  status,
  created_at: '2026-10-01T00:00:00Z',
});

const group = (id: number, name: string, sortOrder: number): SubscriptionGroup => ({
  id,
  name,
  sort_order: sortOrder,
  created_at: '2026-10-01T00:00:00Z',
});

const ymd = (date: Date) => [date.getFullYear(), date.getMonth() + 1, date.getDate()];

describe('subscriptionsUtils - nextRenewalDate', () => {
  test('moves to next month when the billing day already passed', () => {
    assert.deepStrictEqual(ymd(nextRenewalDate(1, new Date(2026, 9, 31))), [2026, 11, 1]);
    assert.deepStrictEqual(ymd(nextRenewalDate(5, new Date(2026, 9, 31))), [2026, 11, 5]);
  });

  test('keeps today when the billing day is today', () => {
    assert.deepStrictEqual(ymd(nextRenewalDate(31, new Date(2026, 9, 31))), [2026, 10, 31]);
  });

  test('rolls over into the next year', () => {
    assert.deepStrictEqual(ymd(nextRenewalDate(1, new Date(2026, 11, 31))), [2027, 1, 1]);
  });

  test('clamps day 31 to the last day of short months', () => {
    assert.deepStrictEqual(ymd(nextRenewalDate(31, new Date(2027, 1, 10))), [2027, 2, 28]);
    assert.deepStrictEqual(ymd(nextRenewalDate(31, new Date(2027, 3, 10))), [2027, 4, 30]);
  });

  test('does not mutate the supplied date', () => {
    const now = new Date(2026, 9, 31, 23, 59);
    nextRenewalDate(1, now);
    assert.deepStrictEqual(ymd(now), [2026, 10, 31]);
  });
});

describe('subscriptionsUtils - calendarDayDiff and formatRenewalDate', () => {
  test('counts whole days across month and year boundaries', () => {
    assert.strictEqual(calendarDayDiff(new Date(2026, 9, 31), new Date(2026, 10, 6)), 6);
    assert.strictEqual(calendarDayDiff(new Date(2026, 11, 31), new Date(2027, 0, 1)), 1);
    assert.strictEqual(calendarDayDiff(new Date(2026, 9, 31), new Date(2026, 9, 31, 23, 59)), 0);
  });

  test('formats the renewal date as month and day', () => {
    assert.strictEqual(formatRenewalDate(new Date(2026, 10, 5)), '11 月 5 日');
  });
});

describe('subscriptionsUtils - summarizeSubscriptions', () => {
  test('sums only active subscriptions and derives the annual estimate', () => {
    const subs = [
      sub(1, 'Netflix', 1, 6800, 31),
      sub(2, 'Spotify', 1, 1500, 5),
      sub(3, 'Notion', 2, 7200, 1),
      sub(4, 'Medium', 2, 3500, 31, 'paused'),
    ];
    const summary = summarizeSubscriptions(subs, new Date(2026, 9, 31));
    assert.strictEqual(summary.monthlyCents, 15500);
    assert.strictEqual(summary.annualCents, 186000);
    assert.strictEqual(summary.activeCount, 3);
    assert.strictEqual(summary.upcomingCents, 15500);
    assert.strictEqual(summary.upcomingCount, 3);
  });

  test('includes today through day 6 and excludes day 7 and later', () => {
    const subs = [
      sub(1, 'today', null, 1000, 31),
      sub(2, 'sixth', null, 2000, 6),
      sub(3, 'seventh', null, 4000, 7),
      sub(4, 'month-end', null, 500, 30),
    ];
    const summary = summarizeSubscriptions(subs, new Date(2026, 9, 31));
    assert.strictEqual(summary.upcomingCents, 3000);
    assert.strictEqual(summary.upcomingCount, 2);
    assert.strictEqual(summary.monthlyCents, 7500);
  });

  test('ignores paused subscriptions entirely', () => {
    const summary = summarizeSubscriptions(
      [sub(1, 'active', null, 1000, 31), sub(2, 'paused', null, 5000, 31, 'paused')],
      new Date(2026, 9, 31)
    );
    assert.deepStrictEqual(summary, {
      monthlyCents: 1000,
      annualCents: 12000,
      upcomingCents: 1000,
      upcomingCount: 1,
      activeCount: 1,
    });
  });

  test('returns zeros for an empty list', () => {
    assert.deepStrictEqual(summarizeSubscriptions([], new Date(2026, 9, 31)), {
      monthlyCents: 0,
      annualCents: 0,
      upcomingCents: 0,
      upcomingCount: 0,
      activeCount: 0,
    });
  });
});

describe('subscriptionsUtils - buildSubscriptionSections', () => {
  const groups = [
    group(2, '软件工具', 2),
    group(1, '影音娱乐', 1),
    group(4, '全暂停', 4),
    group(3, '空分组', 3),
  ];
  const subs = [
    sub(1, 'Netflix', 1, 2000, 20),
    sub(2, 'Spotify', 1, 1000, 5),
    sub(3, 'Adobe', 2, 3000, 15, 'paused'),
    sub(4, 'Medium', 4, 4000, 10, 'paused'),
    sub(5, '临时', null, 500, 1),
    sub(6, '旧订阅', null, 600, 2, 'paused'),
  ];
  const now = new Date(2026, 9, 31);

  test('orders groups by sort_order with ungrouped last and items by next renewal', () => {
    const sections = buildSubscriptionSections(groups, subs, 'all', now);
    assert.deepStrictEqual(
      sections.map((section) => section.key),
      ['group-1', 'group-2', 'group-3', 'group-4', 'ungrouped']
    );
    assert.deepStrictEqual(
      sections[0].items.map((item) => item.name),
      ['Spotify', 'Netflix']
    );
    assert.strictEqual(sections[0].monthlyCents, 3000);
    assert.strictEqual(sections[0].activeCount, 2);
    assert.strictEqual(sections[1].monthlyCents, 0);
    assert.strictEqual(sections[2].totalCount, 0);
    assert.strictEqual(sections[4].monthlyCents, 500);
    assert.strictEqual(sections[4].totalCount, 2);
  });

  test('active filter drops empty, paused-only groups and paused items', () => {
    const sections = buildSubscriptionSections(groups, subs, 'active', now);
    assert.deepStrictEqual(
      sections.map((section) => section.key),
      ['group-1', 'ungrouped']
    );
    assert.ok(sections.every((section) => section.items.every((item) => item.status === 'active')));
    assert.deepStrictEqual(
      sections[1].items.map((item) => item.name),
      ['临时']
    );
  });

  test('paused filter keeps only paused rows and their groups', () => {
    const sections = buildSubscriptionSections(groups, subs, 'paused', now);
    assert.deepStrictEqual(
      sections.map((section) => section.key),
      ['group-2', 'group-4', 'ungrouped']
    );
    assert.ok(sections.every((section) => section.items.every((item) => item.status === 'paused')));
    assert.strictEqual(sections[0].activeCount, 0);
    assert.strictEqual(sections[0].monthlyCents, 0);
  });
});
