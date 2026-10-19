import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class SessionStore {
  String? get serverUrl;
  Future<void> setServerUrl(String? url);
  Future<String?> readToken();
  Future<void> writeToken(String token);
  Future<void> clearToken();
}

class SecureSessionStore implements SessionStore {
  SecureSessionStore({required this.secure, required this.preferences});

  static const _tokenKey = 'ledger_token';
  static const _serverKey = 'ledger_server_url';

  final FlutterSecureStorage secure;
  final SharedPreferences preferences;
  String? _serverUrl;

  @override
  String? get serverUrl => _serverUrl ?? preferences.getString(_serverKey);

  @override
  Future<void> setServerUrl(String? url) async {
    _serverUrl = url;
    if (url == null) {
      await preferences.remove(_serverKey);
    } else {
      await preferences.setString(_serverKey, url);
    }
  }

  @override
  Future<String?> readToken() async {
    try {
      return await secure.read(key: _tokenKey);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeToken(String token) =>
      secure.write(key: _tokenKey, value: token);

  @override
  Future<void> clearToken() async {
    try {
      await secure.delete(key: _tokenKey);
    } catch (_) {
      // A locked/unavailable keystore must not block returning to the lock screen.
    }
  }
}
