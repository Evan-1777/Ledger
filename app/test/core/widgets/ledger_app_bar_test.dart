import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger_app/core/theme/app_theme.dart';
import 'package:ledger_app/core/widgets/ledger_widgets.dart';

void main() {
  testWidgets('compact top bar scrolls away and is 64 high', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: CustomScrollView(
            slivers: [
              LedgerSliverAppBar(title: '测试'),
              SliverToBoxAdapter(child: SizedBox(height: 900)),
            ],
          ),
        ),
      ),
    );

    final bar = tester.widget<SliverAppBar>(find.byType(SliverAppBar));
    expect(bar.toolbarHeight, 64);
    expect(bar.pinned, isFalse);
    expect(bar.floating, isFalse);
    expect(bar.expandedHeight, isNull);
    expect(bar.titleSpacing, 20);
    expect(bar.titleTextStyle?.fontSize, 28);
    expect(bar.titleTextStyle?.fontWeight, FontWeight.w500);
    expect(tester.getTopLeft(find.text('测试')).dy, lessThan(40));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -160));
    await tester.pumpAndSettle();
    final title = find.text('测试');
    expect(title.evaluate().isEmpty || tester.getTopLeft(title).dy < 0, isTrue);
  });
}
