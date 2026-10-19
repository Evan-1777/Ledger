import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ledger_app/core/api/api_client.dart';
import 'package:ledger_app/core/state/ledger_controller.dart';
import 'package:ledger_app/core/state/preferences_controller.dart';
import 'package:ledger_app/core/theme/app_theme.dart';
import 'package:ledger_app/features/auth/session_controller.dart';
import 'package:provider/provider.dart';

import 'fakes.dart';

Future<void> initTestLocale() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN');
}

class TestControllers {
  TestControllers({
    required this.store,
    required this.session,
    required this.ledger,
    required this.preferences,
    required this.requests,
    required this.api,
  });

  final MemorySessionStore store;
  final SessionController session;
  final LedgerController ledger;
  final PreferencesController preferences;
  final List<http.Request> requests;
  final ApiClient api;
}

Future<http.Response> defaultApi(
  http.Request request, {
  List<Object?>? transactions,
}) async {
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
            {'id': 2, 'category_id': 1, 'name': '晚餐', 'sort_order': 2},
          ],
        },
        {
          'id': 2,
          'name': '交通出行',
          'sort_order': 2,
          'type': 'expense',
          'created_at': '',
          'tags': [
            {'id': 3, 'category_id': 2, 'name': '地铁', 'sort_order': 1},
          ],
        },
        {
          'id': 4,
          'name': '职业收入',
          'sort_order': 4,
          'type': 'income',
          'created_at': '',
          'tags': [
            {'id': 4, 'category_id': 4, 'name': '主业工资', 'sort_order': 1},
          ],
        },
        {
          'id': 8,
          'name': '债务偿还',
          'sort_order': 8,
          'type': 'system',
          'created_at': '',
          'tags': [
            {'id': 8, 'category_id': 8, 'name': '负债还款', 'sort_order': 1},
          ],
        },
        {
          'id': 9,
          'name': '账户转账',
          'sort_order': 9,
          'type': 'system',
          'created_at': '',
          'tags': [
            {'id': 9, 'category_id': 9, 'name': '资金互转', 'sort_order': 1},
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
        {
          'id': 2,
          'name': '支付宝',
          'sort_order': 2,
          'type': 'asset',
          'initial_balance': 0,
          'credit_limit': 0,
          'created_at': '',
        },
        {
          'id': 3,
          'name': '现金',
          'sort_order': 3,
          'type': 'asset',
          'initial_balance': 0,
          'credit_limit': 0,
          'created_at': '',
        },
        {
          'id': 5,
          'name': '招商信用卡',
          'sort_order': 5,
          'type': 'liability',
          'initial_balance': 0,
          'credit_limit': 20000,
          'created_at': '',
        },
      ]);
    case '/api/transactions':
      return jsonResponse(transactions ?? [transactionJson()]);
    case '/api/stats/summary':
      return jsonResponse(statsJson());
    default:
      return jsonResponse({});
  }
}

Future<TestControllers> testControllers({
  MockClient? client,
  String? token,
  String? serverUrl = 'https://ledger.test',
  ThemeMode themeMode = ThemeMode.system,
  bool hideAmounts = false,
}) async {
  final store = MemorySessionStore(serverUrl: serverUrl, token: token);
  final requests = <http.Request>[];
  final api = fakeApi(
    client:
        client ??
        MockClient((request) async {
          requests.add(request);
          return http.Response('{}', 200);
        }),
    baseUrl: () => store.serverUrl ?? '',
    tokenProvider: store.readToken,
  );
  final session = SessionController(store: store, api: api);
  final ledger = LedgerController(api: api, onSessionExpired: session.expire);
  final preferences = PreferencesController(
    MemoryPreferencesStore(themeMode: themeMode, hideAmounts: hideAmounts),
  );
  return TestControllers(
    store: store,
    session: session,
    ledger: ledger,
    preferences: preferences,
    requests: requests,
    api: api,
  );
}

Future<TestControllers> testControllersWithHandler(
  Future<http.Response> Function(http.Request request) handler, {
  String? token,
  String? serverUrl = 'https://ledger.test',
  ThemeMode themeMode = ThemeMode.system,
  bool hideAmounts = false,
}) {
  return testControllers(
    client: MockClient(handler),
    token: token,
    serverUrl: serverUrl,
    themeMode: themeMode,
    hideAmounts: hideAmounts,
  );
}

Future<void> pumpWithProviders(
  WidgetTester tester, {
  required Widget home,
  required TestControllers controllers,
  Size size = const Size(390, 844),
  TextScaler textScaler = TextScaler.noScaling,
  ThemeMode themeMode = ThemeMode.light,
  bool scaffold = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: controllers.session),
        ChangeNotifierProvider.value(value: controllers.ledger),
        ChangeNotifierProvider.value(value: controllers.preferences),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(textScaler: textScaler),
            child: child!,
          );
        },
        home: scaffold ? Scaffold(body: home) : home,
      ),
    ),
  );
}

http.Response jsonResponse(Object? body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object?> transactionJson({
  int id = 1,
  String type = 'expense',
  int amountCents = -2800,
  int feeCents = 0,
  String description = '午餐 · 牛肉面',
  int paymentMethodId = 1,
  String paymentMethodName = '招商银行卡',
  int? sourcePaymentMethodId,
  String sourcePaymentMethodName = '',
  int categoryId = 1,
  String categoryName = '餐饮美食',
  int tagId = 1,
  String tagName = '午餐',
  String transactedAt = '2026-10-19T04:42:00Z',
}) => {
  'id': id,
  'type': type,
  'amount_cents': amountCents,
  'amount': amountCents / 100,
  'fee_cents': feeCents,
  'fee': feeCents / 100,
  'description': description,
  'payment_method_id': paymentMethodId,
  'payment_method_name': paymentMethodName,
  'source_payment_method_id': sourcePaymentMethodId,
  'source_payment_method_name': sourcePaymentMethodName,
  'category_id': categoryId,
  'category_name': categoryName,
  'tag_id': tagId,
  'tag_name': tagName,
  'transacted_at': transactedAt,
  'created_at': transactedAt,
};

Map<String, Object?> statsJson({
  String? month,
  double monthExpense = 3248.5,
  double monthIncome = 12800,
  double monthBalance = 9551.5,
}) => {
  'week_expense': 84.2,
  'month_expense': monthExpense,
  'last_month_expense': 2890,
  'month_income': monthIncome,
  'month_balance': monthBalance,
  'savings_rate': 74.6,
  'category_distribution': [
    {
      'id': 1,
      'name': '餐饮美食',
      'amount': 1400,
      'percentage': 43.1,
      'tags': [
        {'id': 1, 'name': '午餐', 'amount': 800, 'percentage': 57.1},
      ],
    },
  ],
  'payment_distribution': [
    {'id': 1, 'name': '招商银行卡', 'amount': 2000, 'percentage': 61.6},
  ],
  'monthly_trends': [
    for (var i = 5; i >= 0; i--)
      {
        'month': '2026-0${5 - i + 1}',
        'expense': 1000.0 + i * 10,
        'income': 12000,
      },
  ],
  'asset_summary': {
    'total_assets': 86200,
    'total_liabilities': 12680,
    'net_assets': 73520,
    'asset_channels': [
      {
        'id': 1,
        'name': '招商银行',
        'type': 'asset',
        'remaining_balance': 45200,
        'initial_balance': 40000,
        'percentage': 52.3,
      },
      {
        'id': 2,
        'name': '储蓄卡',
        'type': 'asset',
        'remaining_balance': 32800,
        'initial_balance': 30000,
        'percentage': 38.0,
      },
      {
        'id': 3,
        'name': '支付宝',
        'type': 'asset',
        'remaining_balance': 8200,
        'initial_balance': 8200,
        'percentage': 9.7,
      },
    ],
    'liability_channels': [
      {
        'id': 5,
        'name': '招商信用卡',
        'type': 'liability',
        'current_debt': 12680,
        'initial_debt': 0,
        'credit_limit': 20000,
        'remaining_credit': 7320,
        'usage_rate': 63.4,
      },
    ],
  },
};
