import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/models.dart';
import '../../core/format/money.dart';
import '../../core/state/ledger_controller.dart';
import '../../core/theme/finance_colors.dart';
import '../../core/widgets/ledger_widgets.dart';
import 'charts.dart';
import 'stats_utils.dart';

enum _ChartMode { composition, trend }

enum _StatsView { expense, income }

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  _ChartMode _mode = _ChartMode.composition;
  _StatsView _view = _StatsView.expense;

  Future<void> _openFilter(LedgerController ledger) async {
    final applied = await showModalBottomSheet<StatsQuery>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _StatsFilterSheet(
        initial: ledger.statsQuery,
        categories: ledger.categories,
      ),
    );
    if (applied == null || !mounted) return;
    final matches = ledger.categories.where(
      (item) => item.id == applied.categoryId,
    );
    final category = matches.isEmpty ? null : matches.first;
    final nextView = switch (category?.type) {
      CategoryType.income => _StatsView.income,
      CategoryType.expense => _StatsView.expense,
      _ => _view,
    };
    if (nextView != _view) setState(() => _view = nextView);
    await ledger.setStatsQuery(applied);
  }

  @override
  Widget build(BuildContext context) {
    final ledger = context.watch<LedgerController>();
    final stats = ledger.rangeStats;
    final now = DateTime.now();
    final range = DateTimeRange(
      start: ledger.statsQuery.start,
      end: ledger.statsQuery.end,
    );
    final preset = rangePresetFor(range, now);
    final summary =
        '${rangeLabel(preset, range)} · ${dimensionSummary(ledger.statsQuery, ledger.categories)}';

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([ledger.loadStats(), ledger.loadRangeStats()]);
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const LedgerSliverAppBar(title: '统计'),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _StatsSummaryBar(
                  summary: summary,
                  onTap: () => _openFilter(ledger),
                ),
                const SizedBox(height: 12),
                if (stats == null && ledger.rangeStatsLoading)
                  const SkeletonList(rows: 5)
                else if (stats == null)
                  SizedBox(
                    height: 320,
                    child: ErrorState(
                      message: ledger.rangeStatsError ?? '加载统计失败',
                      onRetry: ledger.loadRangeStats,
                    ),
                  )
                else ...[
                  _BalanceHero(
                    stats: stats,
                    hasDimension: ledger.statsQuery.hasDimension,
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<_StatsView>(
                    showSelectedIcon: false,
                    expandedInsets: EdgeInsets.zero,
                    segments: const [
                      ButtonSegment(
                        value: _StatsView.expense,
                        label: Text('支出', key: ValueKey('stats-view-expense')),
                      ),
                      ButtonSegment(
                        value: _StatsView.income,
                        label: Text('收入', key: ValueKey('stats-view-income')),
                      ),
                    ],
                    selected: {_view},
                    onSelectionChanged: (selection) =>
                        setState(() => _view = selection.first),
                  ),
                  const SizedBox(height: 16),
                  _Metrics(stats: stats, view: _view),
                  const SizedBox(height: 24),
                  _buildChartCard(context, stats),
                  const SizedBox(height: 24),
                  SectionHeader(
                    title: _view == _StatsView.income ? '收入途径' : '支付途径',
                    padding: EdgeInsets.zero,
                  ),
                  _PaymentDistribution(
                    items: _view == _StatsView.income
                        ? stats.incomePaymentDistribution
                        : stats.paymentDistribution,
                    total: _view == _StatsView.income
                        ? stats.income
                        : stats.expense,
                    emptyTitle: _view == _StatsView.income
                        ? '暂无渠道收入'
                        : '暂无渠道支出',
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartCard(BuildContext context, RangeStats stats) {
    final theme = Theme.of(context);
    final finance = financeColors(context);
    final composition = _mode == _ChartMode.composition;
    final income = _view == _StatsView.income;
    final categories =
        (income ? stats.incomeCategoryDistribution : stats.categoryDistribution)
            .where((item) => item.amount > 0)
            .toList();

    return LedgerCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  composition ? (income ? '收入构成' : '支出构成') : '近 6 个月收支',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SegmentedButton<_ChartMode>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(
                    value: _ChartMode.composition,
                    label: Text('构成'),
                  ),
                  ButtonSegment(value: _ChartMode.trend, label: Text('趋势')),
                ],
                selected: {_mode},
                onSelectionChanged: (selection) =>
                    setState(() => _mode = selection.first),
              ),
            ],
          ),
          const SizedBox(height: 12),
          composition
              ? _CompositionPanel(
                  categories: categories,
                  total: income ? stats.income : stats.expense,
                  colors: finance.chart,
                  emptyTitle: income ? '暂无分类收入' : '暂无分类支出',
                  centerLabel: income ? '收入' : '支出',
                  semanticsLabel: income ? '收入构成环形图' : '支出构成环形图',
                )
              : _TrendPanel(
                  trends: stats.monthlyTrends,
                  expenseColor: finance.expense,
                  incomeColor: finance.income,
                ),
        ],
      ),
    );
  }
}

class _StatsSummaryBar extends StatelessWidget {
  const _StatsSummaryBar({required this.summary, required this.onTap});

  final String summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          key: const ValueKey('stats-filter'),
          onPressed: onTap,
          icon: const Icon(Icons.filter_alt_outlined, size: 18),
          label: const Text('筛选'),
        ),
      ],
    );
  }
}

class _StatsFilterSheet extends StatefulWidget {
  const _StatsFilterSheet({required this.initial, required this.categories});

  final StatsQuery initial;
  final List<Category> categories;

  @override
  State<_StatsFilterSheet> createState() => _StatsFilterSheetState();
}

class _StatsFilterSheetState extends State<_StatsFilterSheet> {
  late final DateTime _now;
  late StatsRangePreset _preset;
  late DateTimeRange _range;
  int? _categoryId;
  int? _tagId;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _range = DateTimeRange(
      start: widget.initial.start,
      end: widget.initial.end,
    );
    _preset = rangePresetFor(_range, _now);
    _categoryId = widget.initial.categoryId;
    _tagId = widget.initial.tagId;
  }

  List<Category> get _orderedCategories => [
    ...widget.categories.where((item) => item.type == CategoryType.expense),
    ...widget.categories.where((item) => item.type == CategoryType.income),
  ];

  Category? get _category {
    final matches = widget.categories.where((item) => item.id == _categoryId);
    return matches.isEmpty ? null : matches.first;
  }

  Future<void> _selectPreset(StatsRangePreset preset) async {
    if (preset != StatsRangePreset.custom) {
      setState(() {
        _preset = preset;
        _range = resolveRange(preset, _now);
      });
      return;
    }
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(_now.year, _now.month, _now.day),
      initialDateRange: _range,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _preset = StatsRangePreset.custom;
      _range = picked;
    });
  }

  void _reset() {
    setState(() {
      _preset = StatsRangePreset.month;
      _range = resolveRange(StatsRangePreset.month, _now);
      _categoryId = null;
      _tagId = null;
    });
  }

  void _apply() {
    Navigator.of(context).pop(
      StatsQuery(
        start: _range.start,
        end: _range.end,
        categoryId: _categoryId,
        tagId: _tagId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final category = _category;
    final media = MediaQuery.sizeOf(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: media.height * 0.85),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.outlineVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '筛选',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FilterSectionLabel('日期范围'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final preset in StatsRangePreset.values)
                        ChoiceChip(
                          key: ValueKey('stats-range-${preset.name}'),
                          label: Text(
                            preset == StatsRangePreset.custom &&
                                    _preset == StatsRangePreset.custom
                                ? rangeLabel(StatsRangePreset.custom, _range)
                                : preset.label,
                          ),
                          selected: _preset == preset,
                          onSelected: (_) => _selectPreset(preset),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _FilterSectionLabel('分类'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        key: const ValueKey('stats-category-all'),
                        label: const Text('全部分类'),
                        selected: _categoryId == null,
                        onSelected: (_) => setState(() {
                          _categoryId = null;
                          _tagId = null;
                        }),
                      ),
                      for (final item in _orderedCategories)
                        ChoiceChip(
                          key: ValueKey('stats-category-${item.id}'),
                          label: Text(item.name),
                          selected: _categoryId == item.id,
                          onSelected: (_) => setState(() {
                            _categoryId = item.id;
                            _tagId = null;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _FilterSectionLabel('标签'),
                  const SizedBox(height: 8),
                  if (category == null)
                    Text(
                      '选择分类后可筛选标签',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          key: const ValueKey('stats-tag-all'),
                          label: const Text('全部标签'),
                          selected: _tagId == null,
                          onSelected: (_) => setState(() => _tagId = null),
                        ),
                        for (final tag in category.tags)
                          ChoiceChip(
                            key: ValueKey('stats-tag-${tag.id}'),
                            label: Text(tag.name),
                            selected: _tagId == tag.id,
                            onSelected: (_) => setState(() => _tagId = tag.id),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  TextButton(
                    key: const ValueKey('stats-filter-reset'),
                    onPressed: _reset,
                    child: const Text('重置'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('stats-filter-apply'),
                      onPressed: _apply,
                      child: const Text('应用'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
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

class _BalanceHero extends StatelessWidget {
  const _BalanceHero({required this.stats, required this.hasDimension});

  final RangeStats stats;
  final bool hasDimension;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final finance = financeColors(context);
    final positive = stats.balance >= 0;
    final totalFlow = stats.income + stats.expense;
    final count = stats.expenseCount + stats.incomeCount;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '结余',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (hasDimension)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: finance.incomeContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$count 笔',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: finance.income,
                    ),
                  ),
                )
              else if (stats.income > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: finance.incomeContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '储蓄率 ${formatPercent(stats.balance / stats.income * 100)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: finance.income,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatMoney(stats.balance),
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: positive ? scheme.onSurface : finance.expense,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _HeroMetric(
                  label: '收入',
                  value: stats.income,
                  color: finance.income,
                ),
              ),
              Expanded(
                child: _HeroMetric(
                  label: '支出',
                  value: stats.expense,
                  color: finance.expense,
                ),
              ),
            ],
          ),
          if (totalFlow > 0) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: stats.income / totalFlow,
                minHeight: 6,
                color: finance.income,
                backgroundColor: finance.expense,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            formatMoney(value),
            style: theme.textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.stats, required this.view});

  final RangeStats stats;
  final _StatsView view;

  @override
  Widget build(BuildContext context) {
    final finance = financeColors(context);
    final income = view == _StatsView.income;
    final current = income ? stats.income : stats.expense;
    final previous = income ? stats.previousIncome : stats.previousExpense;
    final count = income ? stats.incomeCount : stats.expenseCount;
    final mom = monthOverMonth(current, previous);
    final noteColor = mom == null
        ? null
        : income
        ? (mom >= 0 ? finance.income : finance.expense)
        : (mom > 0 ? finance.expense : finance.income);
    final items = [
      _MetricData(
        label: income ? '本期收入' : '本期支出',
        value: current,
        note: mom == null
            ? null
            : '较上期 ${mom >= 0 ? '+' : ''}${mom.toStringAsFixed(1)}%',
        noteColor: noteColor,
      ),
      _MetricData(
        label: income ? '日均收入' : '日均支出',
        value: dailyAverage(current, stats.days),
        note: '按 ${stats.days} 天',
      ),
      _MetricData(label: income ? '上期收入' : '上期支出', value: previous),
      _MetricData(
        label: '单笔均额',
        value: count == 0 ? 0 : current / count,
        note: '$count 笔',
      ),
    ];

    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _MetricCard(data: items[0])),
              const SizedBox(width: 12),
              Expanded(child: _MetricCard(data: items[1])),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _MetricCard(data: items[2])),
              const SizedBox(width: 12),
              Expanded(child: _MetricCard(data: items[3])),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricData {
  const _MetricData({
    required this.label,
    required this.value,
    this.note,
    this.noteColor,
  });

  final String label;
  final double value;
  final String? note;
  final Color? noteColor;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.data});

  final _MetricData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LedgerCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: MediaQuery.textScalerOf(context).scale(28),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatMoney(data.value),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (data.note != null)
            Text(
              data.note!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: data.noteColor ?? scheme.onSurfaceVariant,
              ),
            )
          else
            ExcludeSemantics(
              child: Text(
                ' ',
                maxLines: 1,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CompositionPanel extends StatefulWidget {
  const _CompositionPanel({
    required this.categories,
    required this.total,
    required this.colors,
    required this.emptyTitle,
    required this.centerLabel,
    required this.semanticsLabel,
  });

  final List<CategoryStat> categories;
  final double total;
  final List<Color> colors;
  final String emptyTitle;
  final String centerLabel;
  final String semanticsLabel;

  @override
  State<_CompositionPanel> createState() => _CompositionPanelState();
}

class _CompositionPanelState extends State<_CompositionPanel> {
  int? _selectedId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (widget.categories.isEmpty || widget.total <= 0) {
      return EmptyState(title: widget.emptyTitle);
    }
    final selected = widget.categories.where((item) => item.id == _selectedId);
    final selectedCategory = selected.isEmpty ? null : selected.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: DonutChart(
            categories: widget.categories,
            total: widget.total,
            colors: widget.colors,
            centerLabel: widget.centerLabel,
            semanticsLabel: widget.semanticsLabel,
            size: 160,
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < widget.categories.length; i++)
          _LegendRow(
            category: widget.categories[i],
            color: widget.colors[i % widget.colors.length],
            selected: widget.categories[i].id == _selectedId,
            onTap: () => setState(() {
              _selectedId = _selectedId == widget.categories[i].id
                  ? null
                  : widget.categories[i].id;
            }),
          ),
        if (selectedCategory != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${selectedCategory.name} · 细分标签',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                if (selectedCategory.tags.isEmpty)
                  Text(
                    '该分类暂无细分标签',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                else
                  for (final tag in selectedCategory.tags)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              tag.name,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          Text(
                            '${formatMoney(tag.amount, withCurrency: false)} · ${formatPercent(tag.percentage)}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.category,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final CategoryStat category;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? scheme.secondaryContainer.withValues(alpha: 0.55)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                category.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  formatMoney(category.amount, withCurrency: false),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 52,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  formatPercent(category.percentage),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendPanel extends StatelessWidget {
  const _TrendPanel({
    required this.trends,
    required this.expenseColor,
    required this.incomeColor,
  });

  final List<MonthlyTrend> trends;
  final Color expenseColor;
  final Color incomeColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (trends.isEmpty) return const EmptyState(title: '暂无趋势数据');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        TrendChart(
          trends: trends,
          expenseColor: expenseColor,
          incomeColor: incomeColor,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _DotLabel(color: expenseColor, label: '支出'),
            const SizedBox(width: 20),
            _DotLabel(color: incomeColor, label: '收入'),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '单位为元，按服务端自然月统计',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _DotLabel extends StatelessWidget {
  const _DotLabel({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _PaymentDistribution extends StatelessWidget {
  const _PaymentDistribution({
    required this.items,
    required this.total,
    required this.emptyTitle,
  });

  final List<PaymentMethodStat> items;
  final double total;
  final String emptyTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sorted = [...items]..sort((a, b) => b.amount.compareTo(a.amount));
    return LedgerCard(
      child: sorted.isEmpty
          ? EmptyState(title: emptyTitle)
          : Column(
              children: [
                for (var i = 0; i < sorted.length; i++) ...[
                  if (i > 0) const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          sorted[i].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            formatMoney(sorted[i].amount, withCurrency: false),
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 48,
                        child: Text(
                          formatPercent(sorted[i].percentage),
                          textAlign: TextAlign.right,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: ratioOf(sorted[i].amount, total),
                      minHeight: 5,
                      color: scheme.primary,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
