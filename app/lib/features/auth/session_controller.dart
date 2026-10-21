import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/storage/session_store.dart';

enum SessionPhase { booting, locked, authenticated }

class SessionController extends ChangeNotifier {
  SessionController({required SessionStore store, required ApiClient api})
    : _store = store, // ignore: prefer_initializing_formals
      _api = api; // ignore: prefer_initializing_formals

  final SessionStore _store;
  final ApiClient _api;

  SessionPhase phase = SessionPhase.booting;
  bool busy = false;
  String? loginError;

  int _generation = 0;

  String? get serverUrl => _store.serverUrl;
  bool get isAuthenticated => phase == SessionPhase.authenticated;

  Future<void> restore() async {
    final generation = ++_generation;
    phase = SessionPhase.booting;
    loginError = null;
    notifyListeners();

    final url = _store.serverUrl;
    final token = await _store.readToken();
    if (generation != _generation) return;
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      phase = SessionPhase.locked;
      notifyListeners();
      return;
    }

    // 本地有凭证即可先行进入：网络只用于后台纠正，不再阻塞首帧。
    phase = SessionPhase.authenticated;
    notifyListeners();
    unawaited(_verifySession(generation));
  }

  Future<void> _verifySession(int generation) async {
    try {
      await _api.checkAuth();
    } on ApiException catch (error) {
      if (generation != _generation || !error.isUnauthorized) return;
      await expire();
    }
  }

  Future<bool> login(String rawUrl, String password) async {
    if (busy) return false;
    _generation++;
    busy = true;
    loginError = null;
    notifyListeners();

    try {
      final url = normalizeServerUrl(rawUrl);
      if (kReleaseMode && !url.startsWith('https://')) {
        loginError = '正式版仅支持 HTTPS';
        return false;
      }
      await _store.setServerUrl(url);
      final result = await _api.login(password);
      await _store.writeToken(result.token);
      phase = SessionPhase.authenticated;
      return true;
    } on ApiException catch (error) {
      loginError = error.isUnauthorized ? '密码错误' : error.message;
      return false;
    } catch (_) {
      loginError = '无法保存登录凭证，请通过 HTTPS 或 localhost 访问';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _generation++;
    await _store.clearToken();
    phase = SessionPhase.locked;
    loginError = null;
    notifyListeners();
  }

  Future<void> expire() async {
    _generation++;
    await _store.clearToken();
    phase = SessionPhase.locked;
    loginError = null;
    notifyListeners();
  }

  Future<bool> updateServer(String rawUrl) async {
    _generation++;
    try {
      final url = normalizeServerUrl(rawUrl);
      if (kReleaseMode && !url.startsWith('https://')) {
        return false;
      }
      await _store.setServerUrl(url);
      await _store.clearToken();
      phase = SessionPhase.locked;
      loginError = null;
      notifyListeners();
      return true;
    } on ApiException {
      return false;
    }
  }
}
