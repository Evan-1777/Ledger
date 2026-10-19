import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ledger_app/core/api/api_client.dart';
import 'package:ledger_app/core/api/models.dart';
import 'package:ledger_app/core/storage/preferences_store.dart';
import 'package:ledger_app/core/storage/session_store.dart';
import 'package:flutter/material.dart';

class MemorySessionStore implements SessionStore {
  MemorySessionStore({String? serverUrl, String? token})
    : _serverUrl = serverUrl, // ignore: prefer_initializing_formals
      _token = token; // ignore: prefer_initializing_formals

  String? _serverUrl;
  String? _token;

  @override
  String? get serverUrl => _serverUrl;

  @override
  Future<void> setServerUrl(String? url) async => _serverUrl = url;

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> writeToken(String token) async => _token = token;

  @override
  Future<void> clearToken() async => _token = null;
}

class MemoryPreferencesStore implements PreferencesStore {
  MemoryPreferencesStore({
    this.themeMode = ThemeMode.system,
    this.hideAmounts = false,
  });

  ThemeMode themeMode;
  bool hideAmounts;

  @override
  ThemeMode readThemeMode() => themeMode;

  @override
  Future<void> writeThemeMode(ThemeMode mode) async => themeMode = mode;

  @override
  bool readHideAmounts() => hideAmounts;

  @override
  Future<void> writeHideAmounts(bool value) async => hideAmounts = value;
}

ApiClient fakeApi({
  required MockClient client,
  String Function()? baseUrl,
  Future<String?> Function()? tokenProvider,
}) {
  return ApiClient(
    client: client,
    baseUrl: baseUrl ?? () => 'https://ledger.test',
    tokenProvider: tokenProvider ?? () async => 'token',
  );
}

MockClient jsonClient(
  Map<String, Object?> Function(http.Request request) handler,
) {
  return MockClient((request) async {
    final body = handler(request);
    return http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

PaymentMethod paymentMethod({
  int id = 1,
  String name = '招商银行卡',
  ChannelType type = ChannelType.asset,
  double initialBalance = 0,
  double creditLimit = 0,
  int sortOrder = 1,
}) => PaymentMethod(
  id: id,
  name: name,
  sortOrder: sortOrder,
  type: type,
  initialBalance: initialBalance,
  creditLimit: creditLimit,
);

Category category({
  int id = 1,
  String name = '餐饮美食',
  CategoryType type = CategoryType.expense,
  int sortOrder = 1,
  List<Tag>? tags,
}) => Category(
  id: id,
  name: name,
  sortOrder: sortOrder,
  type: type,
  tags: tags ?? const [Tag(id: 1, categoryId: 1, name: '午餐', sortOrder: 1)],
);

Transaction transactionModel({
  int id = 1,
  TransactionType type = TransactionType.expense,
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
  DateTime? transactedAt,
}) => Transaction(
  id: id,
  type: type,
  amountCents: amountCents,
  feeCents: feeCents,
  description: description,
  paymentMethodId: paymentMethodId,
  paymentMethodName: paymentMethodName,
  sourcePaymentMethodId: sourcePaymentMethodId,
  sourcePaymentMethodName: sourcePaymentMethodName,
  categoryId: categoryId,
  categoryName: categoryName,
  tagId: tagId,
  tagName: tagName,
  transactedAt: (transactedAt ?? DateTime(2026, 10, 19, 8, 42)).toUtc(),
);

StatsSummary emptyStats() => const StatsSummary(
  weekExpense: 0,
  monthExpense: 0,
  lastMonthExpense: 0,
  monthIncome: 0,
  monthBalance: 0,
  savingsRate: 0,
  categoryDistribution: [],
  paymentDistribution: [],
  monthlyTrends: [],
  assetSummary: AssetSummary(
    totalAssets: 0,
    totalLiabilities: 0,
    netAssets: 0,
    assetChannels: [],
    liabilityChannels: [],
  ),
);
