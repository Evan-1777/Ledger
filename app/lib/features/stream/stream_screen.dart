import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/format/dates.dart';
import '../../core/format/money.dart';
import '../../core/state/ledger_controller.dart';
import '../../core/theme/finance_colors.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../record/record_sheet.dart';
import 'stream_utils.dart';

class StreamScreen extends StatelessWidget {
  const StreamScreen({super.key, this.onOpenSettings});

  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final ledger = context.watch<LedgerController>();
    final now = DateTime.now();
    final groups = groupTransactions(ledger.transactions);

    return RefreshIndicator(
      onRefresh: ledger.loadAll,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverAppBar.large(title: Text('流水')),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Text(
                  formatMonth(now),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                _HeadlineCard(stats: ledger.stats),
                const SizedBox(height: 16),
                _FilterBar(
                  selected: ledger.filter,
                  onSelected: (filter) => ledger.setFilter(filter),
                ),
                const SizedBox(height: 16),
                if (ledger.transactionsLoading && ledger.transactions.isEmpty)
                  const SkeletonList(rows: 5)
                else if (ledger.transactionsError != null &&
                    ledger.transactions.isEmpty)
                  ErrorState(
                    message: ledger.transactionsError!,
                    onRetry: ledger.loadTransactions,
                  )
                else if (groups.isEmpty)
                  EmptyState(
                    title: ledger.filter == TransactionFilter.all
                        ? '本月还没有记账'
                        : '当前筛选下暂无记录',
                    icon: Icons.receipt_long_outlined,
                    actionLabel: ledger.filter == TransactionFilter.all
                        ? '记一笔'
                        : null,
                    onAction: ledger.filter == TransactionFilter.all
                        ? () => RecordSheet.show(
                            context,
                            onOpenSettings: onOpenSettings,
                          )
                        : null,
                  )
                else
                  for (final group in groups) ...[
                    _DayCard(group: group, now: now),
                    const SizedBox(height: 12),
                  ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeadlineCard extends StatelessWidget {
  const _HeadlineCard({required this.stats});

  final StatsSummary? stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final finance = financeColors(context);
    final summary = stats;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -40,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.onPrimaryContainer.withValues(alpha: 0.06),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '本月结余',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  summary == null ? '—' : formatMoney(summary.monthBalance),
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _HeadlineMetric(
                        label: '收入',
                        value: summary == null
                            ? '—'
                            : formatMoney(summary.monthIncome),
                        color: finance.income,
                      ),
                    ),
                    Expanded(
                      child: _HeadlineMetric(
                        label: '支出',
                        value: summary == null
                            ? '—'
                            : formatMoney(summary.monthExpense),
                        color: finance.expense,
                      ),
                    ),
                  ],
                ),
                if (summary != null &&
                    summary.monthIncome + summary.monthExpense > 0) ...[
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value:
                          summary.monthIncome /
                          (summary.monthIncome + summary.monthExpense),
                      minHeight: 6,
                      color: finance.income,
                      backgroundColor: finance.expense,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeadlineMetric extends StatelessWidget {
  const _HeadlineMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelMedium),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onSelected});

  final TransactionFilter selected;
  final ValueChanged<TransactionFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in TransactionFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _FilterPill(
                key: ValueKey('filter-${filter.name}'),
                label: filter.label,
                selected: selected == filter,
                onTap: () => onSelected(filter),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected
        ? scheme.onSecondaryContainer
        : scheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHigh,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 64, minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (selected) ...[
                    Icon(Icons.check_rounded, size: 18, color: foreground),
                    const SizedBox(width: 2),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: foreground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.group, required this.now});

  final TransactionDayGroup group;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtotal = daySubtotalParts(group);
    return LedgerCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    dayHeader(group, now),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (subtotal.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 2,
                      children: [
                        for (final part in subtotal)
                          Text(
                            part,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          for (var i = 0; i < group.items.length; i++) ...[
            _TransactionRow(transaction: group.items[i]),
            if (i != group.items.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amountColor = transactionColor(context, transaction);
    return InkWell(
      onTap: () => RecordSheet.show(context, initial: transaction),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        child: Row(
          children: [
            TypeIcon(type: transaction.type),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaction.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    transactionMeta(transaction),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AmountText(
              transaction.amount,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              color: amountColor,
            ),
            PopupMenuButton<_RowAction>(
              tooltip: '更多操作',
              onSelected: (action) => _handleAction(context, action),
              itemBuilder: (context) => const [
                PopupMenuItem(value: _RowAction.edit, child: Text('编辑')),
                PopupMenuItem(value: _RowAction.delete, child: Text('删除')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAction(BuildContext context, _RowAction action) async {
    if (action == _RowAction.edit) {
      await RecordSheet.show(context, initial: transaction);
      return;
    }
    final confirmed = await ConfirmDialog.show(
      context,
      title: '删除账单',
      message:
          '删除后该笔记录不可恢复。\n${transaction.description}  ${formatMoney(transaction.amount)}',
    );
    if (!confirmed || !context.mounted) return;
    try {
      await context.read<LedgerController>().deleteTransaction(transaction.id);
      if (!context.mounted) return;
      showLedgerSnackBar(context, '账单已删除');
    } on ApiException catch (error) {
      if (!context.mounted) return;
      showLedgerSnackBar(context, error.message, isError: true);
    }
  }
}

enum _RowAction { edit, delete }
