import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/api/api_client.dart';
import 'core/state/ledger_controller.dart';
import 'core/state/preferences_controller.dart';
import 'core/storage/ledger_cache.dart';
import 'core/storage/preferences_store.dart';
import 'core/storage/session_store.dart';
import 'features/auth/session_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN');
  if (!kIsWeb) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  final preferences = await SharedPreferences.getInstance();
  final sessionStore = SecureSessionStore(
    secure: const FlutterSecureStorage(),
    preferences: preferences,
  );
  final cache = SharedPreferencesLedgerCache(
    preferences: preferences,
    serverUrl: () => sessionStore.serverUrl,
  );
  final api = ApiClient(
    client: http.Client(),
    baseUrl: () => sessionStore.serverUrl ?? '',
    tokenProvider: sessionStore.readToken,
  );
  final session = SessionController(store: sessionStore, api: api);
  final ledger = LedgerController(
    api: api,
    onSessionExpired: session.expire,
    cache: cache,
  );
  final preferencesController = PreferencesController(
    SharedPreferencesStore(preferences),
  );

  await session.restore();

  runApp(
    LedgerApp(
      session: session,
      ledger: ledger,
      preferences: preferencesController,
    ),
  );
}
