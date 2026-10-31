import type { Subscription, SubscriptionGroup } from '../lib/api';

export type SubscriptionFilter = 'all' | 'active' | 'paused';

export interface SubscriptionSection {
  key: string;
  name: string;
  group: SubscriptionGroup | null;
  items: Subscription[];
  activeCount: number;
  totalCount: number;
  monthlyCents: number;
}

export interface SubscriptionSummary {
  monthlyCents: number;
  annualCents: number;
  upcomingCents: number;
  upcomingCount: number;
  activeCount: number;
}

export function startOfLocalDay(now: Date): Date {
  return new Date(now.getFullYear(), now.getMonth(), now.getDate());
}

export function daysInMonth(year: number, monthIndex: number): number {
  return new Date(year, monthIndex + 1, 0).getDate();
}

/** Next billing date at local midnight; short months clamp to their last day. */
export function nextRenewalDate(billingDay: number, now: Date): Date {
  const today = startOfLocalDay(now);
  const year = today.getFullYear();
  const month = today.getMonth();
  const thisMonth = new Date(year, month, Math.min(billingDay, daysInMonth(year, month)));
  if (thisMonth >= today) {
    return thisMonth;
  }
  return new Date(year, month + 1, Math.min(billingDay, daysInMonth(year, month + 1)));
}

/** Whole-day difference in UTC to stay stable across DST shifts. */
export function calendarDayDiff(from: Date, to: Date): number {
  const start = Date.UTC(from.getFullYear(), from.getMonth(), from.getDate());
  const end = Date.UTC(to.getFullYear(), to.getMonth(), to.getDate());
  return Math.round((end - start) / 86_400_000);
}

export function formatRenewalDate(date: Date): string {
  return `${date.getMonth() + 1} 月 ${date.getDate()} 日`;
}

export function summarizeSubscriptions(subs: Subscription[], now: Date): SubscriptionSummary {
  const today = startOfLocalDay(now);
  let monthlyCents = 0;
  let upcomingCents = 0;
  let upcomingCount = 0;
  let activeCount = 0;

  for (const sub of subs) {
    if (sub.status !== 'active') continue;
    activeCount += 1;
    monthlyCents += sub.amount_cents;
    const diff = calendarDayDiff(today, nextRenewalDate(sub.billing_day, now));
    if (diff >= 0 && diff <= 6) {
      upcomingCents += sub.amount_cents;
      upcomingCount += 1;
    }
  }

  return { monthlyCents, annualCents: monthlyCents * 12, upcomingCents, upcomingCount, activeCount };
}

const byRenewalThenName = (now: Date) => (a: Subscription, b: Subscription) => {
  const diff = nextRenewalDate(a.billing_day, now).getTime() - nextRenewalDate(b.billing_day, now).getTime();
  return diff !== 0 ? diff : a.name.localeCompare(b.name, 'zh-CN');
};

export function buildSubscriptionSections(
  groups: SubscriptionGroup[],
  subs: Subscription[],
  filter: SubscriptionFilter,
  now: Date
): SubscriptionSection[] {
  const orderedGroups = [...groups].sort((a, b) => a.sort_order - b.sort_order || a.id - b.id);
  const sections: SubscriptionSection[] = [];

  const toSection = (key: string, name: string, group: SubscriptionGroup | null, groupSubs: Subscription[]) => {
    const items = groupSubs
      .filter((sub) => filter === 'all' || sub.status === filter)
      .sort(byRenewalThenName(now));
    if (filter !== 'all' && items.length === 0) return;
    sections.push({
      key,
      name,
      group,
      items,
      activeCount: groupSubs.filter((sub) => sub.status === 'active').length,
      totalCount: groupSubs.length,
      monthlyCents: groupSubs.reduce((sum, sub) => (sub.status === 'active' ? sum + sub.amount_cents : sum), 0),
    });
  };

  for (const group of orderedGroups) {
    toSection(`group-${group.id}`, group.name, group, subs.filter((sub) => sub.group_id === group.id));
  }

  const ungrouped = subs.filter((sub) => sub.group_id === null);
  if (ungrouped.length > 0) {
    toSection('ungrouped', '未分组', null, ungrouped);
  }

  return sections;
}
