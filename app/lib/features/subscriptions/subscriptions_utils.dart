import '../../core/api/models.dart';

enum SubscriptionFilter {
  all,
  active,
  paused;

  String get label => switch (this) {
    SubscriptionFilter.all => '全部',
    SubscriptionFilter.active => '使用中',
    SubscriptionFilter.paused => '已暂停',
  };

  bool matches(SubscriptionStatus status) => switch (this) {
    SubscriptionFilter.all => true,
    SubscriptionFilter.active => status == SubscriptionStatus.active,
    SubscriptionFilter.paused => status == SubscriptionStatus.paused,
  };
}

class SubscriptionSection {
  const SubscriptionSection({
    required this.key,
    required this.name,
    required this.group,
    required this.items,
    required this.activeCount,
    required this.totalCount,
    required this.monthlyCents,
  });

  final String key;
  final String name;
  final SubscriptionGroup? group;
  final List<Subscription> items;
  final int activeCount;
  final int totalCount;
  final int monthlyCents;
}

class SubscriptionSummary {
  const SubscriptionSummary({
    required this.monthlyCents,
    required this.annualCents,
    required this.upcomingCents,
    required this.upcomingCount,
    required this.activeCount,
  });

  final int monthlyCents;
  final int annualCents;
  final int upcomingCents;
  final int upcomingCount;
  final int activeCount;
}

List<SubscriptionGroup> sortedSubscriptionGroups(
  Iterable<SubscriptionGroup> groups,
) => [...groups]
  ..sort((a, b) {
    final byOrder = a.sortOrder.compareTo(b.sortOrder);
    return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
  });

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

DateTime _startOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

int _clampDay(int billingDay, int year, int month) =>
    billingDay.clamp(1, daysInMonth(year, month));

/// 下次扣款日（本地零点）；短月夹取到当月最后一天。
DateTime nextRenewalDate(int billingDay, DateTime now) {
  final today = _startOfDay(now);
  final thisMonth = DateTime(
    today.year,
    today.month,
    _clampDay(billingDay, today.year, today.month),
  );
  if (!thisMonth.isBefore(today)) return thisMonth;
  final nextMonth = DateTime(today.year, today.month + 1);
  return DateTime(
    nextMonth.year,
    nextMonth.month,
    _clampDay(billingDay, nextMonth.year, nextMonth.month),
  );
}

/// 以 UTC 整日计算差值，避免夏令时造成 23/25 小时的偏差。
int calendarDayDiff(DateTime from, DateTime to) {
  final start = DateTime.utc(from.year, from.month, from.day);
  final end = DateTime.utc(to.year, to.month, to.day);
  return end.difference(start).inDays;
}

SubscriptionSummary summarizeSubscriptions(
  List<Subscription> subs,
  DateTime now,
) {
  final today = _startOfDay(now);
  var monthlyCents = 0;
  var upcomingCents = 0;
  var upcomingCount = 0;
  var activeCount = 0;

  for (final sub in subs) {
    if (sub.status != SubscriptionStatus.active) continue;
    activeCount += 1;
    monthlyCents += sub.amountCents;
    final diff = calendarDayDiff(today, nextRenewalDate(sub.billingDay, now));
    if (diff >= 0 && diff <= 6) {
      upcomingCents += sub.amountCents;
      upcomingCount += 1;
    }
  }

  return SubscriptionSummary(
    monthlyCents: monthlyCents,
    annualCents: monthlyCents * 12,
    upcomingCents: upcomingCents,
    upcomingCount: upcomingCount,
    activeCount: activeCount,
  );
}

List<SubscriptionSection> buildSubscriptionSections(
  List<SubscriptionGroup> groups,
  List<Subscription> subs,
  SubscriptionFilter filter,
  DateTime now,
) {
  final sections = <SubscriptionSection>[];

  void add(
    String key,
    String name,
    SubscriptionGroup? group,
    List<Subscription> groupSubs,
  ) {
    final items = groupSubs.where((sub) => filter.matches(sub.status)).toList()
      ..sort((a, b) {
        final byDate = nextRenewalDate(
          a.billingDay,
          now,
        ).compareTo(nextRenewalDate(b.billingDay, now));
        return byDate != 0 ? byDate : a.name.compareTo(b.name);
      });
    if (filter != SubscriptionFilter.all && items.isEmpty) return;
    sections.add(
      SubscriptionSection(
        key: key,
        name: name,
        group: group,
        items: items,
        activeCount: groupSubs
            .where((sub) => sub.status == SubscriptionStatus.active)
            .length,
        totalCount: groupSubs.length,
        monthlyCents: groupSubs
            .where((sub) => sub.status == SubscriptionStatus.active)
            .fold(0, (sum, sub) => sum + sub.amountCents),
      ),
    );
  }

  for (final group in sortedSubscriptionGroups(groups)) {
    add(
      'group-${group.id}',
      group.name,
      group,
      subs.where((sub) => sub.groupId == group.id).toList(),
    );
  }

  final ungrouped = subs.where((sub) => sub.groupId == null).toList();
  if (ungrouped.isNotEmpty) add('ungrouped', '未分组', null, ungrouped);

  return sections;
}
