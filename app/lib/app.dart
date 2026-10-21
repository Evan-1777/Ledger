import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/state/ledger_controller.dart';
import 'core/state/preferences_controller.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/session_controller.dart';
import 'features/shell/app_shell.dart';

class LedgerApp extends StatefulWidget {
  const LedgerApp({
    super.key,
    required this.session,
    required this.ledger,
    required this.preferences,
  });

  final SessionController session;
  final LedgerController ledger;
  final PreferencesController preferences;

  @override
  State<LedgerApp> createState() => _LedgerAppState();
}

class _LedgerAppState extends State<LedgerApp> {
  bool _wasAuthenticated = false;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSessionChanged);
    _wasAuthenticated = widget.session.isAuthenticated;
    if (_wasAuthenticated) {
      // 首帧构建前同步水合与置位 loading：有快照直接出内容，没有则保持骨架。
      widget.ledger.hydrateFromCache();
      widget.ledger.loadAll();
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    final authenticated = widget.session.isAuthenticated;
    if (authenticated && !_wasAuthenticated) {
      _wasAuthenticated = true;
      widget.ledger.hydrateFromCache();
      widget.ledger.loadAll();
    } else if (!authenticated && _wasAuthenticated) {
      _wasAuthenticated = false;
      widget.ledger.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.session),
        ChangeNotifierProvider.value(value: widget.ledger),
        ChangeNotifierProvider.value(value: widget.preferences),
      ],
      child: Consumer<PreferencesController>(
        builder: (context, preferences, _) => MaterialApp(
          title: 'Ledger',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: preferences.themeMode,
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) {
            final brightness = Theme.of(context).brightness;
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: brightness == Brightness.light
                    ? Brightness.dark
                    : Brightness.light,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarIconBrightness:
                    brightness == Brightness.light
                    ? Brightness.dark
                    : Brightness.light,
                systemNavigationBarContrastEnforced: false,
              ),
              child: child!,
            );
          },
          home: const _SessionGate(),
        ),
      ),
    );
  }
}

class _SessionGate extends StatelessWidget {
  const _SessionGate();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    return switch (session.phase) {
      SessionPhase.booting => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      SessionPhase.locked => const LoginScreen(),
      SessionPhase.authenticated => const AppShell(),
    };
  }
}
