import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/core/api/models.dart';
import 'package:ledger_app/features/subscriptions/subscriptions_utils.dart';

Subscription subscription({
  int id = 1,
  int? groupId,
  String name = '订阅',
  int amountCents = 1000,
  int billingDay = 1,
  SubscriptionStatus status = SubscriptionStatus.active,
}) => Subscription(
  id: id,
  groupId: groupId,
  name: name,
  amountCents: amountCents,
  billingDay: billingDay,
  status: status,
);

SubscriptionGroup subscriptionGroup({
  int id = 1,
  String name = '分组',
  int sortOrder = 1,
}) => SubscriptionGroup(id: id, name: name, sortOrder: sortOrder);

void main() {
  group('nextRenewalDate', () {
    final today = DateTime(2026, 10, 31);

    test('keeps a billing day later this month', () {
      expect(nextRenewalDate(31, today), DateTime(2026, 10, 31));
    });

    test('rolls a passed billing day into next month', () {
      expect(nextRenewalDate(1, today), DateTime(2026, 11, 1));
      expect(nextRenewalDate(5, today), DateTime(2026, 11, 5));
    });

    test('rolls December into the next year', () {
      expect(nextRenewalDate(1, DateTime(2026, 12, 31)), DateTime(2027, 1, 1));
    });

    test('clamps day 31 to the last day of a short month', () {
      expect(nextRenewalDate(31, DateTime(2027, 2, 10)), DateTime(2027, 2, 28));
      expect(nextRenewalDate(31, DateTime(2027, 4, 10)), DateTime(2027, 4, 30));
    });
  });

  test('calendarDayDiff counts whole days', () {
    final today = DateTime(2026, 10, 31, 23, 30);
    expect(calendarDayDiff(today, DateTime(2026, 10, 31, 0, 5)), 0);
    expect(calendarDayDiff(today, DateTime(2026, 11, 6)), 6);
    expect(calendarDayDiff(today, DateTime(2026, 11, 7)), 7);
  });

  test('summary excludes paused and counts the 0-6 day window', () {
    final summary = summarizeSubscriptions([
      subscription(id: 1, amountCents: 1500, billingDay: 31),
      subscription(id: 2, amountCents: 2500, billingDay: 5),
      subscription(id: 3, amountCents: 4000, billingDay: 8),
      subscription(
        id: 4,
        amountCents: 9900,
        billingDay: 31,
        status: SubscriptionStatus.paused,
      ),
    ], DateTime(2026, 10, 31));

    expect(summary.monthlyCents, 8000);
    expect(summary.annualCents, 96000);
    expect(summary.upcomingCents, 4000);
    expect(summary.upcomingCount, 2);
    expect(summary.activeCount, 3);
  });

  test('summary includes exactly the sixth day and excludes the seventh', () {
    final summary = summarizeSubscriptions([
      subscription(id: 1, amountCents: 600, billingDay: 6),
      subscription(id: 2, amountCents: 700, billingDay: 7),
    ], DateTime(2026, 10, 31));

    expect(summary.upcomingCents, 600);
    expect(summary.upcomingCount, 1);
    expect(summary.monthlyCents, 1300);
  });

  group('buildSubscriptionSections', () {
    final now = DateTime(2026, 10, 31);
    final groups = [
      subscriptionGroup(id: 2, name: '娱乐', sortOrder: 2),
      subscriptionGroup(id: 1, name: '影音', sortOrder: 1),
      subscriptionGroup(id: 3, name: '空组', sortOrder: 3),
    ];
    final subs = [
      subscription(
        id: 1,
        groupId: 1,
        name: 'B',
        billingDay: 10,
        amountCents: 1000,
      ),
      subscription(
        id: 2,
        groupId: 1,
        name: 'A',
        billingDay: 5,
        amountCents: 2000,
      ),
      subscription(
        id: 3,
        groupId: 1,
        name: 'C',
        billingDay: 15,
        amountCents: 3000,
        status: SubscriptionStatus.paused,
      ),
      subscription(
        id: 4,
        groupId: 2,
        name: 'D',
        billingDay: 1,
        amountCents: 4000,
      ),
      subscription(
        id: 5,
        groupId: 2,
        name: 'E',
        billingDay: 20,
        amountCents: 5000,
        status: SubscriptionStatus.paused,
      ),
      subscription(id: 6, name: '未分组项', billingDay: 30, amountCents: 6000),
    ];

    test('orders groups, keeps empty groups and puts ungrouped last', () {
      final sections = buildSubscriptionSections(
        groups,
        subs,
        SubscriptionFilter.all,
        now,
      );

      expect(sections.map((section) => section.key), [
        'group-1',
        'group-2',
        'group-3',
        'ungrouped',
      ]);
      expect(sections[0].items.map((item) => item.name), ['A', 'B', 'C']);
      expect(sections[0].activeCount, 2);
      expect(sections[0].totalCount, 3);
      expect(sections[0].monthlyCents, 3000);
      expect(sections[2].items, isEmpty);
    });

    test('active filter hides empty groups and paused rows', () {
      final sections = buildSubscriptionSections(
        groups,
        subs,
        SubscriptionFilter.active,
        now,
      );

      expect(sections.map((section) => section.key), [
        'group-1',
        'group-2',
        'ungrouped',
      ]);
      expect(
        sections.expand((section) => section.items).map((item) => item.id),
        [2, 1, 4, 6],
      );
    });

    test('paused filter keeps only paused rows', () {
      final sections = buildSubscriptionSections(
        groups,
        subs,
        SubscriptionFilter.paused,
        now,
      );

      expect(sections.map((section) => section.key), ['group-1', 'group-2']);
      expect(
        sections.expand((section) => section.items).map((item) => item.id),
        [3, 5],
      );
      expect(sections[0].monthlyCents, 3000);
    });

    test('paused view keeps the group active subtotal', () {
      final sections = buildSubscriptionSections(
        groups,
        subs,
        SubscriptionFilter.paused,
        now,
      );

      expect(sections.first.activeCount, 2);
      expect(sections.first.monthlyCents, 3000);
    });

    test('ungrouped section is hidden while filtering when it has no rows', () {
      final sections = buildSubscriptionSections(
        groups,
        [subscription(id: 1, groupId: 1, name: 'A')],
        SubscriptionFilter.paused,
        now,
      );

      expect(sections, isEmpty);
    });
  });
}
