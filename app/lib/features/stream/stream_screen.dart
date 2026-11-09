import 'dart:async';

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
    final excludedCategoryIds = ledger.categories
        .where((category) => category.excludeFromStats)
        .map((category) => category.id)
        .toSet();

    return RefreshIndicator(
      onRefresh: ledger.loadAll,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const LedgerSliverAppBar(title: '流水'),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _HeadlineCard(stats: ledger.stats),
                const SizedBox(height: 16),
                _ListHeader(
                  query: ledger.query,
                  categories: ledger.categories,
                  channels: ledger.channels,
                  onQueryChanged: ledger.setQuery,
                ),
                const SizedBox(height: 12),
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
                    title: ledger.query.isActive ? '没有符合条件的账单' : '本月还没有记账',
                    icon: Icons.receipt_long_outlined,
                    actionLabel: ledger.query.isActive ? null : '记一笔',
                    onAction: ledger.query.isActive
                        ? null
                        : () => RecordSheet.show(
                            context,
                            onOpenSettings: onOpenSettings,
                          ),
                  )
                else
                  for (final group in groups) ...[
                    _DayCard(
                      group: group,
                      now: now,
                      excludedCategoryIds: excludedCategoryIds,
                    ),
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

class _ListHeader extends StatefulWidget {
  const _ListHeader({
    required this.query,
    required this.categories,
    required this.channels,
    required this.onQueryChanged,
  });

  final TransactionQuery query;
  final List<Category> categories;
  final List<PaymentMethod> channels;
  final Future<void> Function(TransactionQuery) onQueryChanged;

  @override
  State<_ListHeader> createState() => _ListHeaderState();
}

class _ListHeaderState extends State<_ListHeader> {
  static const _debounceDuration = Duration(milliseconds: 300);

  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _submitKeyword(String value) {
    _debounce?.cancel();
    unawaited(widget.onQueryChanged(widget.query.withKeyword(value)));
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () => _submitKeyword(value));
  }

  void _clearOrCollapse() {
    _debounce?.cancel();
    if (_controller.text.isNotEmpty) {
      _controller.clear();
      unawaited(widget.onQueryChanged(widget.query.withKeyword('')));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _searching = false);
  }

  Future<void> _openFilter() async {
    final draft = ValueNotifier<TransactionQuery>(widget.query);
    final applied = await showLedgerPicker<TransactionQuery>(
      context: context,
      title: '筛选',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _StreamFilterBody(
            draft: draft,
            categories: widget.categories,
            channels: widget.channels,
          ),
        ),
      ],
      footer: ValueListenableBuilder<TransactionQuery>(
        valueListenable: draft,
        builder: (context, value, _) => Row(
          children: [
            TextButton(
              key: const ValueKey('stream-filter-reset'),
              onPressed: () =>
                  draft.value = TransactionQuery(keyword: widget.query.keyword),
              child: const Text('重置'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                key: const ValueKey('stream-filter-apply'),
                onPressed: () => Navigator.of(context).pop(value),
                child: const Text('应用'),
              ),
            ),
          ],
        ),
      ),
    );
    draft.dispose();
    if (applied != null) {
      await widget.onQueryChanged(applied);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final summary = transactionQuerySummary(
      widget.query,
      categories: widget.categories,
      channels: widget.channels,
    );
    return Row(
      children: [
        Expanded(
          child: _searching
              ? TextField(
                  key: const ValueKey('stream-search-field'),
                  controller: _controller,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: _onChanged,
                  onSubmitted: _submitKeyword,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '搜索账单',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: IconButton(
                      key: const ValueKey('stream-search-clear'),
                      icon: const Icon(Icons.close_rounded, size: 20),
                      tooltip: '清空搜索',
                      onPressed: _clearOrCollapse,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                )
              : Text(
                  summary ?? formatMonth(DateTime.now()),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
        ),
        const SizedBox(width: 12),
        if (!_searching)
          IconButton(
            key: const ValueKey('stream-search-toggle'),
            tooltip: '搜索',
            onPressed: () => setState(() => _searching = true),
            icon: const Icon(Icons.search),
          ),
        _FilterButton(
          active: widget.query.hasDimensions,
          onPressed: _openFilter,
        ),
      ],
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.active, required this.onPressed});

  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const ValueKey('stream-filter-menu'),
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: active
                    ? scheme.secondaryContainer
                    : scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(
                Icons.filter_alt_outlined,
                size: 18,
                color: active ? scheme.onSecondaryContainer : scheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterSectionLabel extends StatelessWidget {
  const _FilterSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

class _StreamFilterBody extends StatelessWidget {
  const _StreamFilterBody({
    required this.draft,
    required this.categories,
    required this.channels,
  });

  final ValueNotifier<TransactionQuery> draft;
  final List<Category> categories;
  final List<PaymentMethod> channels;

  List<Category> _visibleCategories(TransactionType? type) {
    if (type == TransactionType.transfer || type == TransactionType.repayment) {
      return const [];
    }
    if (type == null) {
      return [
        ...categories.where((item) => item.type == CategoryType.expense),
        ...categories.where((item) => item.type == CategoryType.income),
      ];
    }
    final categoryType = type == TransactionType.income
        ? CategoryType.income
        : CategoryType.expense;
    return categories.where((item) => item.type == categoryType).toList();
  }

  TransactionQuery _withType(TransactionQuery current, TransactionType? type) {
    final visible = _visibleCategories(type);
    final keepsCategory =
        current.categoryId != null &&
        visible.any((item) => item.id == current.categoryId);
    return TransactionQuery(
      type: type,
      categoryId: keepsCategory ? current.categoryId : null,
      tagId: keepsCategory ? current.tagId : null,
      paymentMethodId: current.paymentMethodId,
      keyword: current.keyword,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TransactionQuery>(
      valueListenable: draft,
      builder: (context, value, _) {
        final visibleCategories = _visibleCategories(value.type);
        Category? category;
        for (final item in visibleCategories) {
          if (item.id == value.categoryId) {
            category = item;
            break;
          }
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _FilterSectionLabel('类型'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  key: const ValueKey('stream-filter-type-all'),
                  label: const Text('全部'),
                  showCheckmark: false,
                  selected: value.type == null,
                  onSelected: (_) => draft.value = _withType(value, null),
                ),
                for (final type in TransactionType.values)
                  ChoiceChip(
                    key: ValueKey('stream-filter-type-${type.name}'),
                    label: Text(type.label),
                    showCheckmark: false,
                    selected: value.type == type,
                    onSelected: (_) => draft.value = _withType(value, type),
                  ),
              ],
            ),
            if (visibleCategories.isNotEmpty) ...[
              const SizedBox(height: 20),
              const _FilterSectionLabel('分类'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    key: const ValueKey('stream-filter-category-all'),
                    label: const Text('全部分类'),
                    showCheckmark: false,
                    selected: value.categoryId == null,
                    onSelected: (_) => draft.value = TransactionQuery(
                      type: value.type,
                      paymentMethodId: value.paymentMethodId,
                      keyword: value.keyword,
                    ),
                  ),
                  for (final item in visibleCategories)
                    ChoiceChip(
                      key: ValueKey('stream-filter-category-${item.id}'),
                      label: Text(item.name),
                      showCheckmark: false,
                      selected: value.categoryId == item.id,
                      onSelected: (_) => draft.value = TransactionQuery(
                        type: value.type,
                        categoryId: item.id,
                        paymentMethodId: value.paymentMethodId,
                        keyword: value.keyword,
                      ),
                    ),
                ],
              ),
            ],
            if (category != null && category.tags.isNotEmpty) ...[
              const SizedBox(height: 20),
              const _FilterSectionLabel('标签'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    key: const ValueKey('stream-filter-tag-all'),
                    label: const Text('全部标签'),
                    showCheckmark: false,
                    selected: value.tagId == null,
                    onSelected: (_) => draft.value = TransactionQuery(
                      type: value.type,
                      categoryId: value.categoryId,
                      paymentMethodId: value.paymentMethodId,
                      keyword: value.keyword,
                    ),
                  ),
                  for (final tag in category.tags)
                    ChoiceChip(
                      key: ValueKey('stream-filter-tag-${tag.id}'),
                      label: Text(tag.name),
                      showCheckmark: false,
                      selected: value.tagId == tag.id,
                      onSelected: (_) => draft.value = TransactionQuery(
                        type: value.type,
                        categoryId: value.categoryId,
                        tagId: tag.id,
                        paymentMethodId: value.paymentMethodId,
                        keyword: value.keyword,
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            const _FilterSectionLabel('支付渠道'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  key: const ValueKey('stream-filter-channel-all'),
                  label: const Text('全部渠道'),
                  showCheckmark: false,
                  selected: value.paymentMethodId == null,
                  onSelected: (_) => draft.value = TransactionQuery(
                    type: value.type,
                    categoryId: value.categoryId,
                    tagId: value.tagId,
                    keyword: value.keyword,
                  ),
                ),
                for (final channel in channels)
                  ChoiceChip(
                    key: ValueKey('stream-filter-channel-${channel.id}'),
                    label: Text(channel.name),
                    showCheckmark: false,
                    selected: value.paymentMethodId == channel.id,
                    onSelected: (_) => draft.value = TransactionQuery(
                      type: value.type,
                      categoryId: value.categoryId,
                      tagId: value.tagId,
                      paymentMethodId: channel.id,
                      keyword: value.keyword,
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.group,
    required this.now,
    required this.excludedCategoryIds,
  });

  final TransactionDayGroup group;
  final DateTime now;
  final Set<int> excludedCategoryIds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtotal = daySubtotalParts(
      group,
      excludedCategoryIds: excludedCategoryIds,
    );
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
    final note = transactionNote(transaction);
    return InkWell(
      key: ValueKey('stream-row-${transaction.id}'),
      onTap: () => RecordSheet.show(context, initial: transaction),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
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
                      key: ValueKey('stream-row-meta-${transaction.id}'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * 0.42,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: AmountText(
                        transaction.amount,
                        key: ValueKey('stream-row-amount-${transaction.id}'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        color: amountColor,
                      ),
                    ),
                    if (note.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        note,
                        key: ValueKey('stream-row-note-${transaction.id}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<_RowAction>(
                tooltip: '更多操作',
                clipBehavior: Clip.antiAlias,
                onSelected: (action) => _handleAction(context, action),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: _RowAction.edit, child: Text('编辑')),
                  PopupMenuItem(value: _RowAction.delete, child: Text('删除')),
                ],
              ),
            ],
          ),
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
