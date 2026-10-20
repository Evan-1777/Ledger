import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/core/theme/app_theme.dart';
import 'package:ledger_app/core/widgets/ledger_widgets.dart';

const _belowBarKey = ValueKey('below-bar');

Widget _harness({double textScale = 1}) => MaterialApp(
  theme: AppTheme.light(),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: const Scaffold(
      body: CustomScrollView(
        slivers: [
          LedgerSliverAppBar(title: '测试'),
          SliverToBoxAdapter(child: SizedBox(key: _belowBarKey, height: 900)),
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets('compact top bar is 64 high and scrolls away', (tester) async {
    await tester.pumpWidget(_harness());

    final bar = tester.getRect(find.byType(AppBar));
    expect(bar.top, 0);
    expect(bar.height, 64);
    expect(tester.getTopLeft(find.byKey(_belowBarKey)).dy, 64);

    final title = tester.getRect(find.text('测试'));
    expect(title.left, 20);
    expect(title.center.dy, closeTo(bar.center.dy, 0.5));
    expect(
      DefaultTextStyle.of(tester.element(find.text('测试'))).style.fontSize,
      28,
    );

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -160));
    await tester.pumpAndSettle();
    final scrolled = find.text('测试');
    expect(
      scrolled.evaluate().isEmpty || tester.getTopLeft(scrolled).dy < 0,
      isTrue,
    );
    expect(tester.getTopLeft(find.byKey(_belowBarKey)).dy, lessThan(64));
  });

  testWidgets('title stays inside the bar at 2x text', (tester) async {
    await tester.pumpWidget(_harness(textScale: 2));

    final bar = tester.getRect(find.byType(AppBar));
    final title = tester.getRect(find.text('测试'));
    expect(title.top, greaterThanOrEqualTo(bar.top));
    expect(title.bottom, lessThanOrEqualTo(bar.bottom));
    expect(title.height, greaterThan(36));
    expect(tester.takeException(), isNull);
  });
}
