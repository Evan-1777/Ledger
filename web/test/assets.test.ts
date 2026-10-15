import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { deriveAssets } from '../src/pages/assetsUtils.ts';
import type { AssetSummary } from '../src/lib/api.ts';

describe('assetsUtils - deriveAssets', () => {
  test('sorts assets and liabilities in descending order', () => {
    const summary: AssetSummary = {
      total_assets: 800,
      total_liabilities: 600,
      net_assets: 200,
      asset_channels: [
        { id: 1, name: 'A', type: 'asset', remaining_balance: 100, initial_balance: 0, percentage: 0 },
        { id: 2, name: 'B', type: 'asset', remaining_balance: 500, initial_balance: 0, percentage: 0 },
        { id: 3, name: 'C', type: 'asset', remaining_balance: 200, initial_balance: 0, percentage: 0 },
      ],
      liability_channels: [
        { id: 1, name: 'L1', type: 'liability', current_debt: 100, initial_debt: 0, credit_limit: 1000, remaining_credit: 900, usage_rate: 10 },
        { id: 2, name: 'L2', type: 'liability', current_debt: 300, initial_debt: 0, credit_limit: 1000, remaining_credit: 700, usage_rate: 30 },
        { id: 3, name: 'L3', type: 'liability', current_debt: 200, initial_debt: 0, credit_limit: 1000, remaining_credit: 800, usage_rate: 20 },
      ],
    };

    const res = deriveAssets(summary);
    assert.deepStrictEqual(
      res.assets.map((a) => a.remaining_balance),
      [500, 200, 100]
    );
    assert.deepStrictEqual(
      res.liabilities.map((l) => l.current_debt),
      [300, 200, 100]
    );
  });

  test('negative balance gets share 0 and remaining positive shares sum to 100', () => {
    const summary: AssetSummary = {
      total_assets: 950,
      total_liabilities: 0,
      net_assets: 950,
      asset_channels: [
        { id: 1, name: 'A', type: 'asset', remaining_balance: 300, initial_balance: 0, percentage: 0 },
        { id: 2, name: 'B', type: 'asset', remaining_balance: -50, initial_balance: 0, percentage: 0 },
        { id: 3, name: 'C', type: 'asset', remaining_balance: 700, initial_balance: 0, percentage: 0 },
      ],
      liability_channels: [],
    };

    const res = deriveAssets(summary);
    const bChannel = res.assets.find((a) => a.id === 2);
    assert.strictEqual(bChannel?.share, 0);

    const positiveSharesSum = res.assets
      .filter((a) => a.remaining_balance > 0)
      .reduce((sum, a) => sum + a.share, 0);
    assert.strictEqual(positiveSharesSum, 100);

    const aChannel = res.assets.find((a) => a.id === 1);
    const cChannel = res.assets.find((a) => a.id === 3);
    assert.strictEqual(aChannel?.share, 30);
    assert.strictEqual(cChannel?.share, 70);
  });

  test('debtRatio is null when total_assets is 0 or negative', () => {
    const summaryZero: AssetSummary = {
      total_assets: 0,
      total_liabilities: 500,
      net_assets: -500,
      asset_channels: [],
      liability_channels: [],
    };
    assert.strictEqual(deriveAssets(summaryZero).debtRatio, null);

    const summaryPositive: AssetSummary = {
      total_assets: 1000,
      total_liabilities: 250,
      net_assets: 750,
      asset_channels: [],
      liability_channels: [],
    };
    assert.strictEqual(deriveAssets(summaryPositive).debtRatio, 25);
  });

  test('liabilities without credit limit are excluded from credit aggregate', () => {
    const summary: AssetSummary = {
      total_assets: 10000,
      total_liabilities: 9000,
      net_assets: 1000,
      asset_channels: [],
      liability_channels: [
        { id: 1, name: 'CreditCard1', type: 'liability', current_debt: 3000, initial_debt: 0, credit_limit: 10000, remaining_credit: 7000, usage_rate: 30 },
        { id: 2, name: 'CreditCard2', type: 'liability', current_debt: 2000, initial_debt: 0, credit_limit: 5000, remaining_credit: 3000, usage_rate: 40 },
        { id: 3, name: 'Mortgage', type: 'liability', current_debt: 4000, initial_debt: 0, credit_limit: 0, remaining_credit: 0, usage_rate: 0 },
      ],
    };

    const res = deriveAssets(summary);
    assert.notStrictEqual(res.credit, null);
    assert.strictEqual(res.credit?.limit, 15000);
    assert.strictEqual(res.credit?.used, 5000);
    assert.strictEqual(Math.round(res.credit?.usage ?? 0), 33);
    assert.strictEqual(res.credit?.available, 10000);
  });

  test('credit is null when all liabilities have no credit limit', () => {
    const summary: AssetSummary = {
      total_assets: 10000,
      total_liabilities: 5000,
      net_assets: 5000,
      asset_channels: [],
      liability_channels: [
        { id: 1, name: 'Mortgage', type: 'liability', current_debt: 4000, initial_debt: 0, credit_limit: 0, remaining_credit: 0, usage_rate: 0 },
        { id: 2, name: 'Loan', type: 'liability', current_debt: 1000, initial_debt: 0, credit_limit: 0, remaining_credit: 0, usage_rate: 0 },
      ],
    };

    const res = deriveAssets(summary);
    assert.strictEqual(res.credit, null);
  });

  test('credit available clamps to 0 when debt exceeds credit limit', () => {
    const summary: AssetSummary = {
      total_assets: 10000,
      total_liabilities: 12000,
      net_assets: -2000,
      asset_channels: [],
      liability_channels: [
        { id: 1, name: 'Card', type: 'liability', current_debt: 12000, initial_debt: 0, credit_limit: 10000, remaining_credit: -2000, usage_rate: 120 },
      ],
    };

    const res = deriveAssets(summary);
    assert.strictEqual(res.credit?.available, 0);
    assert.strictEqual(res.credit?.usage, 120);
  });

  test('share is 0 when all asset balances are zero or negative', () => {
    const summary: AssetSummary = {
      total_assets: 0,
      total_liabilities: 0,
      net_assets: 0,
      asset_channels: [
        { id: 1, name: 'Zero', type: 'asset', remaining_balance: 0, initial_balance: 0, percentage: 0 },
        { id: 2, name: 'Negative', type: 'asset', remaining_balance: -100, initial_balance: 0, percentage: 0 },
      ],
      liability_channels: [],
    };

    const res = deriveAssets(summary);
    assert.strictEqual(res.assets[0].share, 0);
    assert.strictEqual(res.assets[1].share, 0);
  });
});
