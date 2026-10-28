import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ledger_app/core/api/api_exception.dart';
import 'package:ledger_app/core/api/models.dart';
import 'package:ledger_app/core/state/ledger_controller.dart';
import 'package:ledger_app/core/storage/ledger_cache.dart';

import '../support/fakes.dart';
import '../support/harness.dart';

void main() {
  Future<http.Response> standardHandler(http.Request request) async {
    switch (request.url.path) {
      case '/api/categories':
        return jsonResponse([
          {
            'id': 1,
            'name': '餐饮美食',
            'sort_order': 1,
            'type': 'expense',
            'created_at': '',
            'tags': [
              {'id': 1, 'category_id': 1, 'name': '午餐', 'sort_order': 1},
            ],
          },
        ]);
      case '/api/payment-methods':
        return jsonResponse([
          {
            'id': 1,
            'name': '招商银行卡',
            'sort_order': 1,
            'type': 'asset',
            'initial_balance': 0,
            'credit_limit': 0,
            'created_at': '',
          },
        ]);
      case '/api/transactions':
        return jsonResponse([transactionJson()]);
      case '/api/stats/summary':
        return jsonResponse(statsJson());
      default:
        return jsonResponse({});
    }
  }

  test('loadAll fills configuration, transactions and stats', () async {
    final controllers = await testControllersWithHandler(standardHandler);

    await controllers.ledger.loadAll();

    expect(controllers.ledger.categories.single.name, '餐饮美食');
    expect(controllers.ledger.channels.single.name, '招商银行卡');
    expect(controllers.ledger.transactions.single.description, '午餐 · 牛肉面');
    expect(controllers.ledger.stats?.monthBalance, 9551.5);
    expect(controllers.ledger.transactionsError, isNull);
  });

  test('hydrates cached data without entering loading', () async {
    final cache = MemoryLedgerCache()
      ..config = CachedLedgerConfig(
        categories: [category()],
        channels: [paymentMethod()],
      )
      ..transactions = [transactionModel()]
      ..stats = StatsSummary.fromJson(statsJson());
    final controllers = await testControllersWithHandler(
      standardHandler,
      cache: cache,
    );

    controllers.ledger.hydrateFromCache();

    expect(controllers.ledger.categories.single.name, '餐饮美食');
    expect(controllers.ledger.channels.single.name, '招商银行卡');
    expect(controllers.ledger.transactions.single.description, '午餐 · 牛肉面');
    expect(controllers.ledger.stats?.monthBalance, 9551.5);
    expect(controllers.ledger.configLoading, isFalse);
    expect(controllers.ledger.transactionsLoading, isFalse);
    expect(controllers.ledger.statsLoading, isFalse);
  });

  test('hydrate fills only the domains present in the cache', () async {
    final cache = MemoryLedgerCache()..transactions = [transactionModel()];
    final controllers = await testControllersWithHandler(
      standardHandler,
      cache: cache,
    );

    controllers.ledger.hydrateFromCache();

    expect(controllers.ledger.transactions.single.description, '午餐 · 牛肉面');
    expect(controllers.ledger.stats, isNull);
    expect(controllers.ledger.categories, isEmpty);
    expect(controllers.ledger.channels, isEmpty);
    expect(controllers.ledger.transactionsLoading, isFalse);
  });

  test('loadAll writes each domain back to the cache', () async {
    final cache = MemoryLedgerCache();
    final controllers = await testControllersWithHandler(
      standardHandler,
      cache: cache,
    );

    await controllers.ledger.loadAll();

    expect(cache.configWrites, 1);
    expect(cache.transactionWrites, 1);
    expect(cache.statsWrites, 1);
    expect(cache.config!.categories.single.name, '餐饮美食');
    expect(cache.transactions!.single.description, '午餐 · 牛肉面');
    expect(cache.stats!.monthBalance, 9551.5);
  });

  test(
    'a failed refresh keeps cached data and leaves the cache untouched',
    () async {
      final cache = MemoryLedgerCache()
        ..config = CachedLedgerConfig(
          categories: [category()],
          channels: [paymentMethod()],
        )
        ..transactions = [transactionModel(description: '缓存流水')]
        ..stats = StatsSummary.fromJson(statsJson());
      final controllers = await testControllersWithHandler(
        (request) async => jsonResponse({'error': 'server error'}, status: 500),
        cache: cache,
      );
      controllers.ledger.hydrateFromCache();

      await controllers.ledger.loadAll();

      expect(controllers.ledger.transactions.single.description, '缓存流水');
      expect(controllers.ledger.categories.single.name, '餐饮美食');
      expect(controllers.ledger.configError, isNotNull);
      expect(controllers.ledger.transactionsError, isNotNull);
      expect(controllers.ledger.statsError, isNotNull);
      expect(cache.configWrites, 0);
      expect(cache.transactionWrites, 0);
      expect(cache.statsWrites, 0);
    },
  );

  test(
    'filtered transaction refreshes do not replace the cached full list',
    () async {
      final cache = MemoryLedgerCache();
      final controllers = await testControllersWithHandler((request) async {
        if (request.url.path == '/api/transactions' &&
            request.url.queryParameters['type'] == 'expense') {
          return jsonResponse([transactionJson(description: '支出结果')]);
        }
        return standardHandler(request);
      }, cache: cache);

      await controllers.ledger.loadAll();
      await controllers.ledger.setFilter(TransactionFilter.expense);

      expect(cache.transactionWrites, 1);
      expect(cache.transactions!.single.description, '午餐 · 牛肉面');
      expect(controllers.ledger.transactions.single.description, '支出结果');
    },
  );

  test(
    'a stale transaction response cannot overwrite the new filter',
    () async {
      final controllers = await testControllersWithHandler((request) async {
        if (request.url.path == '/api/transactions') {
          final type = request.url.queryParameters['type'];
          if (type == 'expense') {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            return jsonResponse([transactionJson(description: '支出结果')]);
          }
          await Future<void>.delayed(const Duration(milliseconds: 80));
          return jsonResponse([transactionJson(description: '旧的全部结果')]);
        }
        return standardHandler(request);
      });

      final stale = controllers.ledger.loadTransactions();
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await controllers.ledger.setFilter(TransactionFilter.expense);
      await stale;
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(controllers.ledger.transactions.single.description, '支出结果');
    },
  );

  test('a stale config success cannot repopulate cleared data', () async {
    final controllers = await testControllersWithHandler((request) async {
      if (request.url.path == '/api/categories' ||
          request.url.path == '/api/payment-methods') {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return standardHandler(request);
    });
    final ledger = LedgerController(
      api: controllers.api,
      onSessionExpired: () async {},
    );

    final pending = ledger.loadConfig();
    await Future<void>.delayed(const Duration(milliseconds: 2));
    ledger.clear();
    await pending;

    expect(ledger.categories, isEmpty);
    expect(ledger.channels, isEmpty);
    expect(ledger.configError, isNull);
    expect(ledger.configLoading, isFalse);
  });

  test('a stale config 401 cannot expire a cleared session', () async {
    var expired = 0;
    final controllers = await testControllersWithHandler((request) async {
      if (request.url.path == '/api/categories' ||
          request.url.path == '/api/payment-methods') {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return jsonResponse({'error': 'unauthorized'}, status: 401);
      }
      return standardHandler(request);
    });
    final ledger = LedgerController(
      api: controllers.api,
      onSessionExpired: () async => expired++,
    );

    final pending = ledger.loadConfig();
    await Future<void>.delayed(const Duration(milliseconds: 2));
    ledger.clear();
    await pending;

    expect(expired, 0);
    expect(ledger.categories, isEmpty);
    expect(ledger.channels, isEmpty);
    expect(ledger.configError, isNull);
    expect(ledger.configLoading, isFalse);
  });

  test('a failed category swap restores the first sort order', () async {
    final puts = <http.Request>[];
    var failed = false;
    final controllers = await testControllersWithHandler((request) async {
      if (request.method == 'PUT' &&
          request.url.path.startsWith('/api/categories/')) {
        puts.add(request);
        if (request.url.path == '/api/categories/2' && !failed) {
          failed = true;
          return jsonResponse({'error': 'server error'}, status: 500);
        }
        final id = int.parse(request.url.pathSegments.last);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return jsonResponse({
          'id': id,
          'name': id == 1 ? '餐饮美食' : '交通出行',
          'sort_order': body['sort_order'],
          'type': 'expense',
          'created_at': '',
          'tags': <Object?>[],
        });
      }
      return defaultApi(request);
    });
    await controllers.ledger.loadAll();
    final first = controllers.ledger.categories.firstWhere(
      (category) => category.id == 1,
    );

    await expectLater(
      controllers.ledger.moveCategory(first, 1),
      throwsA(isA<ApiException>()),
    );

    expect(
      puts.map((request) => jsonDecode(request.body)['sort_order']).toList(),
      [2, 1, 1],
    );
    expect(
      puts.every(
        (request) => !(jsonDecode(request.body) as Map<String, dynamic>)
            .containsKey('exclude_from_stats'),
      ),
      isTrue,
    );
  });

  test(
    'category stats toggle writes the flag and refreshes config and stats',
    () async {
      var configGets = 0;
      var statsGets = 0;
      http.Request? put;
      final controllers = await testControllersWithHandler((request) async {
        if (request.method == 'PUT' &&
            request.url.path.startsWith('/api/categories/')) {
          put = request;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return jsonResponse({
            'id': 1,
            'name': '餐饮美食',
            'sort_order': 1,
            'type': 'expense',
            'exclude_from_stats': body['exclude_from_stats'],
            'created_at': '',
            'tags': <Object?>[],
          });
        }
        if (request.url.path == '/api/categories') {
          configGets++;
        }
        if (request.url.path == '/api/stats/summary') {
          statsGets++;
        }
        return standardHandler(request);
      });
      await controllers.ledger.loadAll();

      await controllers.ledger.setCategoryExcluded(
        controllers.ledger.categories.single,
        true,
      );

      expect(put, isNotNull);
      expect(
        (jsonDecode(put!.body) as Map<String, dynamic>)['exclude_from_stats'],
        isTrue,
      );
      expect(configGets, 2);
      expect(statsGets, 2);
    },
  );

  test('a 401 expires the session and clears business data', () async {
    var expired = 0;
    final controllers = await testControllersWithHandler((request) async {
      if (request.url.path == '/api/transactions') {
        return jsonResponse({'error': 'unauthorized'}, status: 401);
      }
      return standardHandler(request);
    });
    controllers.ledger.categories = [category()];

    final ledger = LedgerController(
      api: controllers.api,
      onSessionExpired: () async => expired++,
    );
    await ledger.loadTransactions();

    expect(expired, 1);
    expect(ledger.categories, isEmpty);
    expect(ledger.transactions, isEmpty);
  });

  test('duplicate delete calls send one request', () async {
    var deletes = 0;
    final controllers = await testControllersWithHandler((request) async {
      if (request.method == 'DELETE') {
        deletes++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return jsonResponse({'success': true});
      }
      return standardHandler(request);
    });
    controllers.ledger.transactions = [Transaction.fromJson(transactionJson())];

    await Future.wait([
      controllers.ledger.deleteTransaction(1),
      controllers.ledger.deleteTransaction(1),
    ]);

    expect(deletes, 1);
  });

  test('creating a transaction refreshes list and stats once', () async {
    var posts = 0;
    var transactionGets = 0;
    var statsGets = 0;
    final controllers = await testControllersWithHandler((request) async {
      if (request.method == 'POST' && request.url.path == '/api/transactions') {
        posts++;
        return jsonResponse(transactionJson());
      }
      if (request.method == 'GET' && request.url.path == '/api/transactions') {
        transactionGets++;
        return jsonResponse([transactionJson()]);
      }
      if (request.url.path == '/api/stats/summary') {
        statsGets++;
        return jsonResponse(statsJson());
      }
      return standardHandler(request);
    });

    await controllers.ledger.createTransaction(
      TransactionInput(
        type: TransactionType.expense,
        amount: -28,
        description: '午餐 · 牛肉面',
        paymentMethodId: 1,
        categoryId: 1,
        tagId: 1,
        transactedAt: DateTime.utc(2026, 10, 19, 4, 42),
      ),
    );

    expect(posts, 1);
    expect(transactionGets, 1);
    expect(statsGets, 1);
  });

  test('channel changes refresh configuration and stats', () async {
    var configGets = 0;
    var statsGets = 0;
    final controllers = await testControllersWithHandler((request) async {
      if (request.method == 'POST' &&
          request.url.path == '/api/payment-methods') {
        return jsonResponse({
          'id': 2,
          'name': '现金',
          'sort_order': 2,
          'type': 'asset',
          'initial_balance': 0,
          'credit_limit': 0,
          'created_at': '',
        });
      }
      if (request.url.path == '/api/categories' ||
          request.url.path == '/api/payment-methods') {
        configGets++;
        return standardHandler(request);
      }
      if (request.url.path == '/api/stats/summary') {
        statsGets++;
        return jsonResponse(statsJson());
      }
      return standardHandler(request);
    });

    await controllers.ledger.createChannel(
      name: '现金',
      type: ChannelType.asset,
      initialBalance: 0,
      creditLimit: 0,
    );

    expect(configGets, 2);
    expect(statsGets, 1);
  });
}
