import '../../core/api/models.dart';

class RecordRules {
  static List<PaymentMethod> targetChannels(
    TransactionType type,
    List<PaymentMethod> channels,
  ) {
    final assets = channels
        .where((item) => item.type == ChannelType.asset)
        .toList();
    final liabilities = channels
        .where((item) => item.type == ChannelType.liability)
        .toList();
    return switch (type) {
      TransactionType.expense => channels,
      TransactionType.income => assets,
      TransactionType.transfer => assets,
      TransactionType.repayment => liabilities,
    };
  }

  static List<PaymentMethod> sourceChannels(
    TransactionType type,
    List<PaymentMethod> channels,
  ) {
    if (type != TransactionType.transfer && type != TransactionType.repayment) {
      return const [];
    }
    return channels.where((item) => item.type == ChannelType.asset).toList();
  }

  static bool transferReady({
    required List<PaymentMethod> assets,
    required int? sourceId,
    required int? targetId,
  }) =>
      assets.length >= 2 &&
      sourceId != null &&
      targetId != null &&
      sourceId != targetId;

  static double? parsePositiveAmount(String raw) {
    final value = double.tryParse(raw.trim());
    if (value == null || value <= 0) return null;
    return value;
  }

  static double? parseFee(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return 0;
    final parsed = double.tryParse(value);
    if (parsed == null || parsed < 0) return null;
    return parsed;
  }
}
