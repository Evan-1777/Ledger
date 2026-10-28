import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../core/api/models.dart';
import '../../core/format/money.dart';

class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.categories,
    required this.total,
    required this.colors,
    required this.centerLabel,
    required this.semanticsLabel,
    this.size = 168,
  });

  final List<CategoryStat> categories;
  final double total;
  final List<Color> colors;
  final String centerLabel;
  final String semanticsLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '$semanticsLabel，共 ${formatMoney(total)}，${categories.length} 个分类',
      child: ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _DonutPainter(
              categories: categories,
              total: total,
              colors: colors,
              background: scheme.surfaceContainerHighest,
            ),
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(size * 0.18),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatMoney(total, withCurrency: false),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                      ),
                      Text(
                        centerLabel,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.categories,
    required this.total,
    required this.colors,
    required this.background,
  });

  final List<CategoryStat> categories;
  final double total;
  final List<Color> colors;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.17;
    final rect = Offset.zero & size;
    final ringRect = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = background;
    canvas.drawArc(ringRect, 0, math.pi * 2, false, base);

    if (total <= 0) return;
    var start = -math.pi / 2;
    for (var i = 0; i < categories.length; i++) {
      final amount = categories[i].amount;
      if (amount <= 0) continue;
      final sweep = amount / total * math.pi * 2;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt
        ..color = colors[i % colors.length];
      canvas.drawArc(ringRect, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.categories != categories ||
      oldDelegate.total != total ||
      oldDelegate.colors != colors ||
      oldDelegate.background != background;
}

class TrendChart extends StatelessWidget {
  const TrendChart({
    super.key,
    required this.trends,
    required this.expenseColor,
    required this.incomeColor,
    this.height = 190,
  });

  final List<MonthlyTrend> trends;
  final Color expenseColor;
  final Color incomeColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '近六个月收支趋势折线图',
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _TrendPainter(
              trends: trends,
              expenseColor: expenseColor,
              incomeColor: incomeColor,
              gridColor: theme.colorScheme.outlineVariant.withValues(
                alpha: 0.5,
              ),
              labelColor: theme.colorScheme.onSurfaceVariant,
              labelStyle: theme.textTheme.labelSmall ?? const TextStyle(),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.trends,
    required this.expenseColor,
    required this.incomeColor,
    required this.gridColor,
    required this.labelColor,
    required this.labelStyle,
  });

  final List<MonthlyTrend> trends;
  final Color expenseColor;
  final Color incomeColor;
  final Color gridColor;
  final Color labelColor;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (trends.isEmpty) return;
    final bottom = size.height - 24;
    final top = 8.0;
    final chartHeight = bottom - top;
    if (chartHeight <= 0) return;

    var maxValue = 0.0;
    for (final item in trends) {
      maxValue = math.max(maxValue, math.max(item.expense, item.income));
    }
    if (maxValue <= 0) maxValue = 1;

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = top + chartHeight * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    double xAt(int index) {
      if (trends.length == 1) return size.width / 2;
      return index * size.width / (trends.length - 1);
    }

    double yAt(double value) =>
        bottom - chartHeight * (value / maxValue).clamp(0, 1).toDouble();

    void drawSeries(double Function(MonthlyTrend) select, Color color) {
      final path = Path();
      for (var i = 0; i < trends.length; i++) {
        final point = Offset(xAt(i), yAt(select(trends[i])));
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      final end = Offset(xAt(trends.length - 1), yAt(select(trends.last)));
      canvas.drawCircle(end, 4.2, Paint()..color = color);
      canvas.drawCircle(
        end,
        2,
        Paint()
          ..color = color.computeLuminance() > 0.5
              ? Colors.white
              : Colors.black,
      );
    }

    drawSeries((item) => item.expense, expenseColor);
    drawSeries((item) => item.income, incomeColor);

    for (var i = 0; i < trends.length; i++) {
      final label = _monthLabel(trends[i].month);
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: labelStyle.copyWith(color: labelColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(
          (xAt(i) - painter.width / 2)
              .clamp(0, math.max(0, size.width - painter.width))
              .toDouble(),
          size.height - painter.height,
        ),
      );
    }
  }

  String _monthLabel(String month) {
    final parts = month.split('-');
    if (parts.length != 2) return month;
    return '${int.tryParse(parts[1]) ?? parts[1]}月';
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.trends != trends ||
      oldDelegate.expenseColor != expenseColor ||
      oldDelegate.incomeColor != incomeColor ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.labelStyle != labelStyle;
}
