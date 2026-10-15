import type { AssetSummary, AssetChannelStat, LiabilityChannelStat } from '../lib/api';

export interface DerivedAssetItem extends AssetChannelStat {
  share: number;
}

export interface CreditSummary {
  limit: number;
  used: number;
  usage: number;
  available: number;
}

export interface DerivedAssets {
  assets: DerivedAssetItem[];
  liabilities: LiabilityChannelStat[];
  debtRatio: number | null;
  credit: CreditSummary | null;
  totalAssets: number;
  totalLiabilities: number;
  netAssets: number;
}

export function deriveAssets(summary: AssetSummary): DerivedAssets {
  const assetChannels = summary.asset_channels || [];
  const liabilityChannels = summary.liability_channels || [];

  const sortedAssets = [...assetChannels].sort(
    (a, b) => b.remaining_balance - a.remaining_balance
  );
  const sortedLiabilities = [...liabilityChannels].sort(
    (a, b) => b.current_debt - a.current_debt
  );

  const positiveSum = sortedAssets.reduce(
    (sum, ch) => sum + Math.max(0, ch.remaining_balance),
    0
  );

  const assets: DerivedAssetItem[] = sortedAssets.map((ch) => ({
    ...ch,
    share: positiveSum > 0 ? (Math.max(0, ch.remaining_balance) / positiveSum) * 100 : 0,
  }));

  const totalAssets = summary.total_assets;
  const totalLiabilities = summary.total_liabilities;
  const netAssets = summary.net_assets;

  const debtRatio = totalAssets > 0 ? (totalLiabilities / totalAssets) * 100 : null;

  const creditLiabilities = sortedLiabilities.filter((ch) => ch.credit_limit > 0);
  let credit: CreditSummary | null = null;
  if (creditLiabilities.length > 0) {
    const limit = creditLiabilities.reduce((sum, ch) => sum + ch.credit_limit, 0);
    const used = creditLiabilities.reduce((sum, ch) => sum + ch.current_debt, 0);
    const usage = limit > 0 ? (used / limit) * 100 : 0;
    const available = Math.max(limit - used, 0);
    credit = { limit, used, usage, available };
  }

  return {
    assets,
    liabilities: sortedLiabilities,
    debtRatio,
    credit,
    totalAssets,
    totalLiabilities,
    netAssets,
  };
}
