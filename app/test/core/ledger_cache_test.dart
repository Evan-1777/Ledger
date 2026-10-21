import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/core/api/models.dart';
import 'package:ledger_app/core/storage/ledger_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

Map<String, dynamic> _encodeDecode(Map<String, dynamic> source) =>
    jsonDecode(jsonEncode(source)) as Map<String, dynamic>;

Future<SharedPreferencesLedgerCache> _cacheFor(String? serverUrl) async {
  final preferences = await SharedPreferences.getInstance();
  return SharedPreferencesLedgerCache(
    preferences: preferences,
    serverUrl: () => serverUrl,
  );
}

CachedLedgerConfig _config() => CachedLedgerConfig(
  categories: [
    category(tags: const [Tag(id: 7, categoryId: 1, name: '早餐', sortOrder: 2)]),
    const Category(
      id: 8,
      name: '债务偿还',
      sortOrder: 8,
      type: CategoryType.system,
      tags: [],
    ),
  ],
  channels: [
    paymentMethod(),
    paymentMethod(
      id: 5,
      name: '招商信用卡',
      type: ChannelType.liability,
      creditLimit: 20000,
    ),
  ],
);

void main() {
  setUpAll(initTestLocale);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('model json round-trip', () {
    test('stats survive a json encode', () {
      final stats = StatsSummary.fromJson(statsJson());

      final restored = StatsSummary.fromJson(_encodeDecode(stats.toJson()));

      expect(restored.toJson(), equals(stats.toJson()));
    });

    test('transaction survives a json encode', () {
      final transaction = Transaction.fromJson(transactionJson());

      final restored = Transaction.fromJson(
        _encodeDecode(transaction.toJson()),
      );

      expect(restored.toJson(), equals(transaction.toJson()));
    });

    test('a system category keeps its type', () {
      final category = Category.fromJson({
        'id': 8,
        'name': '债务偿还',
        'sort_order': 8,
        'type': 'system',
        'tags': [
          {'id': 8, 'category_id': 8, 'name': '负债还款', 'sort_order': 1},
        ],
      });

      final restored = Category.fromJson(_encodeDecode(category.toJson()));

      expect(restored.type, CategoryType.system);
      expect(restored.toJson(), equals(category.toJson()));
    });

    test('payment method survives a json encode', () {
      final channel = paymentMethod(
        type: ChannelType.liability,
        initialBalance: 1200,
        creditLimit: 20000,
      );

      final restored = PaymentMethod.fromJson(_encodeDecode(channel.toJson()));

      expect(restored.toJson(), equals(channel.toJson()));
    });
  });

  group('SharedPreferencesLedgerCache', () {
    test('round-trips configuration, transactions and stats', () async {
      final cache = await _cacheFor('https://ledger.test');

      await cache.writeConfig(_config());
      await cache.writeTransactions([transactionModel()]);
      await cache.writeStats(StatsSummary.fromJson(statsJson()));

      final config = cache.readConfig()!;
      expect(
        [for (final item in config.categories) item.name],
        ['餐饮美食', '债务偿还'],
      );
      expect(config.categories.last.type, CategoryType.system);
      expect(config.categories.first.tags.single.name, '早餐');
      expect(config.channels.last.type, ChannelType.liability);
      expect(config.channels.last.creditLimit, 20000);

      final transaction = cache.readTransactions()!.single;
      expect(transaction.description, '午餐 · 牛肉面');
      expect(transaction.amountCents, -2800);
      expect(transaction.transactedAt, transactionModel().transactedAt);

      final stats = cache.readStats()!;
      expect(stats.monthBalance, 9551.5);
      expect(stats.assetSummary.netAssets, 73520);
      expect(stats.categoryDistribution.single.tags.single.name, '午餐');
    });

    test('ignores entries saved for another server', () async {
      final preferences = await SharedPreferences.getInstance();
      final old = SharedPreferencesLedgerCache(
        preferences: preferences,
        serverUrl: () => 'https://old.example.com',
      );
      await old.writeConfig(_config());
      await old.writeTransactions([transactionModel()]);
      await old.writeStats(StatsSummary.fromJson(statsJson()));

      final next = SharedPreferencesLedgerCache(
        preferences: preferences,
        serverUrl: () => 'https://new.example.com',
      );

      expect(next.readConfig(), isNull);
      expect(next.readTransactions(), isNull);
      expect(next.readStats(), isNull);
    });

    test('ignores corrupt entries', () async {
      final preferences = await SharedPreferences.getInstance();
      final cache = SharedPreferencesLedgerCache(
        preferences: preferences,
        serverUrl: () => 'https://ledger.test',
      );
      await cache.writeConfig(_config());
      await cache.writeTransactions([transactionModel()]);
      await cache.writeStats(StatsSummary.fromJson(statsJson()));
      for (final key in const [
        'ledger_cache_config',
        'ledger_cache_transactions',
        'ledger_cache_stats',
      ]) {
        await preferences.setString(key, 'not-json');
      }

      expect(cache.readConfig(), isNull);
      expect(cache.readTransactions(), isNull);
      expect(cache.readStats(), isNull);
    });

    test('ignores malformed payload shapes', () async {
      final preferences = await SharedPreferences.getInstance();
      final cache = SharedPreferencesLedgerCache(
        preferences: preferences,
        serverUrl: () => 'https://ledger.test',
      );
      await preferences.setString(
        'ledger_cache_transactions',
        jsonEncode({
          'version': 1,
          'server': 'https://ledger.test',
          'data': 'not-a-list',
        }),
      );
      await preferences.setString(
        'ledger_cache_stats',
        jsonEncode({
          'version': 1,
          'server': 'https://ledger.test',
          'data': 'not-a-map',
        }),
      );

      expect(cache.readTransactions(), isNull);
      expect(cache.readStats(), isNull);
    });

    test('skips writes without a server address', () async {
      final preferences = await SharedPreferences.getInstance();
      final cache = SharedPreferencesLedgerCache(
        preferences: preferences,
        serverUrl: () => null,
      );

      await cache.writeConfig(_config());
      await cache.writeTransactions([transactionModel()]);
      await cache.writeStats(StatsSummary.fromJson(statsJson()));

      expect(preferences.getString('ledger_cache_transactions'), isNull);
      final reader = SharedPreferencesLedgerCache(
        preferences: preferences,
        serverUrl: () => 'https://ledger.test',
      );
      expect(reader.readConfig(), isNull);
      expect(reader.readTransactions(), isNull);
      expect(reader.readStats(), isNull);
    });
  });
}
