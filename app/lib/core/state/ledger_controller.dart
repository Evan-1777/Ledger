import 'package:flutter/foundation.dart' hide Category;

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../api/models.dart';

enum TransactionFilter {
  all,
  expense,
  income,
  transfer,
  repayment;

  TransactionType? get type => switch (this) {
    TransactionFilter.all => null,
    TransactionFilter.expense => TransactionType.expense,
    TransactionFilter.income => TransactionType.income,
    TransactionFilter.transfer => TransactionType.transfer,
    TransactionFilter.repayment => TransactionType.repayment,
  };

  String get label => switch (this) {
    TransactionFilter.all => '全部',
    TransactionFilter.expense => '支出',
    TransactionFilter.income => '收入',
    TransactionFilter.transfer => '转账',
    TransactionFilter.repayment => '还款',
  };
}

class LedgerController extends ChangeNotifier {
  LedgerController({
    required ApiClient api,
    required Future<void> Function() onSessionExpired,
  }) : _api = api, // ignore: prefer_initializing_formals
       // ignore: prefer_initializing_formals
       _onSessionExpired = onSessionExpired;

  final ApiClient _api;
  final Future<void> Function() _onSessionExpired;

  List<Category> categories = [];
  List<PaymentMethod> channels = [];
  List<Transaction> transactions = [];
  StatsSummary? stats;
  TransactionFilter filter = TransactionFilter.all;

  bool configLoading = false;
  bool transactionsLoading = false;
  bool statsLoading = false;
  String? configError;
  String? transactionsError;
  String? statsError;

  int _transactionsGeneration = 0;
  int _statsGeneration = 0;
  bool _expiring = false;
  final Set<int> _deletingTransactions = {};

  List<PaymentMethod> get assetChannels =>
      channels.where((item) => item.type == ChannelType.asset).toList();

  List<PaymentMethod> get liabilityChannels =>
      channels.where((item) => item.type == ChannelType.liability).toList();

  List<Category> categoriesOfType(CategoryType type) =>
      categories.where((item) => item.type == type).toList();

  Category? categoryByName(String name) {
    for (final category in categories) {
      if (category.name == name) return category;
    }
    return null;
  }

  Future<void> loadAll() async {
    await Future.wait([loadConfig(), loadTransactions(), loadStats()]);
  }

  Future<void> refreshAll() async {
    await Future.wait([loadConfig(), loadTransactions(), loadStats()]);
  }

  Future<void> loadConfig() async {
    if (configLoading) return;
    configLoading = true;
    configError = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _api.getCategories(),
        _api.getPaymentMethods(),
      ]);
      categories = results[0] as List<Category>;
      channels = results[1] as List<PaymentMethod>;
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await _expire();
        return;
      }
      configError = error.message;
    } catch (_) {
      configError = '加载分类与渠道失败';
    } finally {
      configLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadTransactions() async {
    final generation = ++_transactionsGeneration;
    transactionsLoading = true;
    transactionsError = null;
    notifyListeners();
    try {
      final list = await _api.getTransactions(type: filter.type);
      if (generation != _transactionsGeneration) return;
      transactions = list;
    } on ApiException catch (error) {
      if (generation != _transactionsGeneration) return;
      if (error.isUnauthorized) {
        await _expire();
        return;
      }
      transactionsError = error.message;
    } catch (_) {
      if (generation != _transactionsGeneration) return;
      transactionsError = '加载流水失败';
    } finally {
      if (generation == _transactionsGeneration) {
        transactionsLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadStats() async {
    final generation = ++_statsGeneration;
    statsLoading = true;
    statsError = null;
    notifyListeners();
    try {
      final summary = await _api.getStatsSummary();
      if (generation != _statsGeneration) return;
      stats = summary;
    } on ApiException catch (error) {
      if (generation != _statsGeneration) return;
      if (error.isUnauthorized) {
        await _expire();
        return;
      }
      statsError = error.message;
    } catch (_) {
      if (generation != _statsGeneration) return;
      statsError = '加载统计失败';
    } finally {
      if (generation == _statsGeneration) {
        statsLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> setFilter(TransactionFilter next) async {
    if (filter == next) return;
    filter = next;
    notifyListeners();
    await loadTransactions();
  }

  Future<Transaction> createTransaction(TransactionInput input) async {
    final created = await _guard(() => _api.createTransaction(input));
    await refreshAfterTransactionChange();
    return created;
  }

  Future<Transaction> updateTransaction(int id, TransactionInput input) async {
    final updated = await _guard(() => _api.updateTransaction(id, input));
    await refreshAfterTransactionChange();
    return updated;
  }

  bool isDeletingTransaction(int id) => _deletingTransactions.contains(id);

  Future<void> deleteTransaction(int id) async {
    if (!_deletingTransactions.add(id)) return;
    try {
      await _guard(() => _api.deleteTransaction(id));
      await refreshAfterTransactionChange();
    } finally {
      _deletingTransactions.remove(id);
    }
  }

  Future<void> refreshAfterTransactionChange() async {
    await Future.wait([loadTransactions(), loadStats()]);
  }

  Future<Category> createCategory(String name, CategoryType type) async {
    final siblings = categoriesOfType(type);
    final sortOrder = _nextSortOrder(siblings.map((item) => item.sortOrder));
    final created = await _guard(
      () => _api.createCategory(name: name, sortOrder: sortOrder, type: type),
    );
    await loadConfig();
    return created;
  }

  Future<void> updateCategory(
    Category category, {
    required String name,
    required int sortOrder,
    required CategoryType type,
  }) async {
    await _guard(
      () => _api.updateCategory(
        category.id,
        name: name,
        sortOrder: sortOrder,
        type: type,
      ),
    );
    await loadConfig();
  }

  Future<void> moveCategory(Category category, int direction) async {
    final siblings = categoriesOfType(category.type);
    final index = siblings.indexWhere((item) => item.id == category.id);
    final targetIndex = index + direction;
    if (index < 0 || targetIndex < 0 || targetIndex >= siblings.length) return;
    final other = siblings[targetIndex];
    try {
      await _guard(() async {
        await _api.updateCategory(
          category.id,
          name: category.name,
          sortOrder: other.sortOrder,
          type: category.type,
        );
        await _api.updateCategory(
          other.id,
          name: other.name,
          sortOrder: category.sortOrder,
          type: other.type,
        );
      });
    } finally {
      await loadConfig();
    }
  }

  Future<void> deleteCategory(Category category) async {
    await _guard(() => _api.deleteCategory(category.id));
    await loadConfig();
  }

  Future<Tag> createTag(Category category, String name) async {
    final sortOrder = _nextSortOrder(
      category.tags.map((item) => item.sortOrder),
    );
    final created = await _guard(
      () => _api.createTag(
        categoryId: category.id,
        name: name,
        sortOrder: sortOrder,
      ),
    );
    await loadConfig();
    return created;
  }

  Future<void> updateTag(Tag tag, String name) async {
    await _guard(
      () => _api.updateTag(tag.id, name: name, sortOrder: tag.sortOrder),
    );
    await loadConfig();
  }

  Future<void> deleteTag(Tag tag) async {
    await _guard(() => _api.deleteTag(tag.id));
    await loadConfig();
  }

  Future<PaymentMethod> createChannel({
    required String name,
    required ChannelType type,
    required double initialBalance,
    required double creditLimit,
  }) async {
    final sortOrder = _nextSortOrder(
      channels.where((item) => item.type == type).map((item) => item.sortOrder),
    );
    final created = await _guard(
      () => _api.createPaymentMethod(
        name: name,
        sortOrder: sortOrder,
        type: type,
        initialBalance: initialBalance,
        creditLimit: creditLimit,
      ),
    );
    await refreshAfterChannelChange();
    return created;
  }

  Future<void> updateChannel(
    PaymentMethod channel, {
    required String name,
    required ChannelType type,
    required double initialBalance,
    required double creditLimit,
  }) async {
    await _guard(
      () => _api.updatePaymentMethod(
        channel.id,
        name: name,
        sortOrder: channel.sortOrder,
        type: type,
        initialBalance: initialBalance,
        creditLimit: creditLimit,
      ),
    );
    await refreshAfterChannelChange();
  }

  Future<void> deleteChannel(PaymentMethod channel) async {
    await _guard(() => _api.deletePaymentMethod(channel.id));
    await refreshAfterChannelChange();
  }

  Future<void> refreshAfterChannelChange() async {
    await Future.wait([loadConfig(), loadStats()]);
  }

  void clear() {
    _transactionsGeneration++;
    _statsGeneration++;
    categories = [];
    channels = [];
    transactions = [];
    stats = null;
    filter = TransactionFilter.all;
    configLoading = false;
    transactionsLoading = false;
    statsLoading = false;
    configError = null;
    transactionsError = null;
    statsError = null;
    notifyListeners();
  }

  Future<void> _expire() async {
    if (_expiring) return;
    _expiring = true;
    try {
      await _onSessionExpired();
      clear();
    } finally {
      _expiring = false;
    }
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await _expire();
      }
      rethrow;
    }
  }

  int _nextSortOrder(Iterable<int> existing) {
    var max = 0;
    for (final value in existing) {
      if (value > max) max = value;
    }
    return max + 1;
  }
}
