enum TransactionType {
  expense,
  income,
  transfer,
  repayment;

  static TransactionType fromApi(String? value) => switch (value) {
    'income' => TransactionType.income,
    'transfer' => TransactionType.transfer,
    'repayment' => TransactionType.repayment,
    _ => TransactionType.expense,
  };

  String get api => name;

  String get label => switch (this) {
    TransactionType.expense => '支出',
    TransactionType.income => '收入',
    TransactionType.transfer => '转账',
    TransactionType.repayment => '还款',
  };
}

enum ChannelType {
  asset,
  liability;

  static ChannelType fromApi(String? value) =>
      value == 'liability' ? ChannelType.liability : ChannelType.asset;

  String get api => name;

  String get label => switch (this) {
    ChannelType.asset => '资产',
    ChannelType.liability => '负债',
  };
}

enum CategoryType {
  expense,
  income,
  system;

  static CategoryType fromApi(String? value) => switch (value) {
    'income' => CategoryType.income,
    'system' => CategoryType.system,
    _ => CategoryType.expense,
  };

  String? get api => this == CategoryType.system ? null : name;

  String get label => switch (this) {
    CategoryType.expense => '支出',
    CategoryType.income => '收入',
    CategoryType.system => '系统',
  };
}

class PaymentMethod {
  const PaymentMethod({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.type,
    required this.initialBalance,
    required this.creditLimit,
  });

  final int id;
  final String name;
  final int sortOrder;
  final ChannelType type;
  final double initialBalance;
  final double creditLimit;

  factory PaymentMethod.fromJson(Map<String, dynamic> json) => PaymentMethod(
    id: _asInt(json['id']),
    name: _asString(json['name']),
    sortOrder: _asInt(json['sort_order']),
    type: ChannelType.fromApi(json['type'] as String?),
    initialBalance: _asDouble(json['initial_balance']),
    creditLimit: _asDouble(json['credit_limit']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sort_order': sortOrder,
    'type': type.name,
    'initial_balance': initialBalance,
    'credit_limit': creditLimit,
  };
}

class Tag {
  const Tag({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.sortOrder,
  });

  final int id;
  final int categoryId;
  final String name;
  final int sortOrder;

  factory Tag.fromJson(Map<String, dynamic> json) => Tag(
    id: _asInt(json['id']),
    categoryId: _asInt(json['category_id']),
    name: _asString(json['name']),
    sortOrder: _asInt(json['sort_order']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'category_id': categoryId,
    'name': name,
    'sort_order': sortOrder,
  };
}

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.type,
    required this.excludeFromStats,
    required this.tags,
  });

  final int id;
  final String name;
  final int sortOrder;
  final CategoryType type;
  final bool excludeFromStats;
  final List<Tag> tags;

  factory Category.fromJson(Map<String, dynamic> json) => Category(
    id: _asInt(json['id']),
    name: _asString(json['name']),
    sortOrder: _asInt(json['sort_order']),
    type: CategoryType.fromApi(json['type'] as String?),
    excludeFromStats: json['exclude_from_stats'] == true,
    tags: _asList(
      json['tags'],
    ).map((item) => Tag.fromJson(item as Map<String, dynamic>)).toList(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sort_order': sortOrder,
    'type': type.name,
    'exclude_from_stats': excludeFromStats,
    'tags': [for (final tag in tags) tag.toJson()],
  };
}

class Transaction {
  const Transaction({
    required this.id,
    required this.type,
    required this.amountCents,
    required this.feeCents,
    required this.description,
    required this.paymentMethodId,
    required this.paymentMethodName,
    required this.sourcePaymentMethodId,
    required this.sourcePaymentMethodName,
    required this.categoryId,
    required this.categoryName,
    required this.tagId,
    required this.tagName,
    required this.transactedAt,
  });

  final int id;
  final TransactionType type;
  final int amountCents;
  final int feeCents;
  final String description;
  final int paymentMethodId;
  final String paymentMethodName;
  final int? sourcePaymentMethodId;
  final String sourcePaymentMethodName;
  final int categoryId;
  final String categoryName;
  final int tagId;
  final String tagName;
  final DateTime transactedAt;

  double get amount => amountCents / 100;
  double get fee => feeCents / 100;
  DateTime get localTransactedAt => transactedAt.toLocal();

  factory Transaction.fromJson(Map<String, dynamic> json) => Transaction(
    id: _asInt(json['id']),
    type: TransactionType.fromApi(json['type'] as String?),
    amountCents: _asInt(json['amount_cents']),
    feeCents: _asInt(json['fee_cents']),
    description: _asString(json['description']),
    paymentMethodId: _asInt(json['payment_method_id']),
    paymentMethodName: _asString(json['payment_method_name']),
    sourcePaymentMethodId: json['source_payment_method_id'] == null
        ? null
        : _asInt(json['source_payment_method_id']),
    sourcePaymentMethodName: _asString(json['source_payment_method_name']),
    categoryId: _asInt(json['category_id']),
    categoryName: _asString(json['category_name']),
    tagId: _asInt(json['tag_id']),
    tagName: _asString(json['tag_name']),
    transactedAt: DateTime.parse(_asString(json['transacted_at'])).toUtc(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'amount_cents': amountCents,
    'fee_cents': feeCents,
    'description': description,
    'payment_method_id': paymentMethodId,
    'payment_method_name': paymentMethodName,
    'source_payment_method_id': sourcePaymentMethodId,
    'source_payment_method_name': sourcePaymentMethodName,
    'category_id': categoryId,
    'category_name': categoryName,
    'tag_id': tagId,
    'tag_name': tagName,
    'transacted_at': transactedAt.toUtc().toIso8601String(),
  };
}

class TransactionInput {
  const TransactionInput({
    required this.type,
    required this.amount,
    required this.description,
    required this.paymentMethodId,
    required this.categoryId,
    required this.tagId,
    required this.transactedAt,
    this.fee = 0,
    this.sourcePaymentMethodId,
  });

  final TransactionType type;
  final double amount;
  final double fee;
  final String description;
  final int paymentMethodId;
  final int? sourcePaymentMethodId;
  final int categoryId;
  final int tagId;
  final DateTime transactedAt;

  Map<String, dynamic> toJson() => {
    'type': type.api,
    'amount': amount,
    'description': description,
    'payment_method_id': paymentMethodId,
    'category_id': categoryId,
    'tag_id': tagId,
    'transacted_at': transactedAt.toUtc().toIso8601String(),
    if (sourcePaymentMethodId != null &&
        (type == TransactionType.transfer || type == TransactionType.repayment))
      'source_payment_method_id': sourcePaymentMethodId,
    if (type == TransactionType.transfer) 'fee': fee,
  };
}

class TagStat {
  const TagStat({
    required this.id,
    required this.name,
    required this.amount,
    required this.percentage,
  });

  final int id;
  final String name;
  final double amount;
  final double percentage;

  factory TagStat.fromJson(Map<String, dynamic> json) => TagStat(
    id: _asInt(json['id']),
    name: _asString(json['name']),
    amount: _asDouble(json['amount']),
    percentage: _asDouble(json['percentage']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'amount': amount,
    'percentage': percentage,
  };
}

class CategoryStat {
  const CategoryStat({
    required this.id,
    required this.name,
    required this.amount,
    required this.percentage,
    required this.tags,
  });

  final int id;
  final String name;
  final double amount;
  final double percentage;
  final List<TagStat> tags;

  factory CategoryStat.fromJson(Map<String, dynamic> json) => CategoryStat(
    id: _asInt(json['id']),
    name: _asString(json['name']),
    amount: _asDouble(json['amount']),
    percentage: _asDouble(json['percentage']),
    tags: _asList(
      json['tags'],
    ).map((item) => TagStat.fromJson(item as Map<String, dynamic>)).toList(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'amount': amount,
    'percentage': percentage,
    'tags': [for (final tag in tags) tag.toJson()],
  };
}

class PaymentMethodStat {
  const PaymentMethodStat({
    required this.id,
    required this.name,
    required this.amount,
    required this.percentage,
  });

  final int id;
  final String name;
  final double amount;
  final double percentage;

  factory PaymentMethodStat.fromJson(Map<String, dynamic> json) =>
      PaymentMethodStat(
        id: _asInt(json['id']),
        name: _asString(json['name']),
        amount: _asDouble(json['amount']),
        percentage: _asDouble(json['percentage']),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'amount': amount,
    'percentage': percentage,
  };
}

class MonthlyTrend {
  const MonthlyTrend({
    required this.month,
    required this.expense,
    required this.income,
  });

  final String month;
  final double expense;
  final double income;

  factory MonthlyTrend.fromJson(Map<String, dynamic> json) => MonthlyTrend(
    month: _asString(json['month']),
    expense: _asDouble(json['expense']),
    income: _asDouble(json['income']),
  );

  Map<String, dynamic> toJson() => {
    'month': month,
    'expense': expense,
    'income': income,
  };
}

class AssetChannelStat {
  const AssetChannelStat({
    required this.id,
    required this.name,
    required this.remainingBalance,
    required this.initialBalance,
    required this.percentage,
  });

  final int id;
  final String name;
  final double remainingBalance;
  final double initialBalance;
  final double percentage;

  factory AssetChannelStat.fromJson(Map<String, dynamic> json) =>
      AssetChannelStat(
        id: _asInt(json['id']),
        name: _asString(json['name']),
        remainingBalance: _asDouble(json['remaining_balance']),
        initialBalance: _asDouble(json['initial_balance']),
        percentage: _asDouble(json['percentage']),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'remaining_balance': remainingBalance,
    'initial_balance': initialBalance,
    'percentage': percentage,
  };
}

class LiabilityChannelStat {
  const LiabilityChannelStat({
    required this.id,
    required this.name,
    required this.currentDebt,
    required this.initialDebt,
    required this.creditLimit,
    required this.remainingCredit,
    required this.usageRate,
  });

  final int id;
  final String name;
  final double currentDebt;
  final double initialDebt;
  final double creditLimit;
  final double remainingCredit;
  final double usageRate;

  factory LiabilityChannelStat.fromJson(Map<String, dynamic> json) =>
      LiabilityChannelStat(
        id: _asInt(json['id']),
        name: _asString(json['name']),
        currentDebt: _asDouble(json['current_debt']),
        initialDebt: _asDouble(json['initial_debt']),
        creditLimit: _asDouble(json['credit_limit']),
        remainingCredit: _asDouble(json['remaining_credit']),
        usageRate: _asDouble(json['usage_rate']),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'current_debt': currentDebt,
    'initial_debt': initialDebt,
    'credit_limit': creditLimit,
    'remaining_credit': remainingCredit,
    'usage_rate': usageRate,
  };
}

class AssetSummary {
  const AssetSummary({
    required this.totalAssets,
    required this.totalLiabilities,
    required this.netAssets,
    required this.assetChannels,
    required this.liabilityChannels,
  });

  final double totalAssets;
  final double totalLiabilities;
  final double netAssets;
  final List<AssetChannelStat> assetChannels;
  final List<LiabilityChannelStat> liabilityChannels;

  factory AssetSummary.fromJson(Map<String, dynamic> json) => AssetSummary(
    totalAssets: _asDouble(json['total_assets']),
    totalLiabilities: _asDouble(json['total_liabilities']),
    netAssets: _asDouble(json['net_assets']),
    assetChannels: _asList(json['asset_channels'])
        .map((item) => AssetChannelStat.fromJson(item as Map<String, dynamic>))
        .toList(),
    liabilityChannels: _asList(json['liability_channels'])
        .map(
          (item) => LiabilityChannelStat.fromJson(item as Map<String, dynamic>),
        )
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'total_assets': totalAssets,
    'total_liabilities': totalLiabilities,
    'net_assets': netAssets,
    'asset_channels': [for (final channel in assetChannels) channel.toJson()],
    'liability_channels': [
      for (final channel in liabilityChannels) channel.toJson(),
    ],
  };
}

class StatsSummary {
  const StatsSummary({
    required this.weekExpense,
    required this.weekIncome,
    required this.monthExpense,
    required this.monthIncome,
    required this.lastMonthExpense,
    required this.lastMonthIncome,
    required this.monthBalance,
    required this.savingsRate,
    required this.categoryDistribution,
    required this.incomeCategoryDistribution,
    required this.paymentDistribution,
    required this.incomePaymentDistribution,
    required this.monthlyTrends,
    required this.assetSummary,
  });

  final double weekExpense;
  final double weekIncome;
  final double monthExpense;
  final double monthIncome;
  final double lastMonthExpense;
  final double lastMonthIncome;
  final double monthBalance;
  final double savingsRate;
  final List<CategoryStat> categoryDistribution;
  final List<CategoryStat> incomeCategoryDistribution;
  final List<PaymentMethodStat> paymentDistribution;
  final List<PaymentMethodStat> incomePaymentDistribution;
  final List<MonthlyTrend> monthlyTrends;
  final AssetSummary assetSummary;

  factory StatsSummary.fromJson(Map<String, dynamic> json) => StatsSummary(
    weekExpense: _asDouble(json['week_expense']),
    weekIncome: _asDouble(json['week_income']),
    monthExpense: _asDouble(json['month_expense']),
    monthIncome: _asDouble(json['month_income']),
    lastMonthExpense: _asDouble(json['last_month_expense']),
    lastMonthIncome: _asDouble(json['last_month_income']),
    monthBalance: _asDouble(json['month_balance']),
    savingsRate: _asDouble(json['savings_rate']),
    categoryDistribution: _asList(json['category_distribution'])
        .map((item) => CategoryStat.fromJson(item as Map<String, dynamic>))
        .toList(),
    incomeCategoryDistribution: _asList(json['income_category_distribution'])
        .map((item) => CategoryStat.fromJson(item as Map<String, dynamic>))
        .toList(),
    paymentDistribution: _asList(json['payment_distribution'])
        .map((item) => PaymentMethodStat.fromJson(item as Map<String, dynamic>))
        .toList(),
    incomePaymentDistribution: _asList(json['income_payment_distribution'])
        .map((item) => PaymentMethodStat.fromJson(item as Map<String, dynamic>))
        .toList(),
    monthlyTrends: _asList(json['monthly_trends'])
        .map((item) => MonthlyTrend.fromJson(item as Map<String, dynamic>))
        .toList(),
    assetSummary: AssetSummary.fromJson(
      (json['asset_summary'] as Map<String, dynamic>?) ?? const {},
    ),
  );

  Map<String, dynamic> toJson() => {
    'week_expense': weekExpense,
    'week_income': weekIncome,
    'month_expense': monthExpense,
    'month_income': monthIncome,
    'last_month_expense': lastMonthExpense,
    'last_month_income': lastMonthIncome,
    'month_balance': monthBalance,
    'savings_rate': savingsRate,
    'category_distribution': [
      for (final category in categoryDistribution) category.toJson(),
    ],
    'income_category_distribution': [
      for (final category in incomeCategoryDistribution) category.toJson(),
    ],
    'payment_distribution': [
      for (final channel in paymentDistribution) channel.toJson(),
    ],
    'income_payment_distribution': [
      for (final channel in incomePaymentDistribution) channel.toJson(),
    ],
    'monthly_trends': [for (final trend in monthlyTrends) trend.toJson()],
    'asset_summary': assetSummary.toJson(),
  };
}

int _asInt(Object? value) => switch (value) {
  int v => v,
  num v => v.round(),
  String v => int.tryParse(v) ?? 0,
  _ => 0,
};

double _asDouble(Object? value) => switch (value) {
  num v => v.toDouble(),
  String v => double.tryParse(v) ?? 0,
  _ => 0,
};

String _asString(Object? value) => value is String ? value : '';

List<Object?> _asList(Object? value) =>
    value is List ? value : const <Object?>[];
