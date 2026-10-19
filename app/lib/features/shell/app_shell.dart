import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/ledger_controller.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../assets/assets_screen.dart';
import '../record/record_sheet.dart';
import '../settings/settings_screen.dart';
import '../stats/stats_screen.dart';
import '../stream/stream_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  SettingsSection _settingsSection = SettingsSection.categories;
  LedgerController? _ledger;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _ledger = context.read<LedgerController>();
    _ledger!.addListener(_onLedgerChanged);
  }

  @override
  void dispose() {
    _ledger?.removeListener(_onLedgerChanged);
    super.dispose();
  }

  void _onLedgerChanged() {
    final ledger = _ledger;
    if (ledger == null || !mounted) return;
    final error =
        ledger.configError ?? ledger.transactionsError ?? ledger.statsError;
    if (error == null) {
      _lastError = null;
      return;
    }
    if (error == _lastError) return;
    _lastError = error;
    final hasCachedData =
        ledger.transactions.isNotEmpty ||
        ledger.stats != null ||
        ledger.categories.isNotEmpty ||
        ledger.channels.isNotEmpty;
    if (!hasCachedData) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showLedgerSnackBar(context, error, isError: true);
    });
  }

  void _selectTab(int index) {
    if (index == _index) {
      if (index == 3) {
        setState(() => _settingsSection = SettingsSection.categories);
      }
      return;
    }
    setState(() {
      _index = index;
      if (index == 3) {
        _settingsSection = SettingsSection.categories;
      }
    });
  }

  void _openChannelSettings() {
    setState(() {
      _index = 3;
      _settingsSection = SettingsSection.channels;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _index != 0) {
          setState(() => _index = 0);
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            StreamScreen(onOpenSettings: _openChannelSettings),
            const StatsScreen(),
            AssetsScreen(onManage: _openChannelSettings),
            SettingsScreen(
              section: _settingsSection,
              onSectionChanged: (section) =>
                  setState(() => _settingsSection = section),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () =>
              RecordSheet.show(context, onOpenSettings: _openChannelSettings),
          icon: const Icon(Icons.add_rounded),
          label: const Text('记一笔'),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _selectTab,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long_rounded),
              label: '流水',
            ),
            NavigationDestination(
              icon: Icon(Icons.insert_chart_outlined),
              selectedIcon: Icon(Icons.insert_chart_rounded),
              label: '统计',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet_rounded),
              label: '资产',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: '设置',
            ),
          ],
        ),
      ),
    );
  }
}
