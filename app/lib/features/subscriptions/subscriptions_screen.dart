import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/format/dates.dart';
import '../../core/format/money.dart';
import '../../core/state/ledger_controller.dart';
import '../../core/theme/finance_colors.dart';
import '../../core/widgets/ledger_widgets.dart';
import 'group_sheet.dart';
import 'subscription_sheet.dart';
import 'subscriptions_utils.dart';

class SubscriptionsScreen extends StatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  SubscriptionFilter _filter = SubscriptionFilter.all;

  @override
  Widget build(BuildContext context) {
    final ledger = context.watch<LedgerController>();
    final now = DateTime.now();
    final orderedGroups = sortedSubscriptionGroups(ledger.subscriptionGroups);
    final sections = buildSubscriptionSections(
      ledger.subscriptionGroups,
      ledger.subscriptions,
      _filter,
      now,
    );
    final allSections = buildSubscriptionSections(
      ledger.subscriptionGroups,
      ledger.subscriptions,
      SubscriptionFilter.all,
      now,
    );
    final summary = summarizeSubscriptions(ledger.subscriptions, now);
    final pausedCount = ledger.subscriptions
        .where((item) => item.status == SubscriptionStatus.paused)
        .length;
    final isEmpty =
        ledger.subscriptionGroups.isEmpty && ledger.subscriptions.isEmpty;
    final firstLoading =
        ledger.subscriptionsLoading &&
        ledger.subscriptions.isEmpty &&
        ledger.subscriptionGroups.isEmpty;
    final firstFailed =
        !ledger.subscriptionsLoading &&
        ledger.subscriptionsError != null &&
        ledger.subscriptions.isEmpty &&
        ledger.subscriptionGroups.isEmpty;

    return RefreshIndicator(
      onRefresh: ledger.loadSubscriptions,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const LedgerSliverAppBar(title: '订阅'),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (!firstLoading && !firstFailed) ...[
                  _ActionRow(
                    onAddGroup: _addGroup,
                    onAddSubscription: () => _addSubscription(null),
                  ),
                  const SizedBox(height: 12),
                ],
                if (firstLoading)
                  const SkeletonList(rows: 5)
                else if (firstFailed)
                  ErrorState(
                    message: ledger.subscriptionsError ?? '加载订阅失败',
                    onRetry: ledger.loadSubscriptions,
                  )
                else if (isEmpty)
                  EmptyState(
                    title: '还没有订阅',
                    icon: Icons.autorenew_rounded,
                    actionLabel: '添加第一个订阅',
                    onAction: () => _addSubscription(null),
                  )
                else ...[
                  _SummaryHero(
                    summary: summary,
                    sections: allSections,
                    groups: orderedGroups,
                  ),
                  const SizedBox(height: 18),
                  _FilterBar(
                    filter: _filter,
                    totalCount: ledger.subscriptions.length,
                    pausedCount: pausedCount,
                    onSelected: (filter) => setState(() => _filter = filter),
                  ),
                  const SizedBox(height: 12),
                  if (sections.isEmpty)
                    EmptyState(
                      title: _filter == SubscriptionFilter.paused
                          ? '暂无已暂停的订阅'
                          : '暂无使用中的订阅',
                      icon: Icons.filter_alt_off_outlined,
                      actionLabel: '查看全部',
                      onAction: () =>
                          setState(() => _filter = SubscriptionFilter.all),
                    )
                  else
                    for (var i = 0; i < sections.length; i++) ...[
                      _SectionCard(
                        section: sections[i],
                        orderedGroups: orderedGroups,
                        filter: _filter,
                        now: now,
                        onAddInGroup: _addSubscription,
                        onRenameGroup: _renameGroup,
                        onMoveGroup: _moveGroup,
                        onDeleteGroup: _deleteGroup,
                        onEditSubscription: _editSubscription,
                        onToggleStatus: _toggleStatus,
                        onDeleteSubscription: _deleteSubscription,
                      ),
                      if (i != sections.length - 1) const SizedBox(height: 12),
                    ],
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addGroup() => GroupSheet.show(context);

  Future<void> _addSubscription(int? groupId) =>
      SubscriptionSheet.show(context, defaultGroupId: groupId);

  Future<void> _editSubscription(Subscription subscription) =>
      SubscriptionSheet.show(context, initial: subscription);

  Future<void> _renameGroup(SubscriptionGroup group) =>
      GroupSheet.show(context, initial: group);

  Future<void> _moveGroup(SubscriptionGroup group, int direction) async {
    final ledger = context.read<LedgerController>();
    try {
      await ledger.moveSubscriptionGroup(group, direction);
      if (!mounted) return;
      showLedgerSnackBar(context, '分组顺序已更新');
    } on ApiException catch (error) {
      if (!mounted) return;
      showLedgerSnackBar(context, error.message, isError: true);
    }
  }

  Future<void> _deleteGroup(SubscriptionGroup group) async {
    final count = context
        .read<LedgerController>()
        .subscriptions
        .where((item) => item.groupId == group.id)
        .length;
    final confirmed = await ConfirmDialog.show(
      context,
      title: '删除分组',
      message: '「${group.name}」内的 $count 项订阅将移至未分组。',
    );
    if (!confirmed || !mounted) return;
    final ledger = context.read<LedgerController>();
    try {
      await ledger.deleteSubscriptionGroup(group);
      if (!mounted) return;
      showLedgerSnackBar(context, '分组已删除，订阅已移至未分组');
    } on ApiException catch (error) {
      if (!mounted) return;
      showLedgerSnackBar(context, error.message, isError: true);
    }
  }

  Future<void> _toggleStatus(Subscription subscription) async {
    final next = subscription.status == SubscriptionStatus.active
        ? SubscriptionStatus.paused
        : SubscriptionStatus.active;
    final ledger = context.read<LedgerController>();
    try {
      await ledger.setSubscriptionStatus(subscription, next);
      if (!mounted) return;
      showLedgerSnackBar(
        context,
        next == SubscriptionStatus.paused ? '已暂停续费' : '已恢复续费',
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      showLedgerSnackBar(context, error.message, isError: true);
    }
  }

  Future<void> _deleteSubscription(Subscription subscription) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: '删除订阅',
      message: '删除后不可恢复。\n${subscription.name}',
    );
    if (!confirmed || !mounted) return;
    final ledger = context.read<LedgerController>();
    try {
      await ledger.deleteSubscription(subscription);
      if (!mounted) return;
      showLedgerSnackBar(context, '订阅已删除');
    } on ApiException catch (error) {
      if (!mounted) return;
      showLedgerSnackBar(context, error.message, isError: true);
    }
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.onAddGroup, required this.onAddSubscription});

  final VoidCallback onAddGroup;
  final VoidCallback onAddSubscription;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('subscriptions-add-group'),
            onPressed: onAddGroup,
            icon: const Icon(Icons.create_new_folder_outlined, size: 18),
            label: const Text('新建分组'),
          ),
          FilledButton.icon(
            key: const ValueKey('subscriptions-add'),
            onPressed: onAddSubscription,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('添加订阅'),
          ),
        ],
      ),
    );
  }
}

class _SummaryHero extends StatelessWidget {
  const _SummaryHero({
    required this.summary,
    required this.sections,
    required this.groups,
  });

  final SubscriptionSummary summary;
  final List<SubscriptionSection> sections;
  final List<SubscriptionGroup> groups;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final finance = financeColors(context);
    final segments = sections
        .where((section) => section.monthlyCents > 0)
        .toList();

    return LedgerCard(
      radius: 28,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '每月固定开支',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${summary.activeCount} 项使用中',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '¥',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  formatMoney(summary.monthlyCents / 100, withCurrency: false),
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '/ 月',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _HeroStat(
                  label: '年度预估',
                  value: formatMoney(
                    summary.annualCents / 100,
                    withCurrency: false,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _HeroStat(
                  label: '未来 7 天',
                  value: formatMoney(
                    summary.upcomingCents / 100,
                    withCurrency: false,
                  ),
                  suffix: '${summary.upcomingCount} 项',
                ),
              ),
            ],
          ),
          if (segments.isNotEmpty) ...[
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 7,
                child: Row(
                  children: [
                    for (final section in segments)
                      Expanded(
                        flex: section.monthlyCents,
                        child: ColoredBox(
                          color: _sectionColor(section, groups, finance),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value, this.suffix});

  final String label;
  final String value;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (suffix != null) ...[
                const SizedBox(width: 4),
                Text(
                  suffix!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filter,
    required this.totalCount,
    required this.pausedCount,
    required this.onSelected,
  });

  final SubscriptionFilter filter;
  final int totalCount;
  final int pausedCount;
  final ValueChanged<SubscriptionFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in SubscriptionFilter.values)
              ChoiceChip(
                key: ValueKey('subscriptions-filter-${item.name}'),
                label: Text(item.label),
                selected: filter == item,
                onSelected: (_) => onSelected(item),
              ),
          ],
        ),
        const SizedBox(height: 2),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            filter == SubscriptionFilter.paused
                ? '$pausedCount 项已暂停'
                : '共 $totalCount 项',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

Color _sectionColor(
  SubscriptionSection section,
  List<SubscriptionGroup> groups,
  FinanceColors finance,
) {
  final index = section.group == null
      ? groups.length
      : groups.indexWhere((group) => group.id == section.group!.id);
  return finance.chart[(index < 0 ? groups.length : index) %
      finance.chart.length];
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.orderedGroups,
    required this.filter,
    required this.now,
    required this.onAddInGroup,
    required this.onRenameGroup,
    required this.onMoveGroup,
    required this.onDeleteGroup,
    required this.onEditSubscription,
    required this.onToggleStatus,
    required this.onDeleteSubscription,
  });

  final SubscriptionSection section;
  final List<SubscriptionGroup> orderedGroups;
  final SubscriptionFilter filter;
  final DateTime now;
  final ValueChanged<int?> onAddInGroup;
  final ValueChanged<SubscriptionGroup> onRenameGroup;
  final void Function(SubscriptionGroup, int) onMoveGroup;
  final ValueChanged<SubscriptionGroup> onDeleteGroup;
  final ValueChanged<Subscription> onEditSubscription;
  final ValueChanged<Subscription> onToggleStatus;
  final ValueChanged<Subscription> onDeleteSubscription;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final finance = financeColors(context);
    final group = section.group;
    final isPausedView = filter == SubscriptionFilter.paused;
    final groupIndex = group == null
        ? -1
        : orderedGroups.indexWhere((item) => item.id == group.id);
    final showDash = isPausedView && section.activeCount == 0;
    final countLabel = isPausedView
        ? '${section.totalCount - section.activeCount} 项已暂停'
        : '${section.activeCount} 项使用中';

    return LedgerCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (group != null) ...[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          color: _sectionColor(section, orderedGroups, finance),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        section.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          showDash
                              ? '—'
                              : '${formatMoney(section.monthlyCents / 100, withCurrency: false)} / 月',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                    if (group != null)
                      PopupMenuButton<_GroupAction>(
                        key: ValueKey('subscription-group-menu-${group.id}'),
                        tooltip: '分组操作',
                        iconSize: 20,
                        onSelected: (action) {
                          switch (action) {
                            case _GroupAction.add:
                              onAddInGroup(group.id);
                            case _GroupAction.rename:
                              onRenameGroup(group);
                            case _GroupAction.moveUp:
                              onMoveGroup(group, -1);
                            case _GroupAction.moveDown:
                              onMoveGroup(group, 1);
                            case _GroupAction.delete:
                              onDeleteGroup(group);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: _GroupAction.add,
                            child: Text('在此分组添加订阅'),
                          ),
                          const PopupMenuItem(
                            value: _GroupAction.rename,
                            child: Text('重命名分组'),
                          ),
                          PopupMenuItem(
                            value: _GroupAction.moveUp,
                            enabled: groupIndex > 0,
                            child: const Text('上移'),
                          ),
                          PopupMenuItem(
                            value: _GroupAction.moveDown,
                            enabled: groupIndex < orderedGroups.length - 1,
                            child: const Text('下移'),
                          ),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: _GroupAction.delete,
                            child: Text(
                              '删除分组',
                              style: TextStyle(color: scheme.error),
                            ),
                          ),
                        ],
                      )
                    else
                      const SizedBox(width: 8),
                  ],
                ),
                Padding(
                  padding: EdgeInsets.only(left: group == null ? 0 : 16),
                  child: Text(
                    countLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (section.items.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '暂无订阅',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    key: ValueKey(
                      'subscriptions-empty-add-${group?.id ?? 'ungrouped'}',
                    ),
                    onPressed: () => onAddInGroup(group?.id),
                    child: const Text('添加'),
                  ),
                ],
              ),
            )
          else
            for (var i = 0; i < section.items.length; i++) ...[
              if (i == 0) const Divider(height: 1),
              _SubscriptionRow(
                subscription: section.items[i],
                now: now,
                onEdit: () => onEditSubscription(section.items[i]),
                onToggleStatus: () => onToggleStatus(section.items[i]),
                onDelete: () => onDeleteSubscription(section.items[i]),
              ),
              if (i != section.items.length - 1) const Divider(height: 1),
            ],
        ],
      ),
    );
  }
}

class _SubscriptionRow extends StatelessWidget {
  const _SubscriptionRow({
    required this.subscription,
    required this.now,
    required this.onEdit,
    required this.onToggleStatus,
    required this.onDelete,
  });

  final Subscription subscription;
  final DateTime now;
  final VoidCallback onEdit;
  final VoidCallback onToggleStatus;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final paused = subscription.status == SubscriptionStatus.paused;
    final initial = subscription.name.trim().isEmpty
        ? '?'
        : subscription.name.trim().characters.first.toUpperCase();

    return Container(
      constraints: const BoxConstraints(minHeight: 62),
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: paused
                  ? scheme.surfaceContainerHigh
                  : scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              initial,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: paused
                    ? scheme.onSurfaceVariant
                    : scheme.onSecondaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 7,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(subscription.name, style: theme.textTheme.bodyLarge),
                    if (paused)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '已暂停',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  paused
                      ? '原扣款日 ${subscription.billingDay} 日'
                      : '每月 ${subscription.billingDay} 日 · 下次 ${formatMonthDay(nextRenewalDate(subscription.billingDay, now))}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      formatMoney(subscription.amount, withCurrency: false),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: paused ? FontWeight.w500 : FontWeight.w600,
                        color: paused ? scheme.onSurfaceVariant : null,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '/ 月',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          PopupMenuButton<_RowAction>(
            key: ValueKey('subscription-menu-${subscription.id}'),
            tooltip: '订阅操作',
            iconSize: 20,
            onSelected: (action) {
              switch (action) {
                case _RowAction.edit:
                  onEdit();
                case _RowAction.toggle:
                  onToggleStatus();
                case _RowAction.delete:
                  onDelete();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: _RowAction.edit, child: Text('编辑')),
              PopupMenuItem(
                value: _RowAction.toggle,
                child: Text(paused ? '恢复续费' : '暂停续费'),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: _RowAction.delete,
                child: Text('删除', style: TextStyle(color: scheme.error)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _RowAction { edit, toggle, delete }

enum _GroupAction { add, rename, moveUp, moveDown, delete }
