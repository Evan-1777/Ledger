import 'package:flutter/material.dart';

/// Financial semantic colors kept separate from the Material roles so expense,
/// income, transfer and repayment stay recognizable in both themes.
@immutable
class FinanceColors extends ThemeExtension<FinanceColors> {
  const FinanceColors({
    required this.expense,
    required this.expenseContainer,
    required this.income,
    required this.incomeContainer,
    required this.transfer,
    required this.transferContainer,
    required this.repayment,
    required this.repaymentContainer,
    required this.chart,
  });

  final Color expense;
  final Color expenseContainer;
  final Color income;
  final Color incomeContainer;
  final Color transfer;
  final Color transferContainer;
  final Color repayment;
  final Color repaymentContainer;
  final List<Color> chart;

  static const light = FinanceColors(
    expense: Color(0xFFB3261E),
    expenseContainer: Color(0xFFFFDAD6),
    income: Color(0xFF006D3B),
    incomeContainer: Color(0xFFC4F0D3),
    transfer: Color(0xFF0061A4),
    transferContainer: Color(0xFFD6E7FF),
    repayment: Color(0xFF6A4BA3),
    repaymentContainer: Color(0xFFEADDFF),
    chart: [
      Color(0xFF0078D4),
      Color(0xFF4C8DFF),
      Color(0xFF2E8B6D),
      Color(0xFFB3261E),
      Color(0xFF8E7CC3),
    ],
  );

  static const dark = FinanceColors(
    expense: Color(0xFFFFB4AB),
    expenseContainer: Color(0xFF5F1410),
    income: Color(0xFF7EDCA4),
    incomeContainer: Color(0xFF00391E),
    transfer: Color(0xFFA7C8FF),
    transferContainer: Color(0xFF00325A),
    repayment: Color(0xFFD4BBFF),
    repaymentContainer: Color(0xFF3A2A5C),
    chart: [
      Color(0xFF8ECBFF),
      Color(0xFFB3C9FF),
      Color(0xFF7EDCA4),
      Color(0xFFFFB4AB),
      Color(0xFFD4BBFF),
    ],
  );

  @override
  FinanceColors copyWith({
    Color? expense,
    Color? expenseContainer,
    Color? income,
    Color? incomeContainer,
    Color? transfer,
    Color? transferContainer,
    Color? repayment,
    Color? repaymentContainer,
    List<Color>? chart,
  }) {
    return FinanceColors(
      expense: expense ?? this.expense,
      expenseContainer: expenseContainer ?? this.expenseContainer,
      income: income ?? this.income,
      incomeContainer: incomeContainer ?? this.incomeContainer,
      transfer: transfer ?? this.transfer,
      transferContainer: transferContainer ?? this.transferContainer,
      repayment: repayment ?? this.repayment,
      repaymentContainer: repaymentContainer ?? this.repaymentContainer,
      chart: chart ?? this.chart,
    );
  }

  @override
  FinanceColors lerp(ThemeExtension<FinanceColors>? other, double t) {
    if (other is! FinanceColors) return this;
    List<Color> lerpChart(List<Color> a, List<Color> b) => [
      for (var i = 0; i < a.length; i++) Color.lerp(a[i], b[i], t) ?? a[i],
    ];
    return FinanceColors(
      expense: Color.lerp(expense, other.expense, t)!,
      expenseContainer: Color.lerp(
        expenseContainer,
        other.expenseContainer,
        t,
      )!,
      income: Color.lerp(income, other.income, t)!,
      incomeContainer: Color.lerp(incomeContainer, other.incomeContainer, t)!,
      transfer: Color.lerp(transfer, other.transfer, t)!,
      transferContainer: Color.lerp(
        transferContainer,
        other.transferContainer,
        t,
      )!,
      repayment: Color.lerp(repayment, other.repayment, t)!,
      repaymentContainer: Color.lerp(
        repaymentContainer,
        other.repaymentContainer,
        t,
      )!,
      chart: lerpChart(chart, other.chart),
    );
  }
}

FinanceColors financeColors(BuildContext context) =>
    Theme.of(context).extension<FinanceColors>()!;
