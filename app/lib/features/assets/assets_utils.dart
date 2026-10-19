import '../../core/api/models.dart';

class AssetView {
  const AssetView({required this.channel, required this.share});

  final AssetChannelStat channel;
  final double share;
}

class DerivedAssets {
  const DerivedAssets({
    required this.assets,
    required this.liabilities,
    required this.debtRatio,
  });

  final List<AssetView> assets;
  final List<LiabilityChannelStat> liabilities;
  final double? debtRatio;
}

DerivedAssets deriveAssets(AssetSummary summary) {
  final positiveTotal = summary.assetChannels
      .where((item) => item.remainingBalance > 0)
      .fold(0.0, (sum, item) => sum + item.remainingBalance);

  final assets =
      summary.assetChannels
          .map(
            (item) => AssetView(
              channel: item,
              share: positiveTotal > 0 && item.remainingBalance > 0
                  ? item.remainingBalance / positiveTotal
                  : 0,
            ),
          )
          .toList()
        ..sort(
          (a, b) =>
              b.channel.remainingBalance.compareTo(a.channel.remainingBalance),
        );

  final liabilities = [...summary.liabilityChannels]
    ..sort((a, b) => b.currentDebt.compareTo(a.currentDebt));

  final debtRatio = summary.totalAssets > 0
      ? summary.totalLiabilities / summary.totalAssets * 100
      : null;

  return DerivedAssets(
    assets: assets,
    liabilities: liabilities,
    debtRatio: debtRatio,
  );
}

double liabilityUsage(LiabilityChannelStat channel) =>
    channel.usageRate.clamp(0, 100).toDouble();
