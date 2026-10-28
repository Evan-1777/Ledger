import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'models.dart';

String normalizeServerUrl(String raw) {
  final value = raw.trim();
  if (value.isEmpty || value.contains(RegExp(r'\s'))) {
    throw ApiException.invalidServer;
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.userInfo.isNotEmpty) {
    throw ApiException.invalidServer;
  }
  if (uri.path.isNotEmpty && uri.path != '/') {
    throw ApiException.invalidServer;
  }
  if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) {
    throw ApiException.invalidServer;
  }
  final normalized = Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
  );
  return normalized.toString();
}

class LoginResult {
  const LoginResult({required this.token});

  final String token;
}

class ApiClient {
  ApiClient({
    required http.Client client,
    required String Function() baseUrl,
    required Future<String?> Function() tokenProvider,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client, // ignore: prefer_initializing_formals
       _baseUrl = baseUrl, // ignore: prefer_initializing_formals
       _tokenProvider = tokenProvider; // ignore: prefer_initializing_formals

  final http.Client _client;
  final String Function() _baseUrl;
  final Future<String?> Function() _tokenProvider;
  final Duration timeout;

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final base = _baseUrl();
    if (base.isEmpty) throw ApiException.invalidServer;

    final uri = Uri.parse(base).replace(path: path, queryParameters: query);
    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = await _tokenProvider();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    try {
      final request = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) request.body = jsonEncode(body);
      final streamed = await _client.send(request).timeout(timeout);
      return await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw ApiException.timeout;
    } on http.ClientException {
      throw ApiException.network;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException.network;
    }
  }

  Future<Object?> _json(http.Response response) async {
    if (response.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw ApiException.invalidResponse;
    }
  }

  Never _throwFor(http.Response response, Object? decoded) {
    String? serverMessage;
    if (decoded is Map<String, dynamic> && decoded['error'] is String) {
      serverMessage = decoded['error'] as String;
    }
    throw ApiException.fromStatus(response.statusCode, serverMessage);
  }

  Future<Object?> _expectOk(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    final response = await _send(method, path, body: body, query: query);
    final decoded = await _json(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwFor(response, decoded);
    }
    return decoded;
  }

  Future<LoginResult> login(String password) async {
    final decoded = await _expectOk(
      'POST',
      '/api/auth/login',
      body: {'password': password},
    );
    if (decoded is! Map<String, dynamic> || decoded['token'] is! String) {
      throw ApiException.invalidResponse;
    }
    return LoginResult(token: decoded['token'] as String);
  }

  Future<void> checkAuth() async {
    await _expectOk('GET', '/api/auth/check');
  }

  Future<List<PaymentMethod>> getPaymentMethods() async {
    final decoded = await _expectOk('GET', '/api/payment-methods');
    return _list(decoded, PaymentMethod.fromJson);
  }

  Future<PaymentMethod> createPaymentMethod({
    required String name,
    required int sortOrder,
    required ChannelType type,
    required double initialBalance,
    required double creditLimit,
  }) async {
    final decoded = await _expectOk(
      'POST',
      '/api/payment-methods',
      body: {
        'name': name,
        'sort_order': sortOrder,
        'type': type.api,
        'initial_balance': initialBalance,
        'credit_limit': creditLimit,
      },
    );
    return _one(decoded, PaymentMethod.fromJson);
  }

  Future<PaymentMethod> updatePaymentMethod(
    int id, {
    required String name,
    required int sortOrder,
    required ChannelType type,
    required double initialBalance,
    required double creditLimit,
  }) async {
    final decoded = await _expectOk(
      'PUT',
      '/api/payment-methods/$id',
      body: {
        'name': name,
        'sort_order': sortOrder,
        'type': type.api,
        'initial_balance': initialBalance,
        'credit_limit': creditLimit,
      },
    );
    return _one(decoded, PaymentMethod.fromJson);
  }

  Future<void> deletePaymentMethod(int id) async {
    await _expectOk('DELETE', '/api/payment-methods/$id');
  }

  Future<List<Category>> getCategories() async {
    final decoded = await _expectOk('GET', '/api/categories');
    return _list(decoded, Category.fromJson);
  }

  Future<Category> createCategory({
    required String name,
    required int sortOrder,
    required CategoryType type,
  }) async {
    final decoded = await _expectOk(
      'POST',
      '/api/categories',
      body: {'name': name, 'sort_order': sortOrder, 'type': type.api},
    );
    return _one(decoded, Category.fromJson);
  }

  Future<Category> updateCategory(
    int id, {
    required String name,
    required int sortOrder,
    required CategoryType type,
    bool? excludeFromStats,
  }) async {
    final decoded = await _expectOk(
      'PUT',
      '/api/categories/$id',
      body: {
        'name': name,
        'sort_order': sortOrder,
        'type': type.api,
        'exclude_from_stats': ?excludeFromStats,
      },
    );
    return _one(decoded, Category.fromJson);
  }

  Future<void> deleteCategory(int id) async {
    await _expectOk('DELETE', '/api/categories/$id');
  }

  Future<List<Tag>> getTags({int? categoryId}) async {
    final decoded = await _expectOk(
      'GET',
      '/api/tags',
      query: categoryId == null ? null : {'category_id': '$categoryId'},
    );
    return _list(decoded, Tag.fromJson);
  }

  Future<Tag> createTag({
    required int categoryId,
    required String name,
    required int sortOrder,
  }) async {
    final decoded = await _expectOk(
      'POST',
      '/api/tags',
      body: {'category_id': categoryId, 'name': name, 'sort_order': sortOrder},
    );
    return _one(decoded, Tag.fromJson);
  }

  Future<Tag> updateTag(
    int id, {
    required String name,
    required int sortOrder,
  }) async {
    final decoded = await _expectOk(
      'PUT',
      '/api/tags/$id',
      body: {'name': name, 'sort_order': sortOrder},
    );
    return _one(decoded, Tag.fromJson);
  }

  Future<void> deleteTag(int id) async {
    await _expectOk('DELETE', '/api/tags/$id');
  }

  Future<List<Transaction>> getTransactions({
    TransactionType? type,
    int limit = 100,
  }) async {
    final decoded = await _expectOk(
      'GET',
      '/api/transactions',
      query: {'limit': '$limit', if (type != null) 'type': type.api},
    );
    return _list(decoded, Transaction.fromJson);
  }

  Future<Transaction> createTransaction(TransactionInput input) async {
    final decoded = await _expectOk(
      'POST',
      '/api/transactions',
      body: input.toJson(),
    );
    return _one(decoded, Transaction.fromJson);
  }

  Future<Transaction> updateTransaction(int id, TransactionInput input) async {
    final decoded = await _expectOk(
      'PUT',
      '/api/transactions/$id',
      body: input.toJson(),
    );
    return _one(decoded, Transaction.fromJson);
  }

  Future<void> deleteTransaction(int id) async {
    await _expectOk('DELETE', '/api/transactions/$id');
  }

  Future<StatsSummary> getStatsSummary() async {
    final decoded = await _expectOk('GET', '/api/stats/summary');
    return _one(decoded, StatsSummary.fromJson);
  }

  List<T> _list<T>(Object? decoded, T Function(Map<String, dynamic>) parse) {
    if (decoded is! List) throw ApiException.invalidResponse;
    try {
      return decoded
          .map((item) => parse(item as Map<String, dynamic>))
          .toList();
    } on TypeError {
      throw ApiException.invalidResponse;
    }
  }

  T _one<T>(Object? decoded, T Function(Map<String, dynamic>) parse) {
    if (decoded is! Map<String, dynamic>) throw ApiException.invalidResponse;
    try {
      return parse(decoded);
    } on TypeError {
      throw ApiException.invalidResponse;
    }
  }
}
