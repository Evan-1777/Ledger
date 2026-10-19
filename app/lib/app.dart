import 'dart:async';

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
    this.autoRestore = true,
  });

  final SessionController session;
  final LedgerController ledger;
  final PreferencesController preferences;
  final bool autoRestore;

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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.ledger.loadAll();
      });
    }
    if (widget.autoRestore && widget.session.phase == SessionPhase.booting) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.session.restore();
      });
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
      SessionPhase.booting => _SplashScreen(
        error: session.startupError,
        onRetry: session.restore,
      ),
      SessionPhase.locked => const LoginScreen(),
      SessionPhase.authenticated => const AppShell(),
    };
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen({this.error, this.onRetry});

  final String? error;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Icon(
                    Icons.menu_book_rounded,
                    size: 38,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Ledger',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 24),
                if (error == null)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                else ...[
                  Text(
                    error!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(onPressed: onRetry, child: const Text('重试')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
