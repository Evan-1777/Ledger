import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/models.dart';
import '../../core/format/money.dart';
import '../../core/state/ledger_controller.dart';
import '../../core/state/preferences_controller.dart';
import '../../core/theme/finance_colors.dart';
import '../../core/widgets/ledger_widgets.dart';
import 'assets_utils.dart';

class AssetsScreen extends StatelessWidget {
  const AssetsScreen({super.key, required this.onManage});

  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final ledger = context.watch<LedgerController>();
    final preferences = context.watch<PreferencesController>();
    final stats = ledger.stats;

    return RefreshIndicator(
      onRefresh: ledger.refreshAll,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverAppBar.large(title: Text('资产')),
          if (stats == null && ledger.statsLoading)
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 100),
              sliver: SliverToBoxAdapter(child: SkeletonList(rows: 5)),
            )
          else if (stats == null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorState(
                message: ledger.statsError ?? '加载资产失败',
                onRetry: ledger.loadStats,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  _content(context, stats.assetSummary, preferences),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _content(
    BuildContext context,
    AssetSummary summary,
    PreferencesController preferences,
  ) {
    final theme = Theme.of(context);
    final derived = deriveAssets(summary);
    final hide = preferences.hideAmounts;
    final finance = financeColors(context);

    String money(double value) =>
        hide ? '••••' : formatMoney(value, withCurrency: false);

    return [
      Text(
        '账户与额度',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 12),
      _NetWorthHero(
        summary: summary,
        derived: derived,
        hide: hide,
        onToggle: preferences.toggleHideAmounts,
        money: money,
      ),
      SectionHeader(title: '资产账户', actionLabel: '管理', onAction: onManage),
      if (derived.assets.isEmpty)
        LedgerCard(
          child: EmptyState(
            title: '暂无资产账户',
            icon: Icons.account_balance_wallet_outlined,
            actionLabel: '添加',
            onAction: onManage,
          ),
        )
      else
        LedgerCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < derived.assets.length; i++) ...[
                _AssetRow(
                  view: derived.assets[i],
                  color: finance.chart[i % finance.chart.length],
                  hidden: hide,
                  money: money,
                ),
                if (i != derived.assets.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
      SectionHeader(title: '负债账户', actionLabel: '管理', onAction: onManage),
      if (derived.liabilities.isEmpty)
        LedgerCard(
          child: EmptyState(
            title: '暂无负债账户',
            icon: Icons.credit_card_outlined,
            actionLabel: '添加',
            onAction: onManage,
          ),
        )
      else
        LedgerCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < derived.liabilities.length; i++) ...[
                _LiabilityRow(
                  channel: derived.liabilities[i],
                  hidden: hide,
                  money: money,
                ),
                if (i != derived.liabilities.length - 1)
                  const Divider(height: 1),
              ],
            ],
          ),
        ),
    ];
  }
}

class _NetWorthHero extends StatelessWidget {
  const _NetWorthHero({
    required this.summary,
    required this.derived,
    required this.hide,
    required this.onToggle,
    required this.money,
  });

  final AssetSummary summary;
  final DerivedAssets derived;
  final bool hide;
  final VoidCallback onToggle;
  final String Function(double) money;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final finance = financeColors(context);
    final positiveAssets = derived.assets
        .where((item) => item.share > 0)
        .toList();

    return LedgerCard(
      radius: 28,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '净资产',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                tooltip: hide ? '显示金额' : '隐藏金额',
                onPressed: onToggle,
                icon: Icon(
                  hide
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ],
          ),
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
                  hide
                      ? '••••'
                      : formatMoney(summary.netAssets, withCurrency: false),
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: summary.netAssets < 0
                        ? finance.expense
                        : scheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _HeroStat(
                  label: '资产总计',
                  value: money(summary.totalAssets),
                ),
              ),
              Expanded(
                child: _HeroStat(
                  label: '负债总计',
                  value: money(summary.totalLiabilities),
                ),
              ),
              Expanded(
                child: _HeroStat(
                  label: '资产负债率',
                  value: derived.debtRatio == null
                      ? '—'
                      : formatPercent(derived.debtRatio!),
                ),
              ),
            ],
          ),
          if (positiveAssets.isNotEmpty) ...[
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    for (var i = 0; i < positiveAssets.length; i++)
                      Expanded(
                        flex: (positiveAssets[i].share * 1000).round(),
                        child: ColoredBox(
                          color: finance.chart[i % finance.chart.length],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                for (var i = 0; i < positiveAssets.length; i++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: finance.chart[i % finance.chart.length],
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${positiveAssets[i].channel.name} ${formatPercent(positiveAssets[i].share * 100)}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _AssetRow extends StatelessWidget {
  const _AssetRow({
    required this.view,
    required this.color,
    required this.hidden,
    required this.money,
  });

  final AssetView view;
  final Color color;
  final bool hidden;
  final String Function(double) money;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final finance = financeColors(context);
    final balance = view.channel.remainingBalance;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.account_balance_wallet_outlined,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  view.channel.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: view.share > 0 ? color : Colors.transparent,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        view.share > 0
                            ? formatPercent(view.share * 100)
                            : '暂无占比',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    money(balance),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: balance < 0 ? finance.expense : null,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Text(
                  '余额',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LiabilityRow extends StatelessWidget {
  const _LiabilityRow({
    required this.channel,
    required this.hidden,
    required this.money,
  });

  final LiabilityChannelStat channel;
  final bool hidden;
  final String Function(double) money;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final finance = financeColors(context);
    final usage = liabilityUsage(channel);
    final warning = usage >= 80;
    final hasLimit = channel.creditLimit > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.credit_card_outlined,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasLimit
                          ? '额度 ${money(channel.creditLimit)} · 可用 ${money(channel.remainingCredit)}'
                          : '不设额度',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        money(channel.currentDebt),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: channel.currentDebt > 0
                              ? finance.expense
                              : scheme.onSurface,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Text(
                      '欠款',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (hasLimit) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: (usage / 100).clamp(0, 1).toDouble(),
                      minHeight: 5,
                      color: warning ? finance.expense : scheme.primary,
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '已用 ${formatPercent(usage)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: warning ? finance.expense : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
