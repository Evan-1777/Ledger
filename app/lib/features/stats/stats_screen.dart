import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/models.dart';
import '../../core/format/dates.dart';
import '../../core/format/money.dart';
import '../../core/state/ledger_controller.dart';
import '../../core/theme/finance_colors.dart';
import '../../core/widgets/ledger_widgets.dart';
import 'charts.dart';
import 'stats_utils.dart';

enum _ChartMode { composition, trend }

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  _ChartMode _mode = _ChartMode.composition;

  @override
  Widget build(BuildContext context) {
    final ledger = context.watch<LedgerController>();
    final stats = ledger.stats;
    final now = DateTime.now();

    return RefreshIndicator(
      onRefresh: ledger.loadAll,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverAppBar.large(title: Text('统计')),
          if (stats == null && ledger.statsLoading)
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 100),
              sliver: SliverToBoxAdapter(child: SkeletonList(rows: 5)),
            )
          else if (stats == null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorState(
                message: ledger.statsError ?? '加载统计失败',
                onRetry: ledger.loadStats,
              ),
            )
          else
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
                  _BalanceHero(stats: stats),
                  const SizedBox(height: 16),
                  _Metrics(stats: stats, now: now),
                  const SizedBox(height: 24),
                  _buildChartCard(context, stats),
                  const SizedBox(height: 24),
                  const SectionHeader(title: '支付途径', padding: EdgeInsets.zero),
                  _PaymentDistribution(
                    items: stats.paymentDistribution,
                    total: stats.monthExpense,
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChartCard(BuildContext context, StatsSummary stats) {
    final theme = Theme.of(context);
    final finance = financeColors(context);
    final composition = _mode == _ChartMode.composition;
    final categories = stats.categoryDistribution
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
                  composition ? '支出构成' : '近 6 个月收支',
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
          SizedBox(
            height: 400,
            child: composition
                ? _CompositionPanel(
                    categories: categories,
                    total: stats.monthExpense,
                    colors: finance.chart,
                  )
                : _TrendPanel(
                    trends: stats.monthlyTrends,
                    expenseColor: finance.expense,
                    incomeColor: finance.income,
                  ),
          ),
        ],
      ),
    );
  }
}

class _BalanceHero extends StatelessWidget {
  const _BalanceHero({required this.stats});

  final StatsSummary stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final finance = financeColors(context);
    final positive = stats.monthBalance >= 0;
    final totalFlow = stats.monthIncome + stats.monthExpense;

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
                  '本月结余',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (stats.monthIncome > 0)
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
                    '储蓄率 ${formatPercent(stats.savingsRate)}',
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
              formatMoney(stats.monthBalance),
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
                  value: stats.monthIncome,
                  color: finance.income,
                ),
              ),
              Expanded(
                child: _HeroMetric(
                  label: '支出',
                  value: stats.monthExpense,
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
                value: stats.monthIncome / totalFlow,
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
  const _Metrics({required this.stats, required this.now});

  final StatsSummary stats;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final finance = financeColors(context);
    final mom = monthOverMonth(stats);
    final items = [
      _MetricData(label: '本周花费', value: stats.weekExpense),
      _MetricData(
        label: '当月花费',
        value: stats.monthExpense,
        note: mom == null
            ? null
            : '较上月 ${mom >= 0 ? '+' : ''}${mom.toStringAsFixed(1)}%',
        noteColor: mom == null
            ? null
            : (mom > 0 ? finance.expense : finance.income),
      ),
      _MetricData(label: '上月花费', value: stats.lastMonthExpense),
      _MetricData(
        label: '日均花费',
        value: dailyAverage(stats, now),
        note: '按已过 ${now.day} 天',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: _MetricCard(data: item),
              ),
          ],
        );
      },
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
          FittedBox(
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
          if (data.note != null) ...[
            const SizedBox(height: 4),
            Text(
              data.note!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: data.noteColor ?? scheme.onSurfaceVariant,
              ),
            ),
          ],
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
  });

  final List<CategoryStat> categories;
  final double total;
  final List<Color> colors;

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
      return const EmptyState(title: '当月暂无分类支出');
    }
    final selected = widget.categories.where((item) => item.id == _selectedId);
    final selectedCategory = selected.isEmpty ? null : selected.first;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: DonutChart(
              categories: widget.categories,
              total: widget.total,
              colors: widget.colors,
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
      ),
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
            Text(
              formatMoney(category.amount, withCurrency: false),
              style: theme.textTheme.labelMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 52,
              child: Text(
                formatPercent(category.percentage),
                textAlign: TextAlign.right,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
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
    return SingleChildScrollView(
      child: Column(
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
      ),
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
  const _PaymentDistribution({required this.items, required this.total});

  final List<PaymentMethodStat> items;
  final double total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sorted = [...items]..sort((a, b) => b.amount.compareTo(a.amount));
    return LedgerCard(
      child: sorted.isEmpty
          ? const EmptyState(title: '当月暂无渠道支出')
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
                      Text(
                        formatMoney(sorted[i].amount, withCurrency: false),
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
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
