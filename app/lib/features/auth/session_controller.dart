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
  String? startupError;
  String? loginError;

  String? get serverUrl => _store.serverUrl;
  bool get isAuthenticated => phase == SessionPhase.authenticated;

  Future<void> restore() async {
    phase = SessionPhase.booting;
    startupError = null;
    loginError = null;
    notifyListeners();

    final url = _store.serverUrl;
    final token = await _store.readToken();
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      phase = SessionPhase.locked;
      notifyListeners();
      return;
    }

    try {
      await _api.checkAuth();
      phase = SessionPhase.authenticated;
      notifyListeners();
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await _store.clearToken();
        phase = SessionPhase.locked;
      } else {
        startupError = error.message;
        phase = SessionPhase.booting;
      }
      notifyListeners();
    }
  }

  Future<bool> login(String rawUrl, String password) async {
    if (busy) return false;
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
    await _store.clearToken();
    phase = SessionPhase.locked;
    loginError = null;
    notifyListeners();
  }

  Future<void> expire() async {
    await _store.clearToken();
    phase = SessionPhase.locked;
    loginError = null;
    notifyListeners();
  }

  Future<bool> updateServer(String rawUrl) async {
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
