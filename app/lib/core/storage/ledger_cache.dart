import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/models.dart';

class CachedLedgerConfig {
  const CachedLedgerConfig({required this.categories, required this.channels});

  final List<Category> categories;
  final List<PaymentMethod> channels;
}

/// 冷启动只读快照：按域把上一次成功同步的数据存成 JSON，供首帧直接渲染。
///
/// 单键容量以 100 条流水窗口为界；数据量显著增长时应迁移到 SQLite 或文件。
abstract class LedgerCache {
  CachedLedgerConfig? readConfig();
  Future<void> writeConfig(CachedLedgerConfig config);
  List<Transaction>? readTransactions();
  Future<void> writeTransactions(List<Transaction> transactions);
  StatsSummary? readStats();
  Future<void> writeStats(StatsSummary stats);
}

class SharedPreferencesLedgerCache implements LedgerCache {
  SharedPreferencesLedgerCache({
    required SharedPreferences preferences,
    required String? Function() serverUrl,
  }) : _preferences = preferences, // ignore: prefer_initializing_formals
       _serverUrl = serverUrl; // ignore: prefer_initializing_formals

  static const _configKey = 'ledger_cache_config';
  static const _transactionsKey = 'ledger_cache_transactions';
  static const _statsKey = 'ledger_cache_stats';
  static const _version = 1;

  final SharedPreferences _preferences;
  final String? Function() _serverUrl;

  @override
  CachedLedgerConfig? readConfig() {
    final data = _read(_configKey);
    if (data is! Map<String, dynamic>) return null;
    return _parse(
      () => CachedLedgerConfig(
        categories: _decodeList(data['categories'], Category.fromJson),
        channels: _decodeList(data['channels'], PaymentMethod.fromJson),
      ),
    );
  }

  @override
  Future<void> writeConfig(CachedLedgerConfig config) => _write(_configKey, {
    'categories': [for (final category in config.categories) category.toJson()],
    'channels': [for (final channel in config.channels) channel.toJson()],
  });

  @override
  List<Transaction>? readTransactions() {
    final data = _read(_transactionsKey);
    if (data is! List) return null;
    return _parse(() => _decodeList(data, Transaction.fromJson));
  }

  @override
  Future<void> writeTransactions(List<Transaction> transactions) => _write(
    _transactionsKey,
    [for (final transaction in transactions) transaction.toJson()],
  );

  @override
  StatsSummary? readStats() {
    final data = _read(_statsKey);
    if (data is! Map<String, dynamic>) return null;
    return _parse(() => StatsSummary.fromJson(data));
  }

  @override
  Future<void> writeStats(StatsSummary stats) =>
      _write(_statsKey, stats.toJson());

  Object? _read(String key) {
    final server = _serverUrl();
    if (server == null || server.isEmpty) return null;
    final raw = _preferences.getString(key);
    if (raw == null) return null;
    try {
      final envelope = jsonDecode(raw);
      if (envelope is! Map<String, dynamic>) return null;
      if (envelope['version'] != _version || envelope['server'] != server) {
        return null;
      }
      return envelope['data'];
    } on FormatException {
      return null;
    }
  }

  Future<void> _write(String key, Object? data) async {
    final server = _serverUrl();
    if (server == null || server.isEmpty) return;
    try {
      await _preferences.setString(
        key,
        jsonEncode({'version': _version, 'server': server, 'data': data}),
      );
    } catch (_) {
      // 快照是尽力而为：写入失败不影响本次加载结果。
    }
  }

  List<T> _decodeList<T>(
    Object? value,
    T Function(Map<String, dynamic>) parse,
  ) => [for (final item in value as List) parse(item as Map<String, dynamic>)];

  T? _parse<T>(T Function() build) {
    try {
      return build();
    } catch (_) {
      return null;
    }
  }
}
