import 'package:flutter/services.dart';

TextInputFormatter decimalInputFormatter({int decimals = 2}) {
  final pattern = RegExp('^\\d*\\.?\\d{0,$decimals}\$');
  return TextInputFormatter.withFunction((oldValue, newValue) {
    if (newValue.text.isEmpty || pattern.hasMatch(newValue.text)) {
      return newValue;
    }
    return oldValue;
  });
}

double? parseAmountInput(String raw, {bool allowEmpty = false}) {
  final text = raw.trim();
  if (text.isEmpty) return allowEmpty ? 0 : null;
  return double.tryParse(text);
}
