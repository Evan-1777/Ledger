import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/format/dates.dart';
import '../../core/format/inputs.dart';
import '../../core/state/ledger_controller.dart';
import '../../core/widgets/ledger_widgets.dart';
import 'record_rules.dart';

class RecordSheet extends StatefulWidget {
  const RecordSheet({super.key, this.initial, this.onOpenSettings});

  final Transaction? initial;
  final VoidCallback? onOpenSettings;

  static Future<void> show(
    BuildContext context, {
    Transaction? initial,
    VoidCallback? onOpenSettings,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          RecordSheet(initial: initial, onOpenSettings: onOpenSettings),
    );
  }

  @override
  State<RecordSheet> createState() => _RecordSheetState();
}

class _RecordSheetState extends State<RecordSheet> {
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _feeController = TextEditingController();

  late TransactionType _type;
  DateTime _transactedAt = DateTime.now();
  int? _categoryId;
  int? _tagId;
  int? _targetChannelId;
  int? _sourceChannelId;
  bool _categoryOpen = false;
  bool _showFee = false;
  bool _busy = false;
  bool _bootstrapped = false;
  bool _configSyncScheduled = false;
  String? _error;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _type = initial.type;
      _amountController.text = _inputAmount(initial.amount.abs());
      _descriptionController.text = initial.description;
      _feeController.text = initial.feeCents > 0
          ? _inputAmount(initial.fee)
          : '';
      _showFee = initial.feeCents > 0;
      _categoryId = initial.categoryId;
      _tagId = initial.tagId;
      _targetChannelId = initial.paymentMethodId;
      _sourceChannelId = initial.sourcePaymentMethodId;
      _transactedAt = initial.localTransactedAt;
    } else {
      _type = TransactionType.expense;
      _transactedAt = DateTime.now();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapped) return;
    _bootstrapped = true;
    if (!_editing) {
      _applyDefaults();
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _feeController.dispose();
    super.dispose();
  }

  String _inputAmount(double value) {
    final text = value.toStringAsFixed(2);
    return text.endsWith('.00') ? text.substring(0, text.length - 3) : text;
  }

  List<Category> _categoriesForType() {
    final ledger = context.read<LedgerController>();
    return switch (_type) {
      TransactionType.expense => ledger.categoriesOfType(CategoryType.expense),
      TransactionType.income => ledger.categoriesOfType(CategoryType.income),
      _ => const [],
    };
  }

  Category? get _selectedCategory {
    for (final category in context.read<LedgerController>().categories) {
      if (category.id == _categoryId) return category;
    }
    return null;
  }

  void _applyDefaults() {
    final ledger = context.read<LedgerController>();
    final targets = RecordRules.targetChannels(_type, ledger.channels);
    _targetChannelId = targets.isEmpty ? null : targets.first.id;
    _sourceChannelId = null;

    if (_type == TransactionType.transfer) {
      final assets = RecordRules.targetChannels(
        TransactionType.transfer,
        ledger.channels,
      );
      final other = assets.where((item) => item.id != _targetChannelId);
      _sourceChannelId = other.isEmpty ? null : other.first.id;
    }

    if (_type == TransactionType.expense || _type == TransactionType.income) {
      final categories = _categoriesForType();
      final match = categories.where((item) => item.id == _categoryId);
      final category = match.isNotEmpty
          ? match.first
          : (categories.isEmpty ? null : categories.first);
      _categoryId = category?.id;
      _tagId = (category != null && category.tags.isNotEmpty)
          ? category.tags.first.id
          : null;
    } else {
      _selectSystemCategory();
    }
  }

  void _selectSystemCategory() {
    final isTransfer = _type == TransactionType.transfer;
    final category = context.read<LedgerController>().categoryByName(
      isTransfer ? '账户转账' : '债务偿还',
    );
    _categoryId = category?.id ?? 0;
    _tagId = (category != null && category.tags.isNotEmpty)
        ? category.tags.first.id
        : 0;
  }

  bool _needsDefaults(LedgerController ledger) {
    if (_editing) return false;
    if (_type == TransactionType.expense || _type == TransactionType.income) {
      final categories = _categoriesForType();
      if (categories.isNotEmpty) {
        final current = categories.where((item) => item.id == _categoryId);
        if (current.isEmpty) return true;
        final category = current.first;
        if (category.tags.isNotEmpty &&
            !category.tags.any((tag) => tag.id == _tagId)) {
          return true;
        }
      }
    } else {
      final category = ledger.categoryByName(
        _type == TransactionType.transfer ? '账户转账' : '债务偿还',
      );
      if (category != null && _categoryId != category.id) return true;
    }
    final targets = RecordRules.targetChannels(_type, ledger.channels);
    if (targets.isNotEmpty &&
        !targets.any((item) => item.id == _targetChannelId)) {
      return true;
    }
    if (_type == TransactionType.transfer) {
      final sources = RecordRules.sourceChannels(_type, ledger.channels);
      if (sources.length >= 2 &&
          (_sourceChannelId == null || _sourceChannelId == _targetChannelId)) {
        return true;
      }
    }
    return false;
  }

  void _scheduleConfigAdoption() {
    if (_configSyncScheduled) return;
    _configSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _configSyncScheduled = false;
      if (!mounted) return;
      setState(_adoptMissingDefaults);
    });
  }

  void _adoptMissingDefaults() {
    final ledger = context.read<LedgerController>();
    if (_type == TransactionType.expense || _type == TransactionType.income) {
      final categories = _categoriesForType();
      if (categories.isNotEmpty) {
        final current = categories.where((item) => item.id == _categoryId);
        final category = current.isNotEmpty ? current.first : categories.first;
        _categoryId = category.id;
        if (category.tags.isEmpty) {
          _tagId = null;
        } else if (!category.tags.any((tag) => tag.id == _tagId)) {
          _tagId = category.tags.first.id;
        }
      }
    } else {
      final category = ledger.categoryByName(
        _type == TransactionType.transfer ? '账户转账' : '债务偿还',
      );
      if (category != null) {
        _categoryId = category.id;
        _tagId = category.tags.isEmpty ? 0 : category.tags.first.id;
      }
    }
    final targets = RecordRules.targetChannels(_type, ledger.channels);
    if (targets.isNotEmpty &&
        !targets.any((item) => item.id == _targetChannelId)) {
      _targetChannelId = targets.first.id;
    }
    if (_type == TransactionType.transfer) {
      final sources = RecordRules.sourceChannels(_type, ledger.channels);
      if (sources.length >= 2 &&
          (_sourceChannelId == null || _sourceChannelId == _targetChannelId)) {
        final other = sources.where((item) => item.id != _targetChannelId);
        _sourceChannelId = other.isEmpty ? null : other.first.id;
      }
    }
  }

  void _switchType(TransactionType type) {
    if (_editing || type == _type) return;
    setState(() {
      _type = type;
      _categoryId = null;
      _tagId = null;
      _categoryOpen = false;
      _showFee = false;
      _feeController.clear();
      _error = null;
      _applyDefaults();
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _transactedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    if (!mounted) return;
    setState(() {
      _transactedAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _transactedAt.hour,
        _transactedAt.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_transactedAt),
    );
    if (picked == null) return;
    if (!mounted) return;
    setState(() {
      _transactedAt = DateTime(
        _transactedAt.year,
        _transactedAt.month,
        _transactedAt.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  String? _validate() {
    final amount = RecordRules.parsePositiveAmount(_amountController.text);
    if (amount == null) return '请输入大于 0 的金额';
    if (_descriptionController.text.trim().isEmpty) return '请输入用途说明';

    if (_type == TransactionType.transfer) {
      final assets = RecordRules.targetChannels(
        TransactionType.transfer,
        context.read<LedgerController>().channels,
      );
      if (!RecordRules.transferReady(
        assets: assets,
        sourceId: _sourceChannelId,
        targetId: _targetChannelId,
      )) {
        return assets.length < 2 ? '转账需要至少两个资产账户' : '请选择不同的转出与转入账户';
      }
      if (RecordRules.parseFee(_feeController.text) == null) {
        return '手续费不能为负数';
      }
    } else if (_type == TransactionType.repayment) {
      if (_targetChannelId == null) return '请选择还入的负债账户';
    } else {
      if (_targetChannelId == null) return '请选择渠道';
      if (_categoryId == null || _categoryId == 0) return '请选择分类';
      final category = _selectedCategory;
      if (category == null) return '请选择分类';
      if (category.tags.isEmpty) {
        return '该分类暂无细分标签，请先在设置中添加';
      }
      if (_tagId == null) return '请选择细分标签';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final validation = _validate();
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }

    final ledger = context.read<LedgerController>();
    final amount = RecordRules.parsePositiveAmount(_amountController.text)!;
    final fee = _type == TransactionType.transfer
        ? RecordRules.parseFee(_feeController.text)!
        : 0.0;
    final input = TransactionInput(
      type: _type,
      amount: _type == TransactionType.expense ? -amount : amount,
      fee: fee,
      description: _descriptionController.text.trim(),
      paymentMethodId: _targetChannelId!,
      sourcePaymentMethodId:
          _type == TransactionType.transfer ||
              _type == TransactionType.repayment
          ? _sourceChannelId
          : null,
      categoryId: _categoryId ?? 0,
      tagId: _tagId ?? 0,
      transactedAt: _transactedAt,
    );

    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_editing) {
        await ledger.updateTransaction(widget.initial!.id, input);
      } else {
        await ledger.createTransaction(input);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(_editing ? '账单修改成功' : '记账成功')));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '保存失败，请稍后重试';
      });
    }
  }

  void _openSettings() {
    Navigator.of(context).pop();
    widget.onOpenSettings?.call();
  }

  @override
  Widget build(BuildContext context) {
    final ledger = context.watch<LedgerController>();
    if (!_editing && _needsDefaults(ledger)) {
      _scheduleConfigAdoption();
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final insets = MediaQuery.viewInsetsOf(context);
    final size = MediaQuery.sizeOf(context);
    final height = (size.height - insets.bottom) * 0.92;

    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _editing ? '编辑账单' : '记一笔',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SegmentedButton<TransactionType>(
                      showSelectedIcon: false,
                      segments: [
                        for (final type in TransactionType.values)
                          ButtonSegment(value: type, label: Text(type.label)),
                      ],
                      selected: {_type},
                      onSelectionChanged: _editing
                          ? null
                          : (selection) => _switchType(selection.first),
                    ),
                    const SizedBox(height: 24),
                    _FieldLabel('金额', style: theme.textTheme.labelLarge),
                    TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [decimalInputFormatter()],
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      decoration: InputDecoration(
                        prefixText: '¥ ',
                        prefixStyle: theme.textTheme.headlineMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        hintText: '0.00',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                    const Divider(),
                    const SizedBox(height: 16),
                    _FieldLabel('用途说明', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _descriptionController,
                      textInputAction: TextInputAction.done,
                      maxLength: 80,
                      decoration: const InputDecoration(
                        hintText: '例如：午餐 · 牛肉面',
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_type == TransactionType.expense ||
                        _type == TransactionType.income)
                      _buildCategorySection(theme, scheme)
                    else
                      _buildSystemCategory(theme, scheme),
                    const SizedBox(height: 20),
                    _buildChannelSection(theme),
                    if (_type == TransactionType.transfer) ...[
                      const SizedBox(height: 20),
                      _buildFeeSection(theme),
                    ],
                    const SizedBox(height: 20),
                    _FieldLabel('时间', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickDate,
                            icon: const Icon(
                              Icons.calendar_today_outlined,
                              size: 18,
                            ),
                            label: Text(
                              DateFormat('M月d日').format(_transactedAt),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickTime,
                            icon: const Icon(Icons.schedule_outlined, size: 18),
                            label: Text(formatTime(_transactedAt)),
                          ),
                        ),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              size: 20,
                              color: scheme.onErrorContainer,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _error!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : const Text('保存'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySection(ThemeData theme, ColorScheme scheme) {
    final categories = _categoriesForType();
    final selected = _selectedCategory;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _FieldLabel('分类与标签', style: theme.textTheme.labelLarge),
            ),
            if (selected != null)
              TextButton(
                onPressed: () => setState(() => _categoryOpen = !_categoryOpen),
                child: Text(_categoryOpen ? '收起' : '更换'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        LedgerCard(
          color: scheme.surfaceContainerHigh,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          onTap: () => setState(() => _categoryOpen = !_categoryOpen),
          child: Row(
            children: [
              Icon(
                selected == null
                    ? Icons.category_outlined
                    : Icons.sell_outlined,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  selected == null
                      ? '选择分类'
                      : [
                          selected.name,
                          if (_tagId != null)
                            for (final tag in selected.tags)
                              if (tag.id == _tagId) tag.name,
                        ].join(' · '),
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              Icon(Icons.expand_more_rounded, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: !_categoryOpen
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final category in categories)
                            ChoiceChip(
                              label: Text(category.name),
                              selected: category.id == _categoryId,
                              onSelected: (_) => setState(() {
                                _categoryId = category.id;
                                _tagId = category.tags.isEmpty
                                    ? null
                                    : category.tags.first.id;
                              }),
                            ),
                        ],
                      ),
                      if (selected != null) ...[
                        const SizedBox(height: 14),
                        if (selected.tags.isEmpty)
                          Text(
                            '该分类暂无细分标签，请先在设置中添加',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.error,
                            ),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final tag in selected.tags)
                                ChoiceChip(
                                  label: Text(tag.name),
                                  selected: tag.id == _tagId,
                                  onSelected: (_) =>
                                      setState(() => _tagId = tag.id),
                                ),
                            ],
                          ),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSystemCategory(ThemeData theme, ColorScheme scheme) {
    final category = _selectedCategory;
    final isTransfer = _type == TransactionType.transfer;
    return Row(
      children: [
        Icon(
          Icons.lock_outline_rounded,
          size: 18,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${isTransfer ? '账户转账' : '债务偿还'} · ${isTransfer ? '资金互转' : '负债还款'}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        if (category == null && _categoryId == 0)
          Text(
            '系统分类',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  Widget _buildChannelSection(ThemeData theme) {
    final ledger = context.read<LedgerController>();
    final targets = RecordRules.targetChannels(_type, ledger.channels);
    final sources = RecordRules.sourceChannels(_type, ledger.channels);

    Widget chips({
      required List<PaymentMethod> items,
      required int? selectedId,
      required ValueChanged<int> onSelected,
      bool external = false,
    }) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final channel in items)
            ChoiceChip(
              label: Text(channel.name),
              selected: selectedId == channel.id,
              onSelected: (_) => onSelected(channel.id),
            ),
          if (external)
            ChoiceChip(
              label: const Text('外部/未记录资金'),
              selected: selectedId == null,
              onSelected: (_) => onSelected(0),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(switch (_type) {
          TransactionType.expense => '支付渠道',
          TransactionType.income => '入账渠道',
          TransactionType.transfer => '转入账户',
          TransactionType.repayment => '还入账户',
        }, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        if (targets.isEmpty)
          Text(
            _type == TransactionType.repayment
                ? '暂无负债账户，请先在设置中添加'
                : '暂无可用渠道，请先在设置中添加',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          )
        else
          chips(
            items: targets,
            selectedId: _targetChannelId,
            onSelected: (id) => setState(() {
              _targetChannelId = id;
              if (_type == TransactionType.transfer && id == _sourceChannelId) {
                final other = targets.where((item) => item.id != id).toList();
                _sourceChannelId = other.isEmpty ? null : other.first.id;
              }
            }),
          ),
        if (_type == TransactionType.transfer) ...[
          const SizedBox(height: 16),
          _FieldLabel('转出账户', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          if (sources.length < 2)
            Text(
              '转账需要至少两个资产账户',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            )
          else
            chips(
              items: sources,
              selectedId: _sourceChannelId,
              onSelected: (id) => setState(() {
                _sourceChannelId = id;
                if (id == _targetChannelId) {
                  final other = targets.where((item) => item.id != id).toList();
                  _targetChannelId = other.isEmpty ? null : other.first.id;
                }
              }),
            ),
        ],
        if (_type == TransactionType.repayment) ...[
          const SizedBox(height: 16),
          _FieldLabel('资金来源（可选）', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          if (sources.isEmpty)
            Text(
              '未记录资金来源，将按外部资金处理',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            chips(
              items: sources,
              selectedId: _sourceChannelId,
              external: true,
              onSelected: (id) =>
                  setState(() => _sourceChannelId = id == 0 ? null : id),
            ),
        ],
        if (targets.isEmpty && widget.onOpenSettings != null) ...[
          const SizedBox(height: 4),
          TextButton(onPressed: _openSettings, child: const Text('前往设置添加')),
        ],
      ],
    );
  }

  Widget _buildFeeSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_showFee)
          TextButton.icon(
            onPressed: () => setState(() => _showFee = true),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('手续费'),
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: _FieldLabel('手续费', style: theme.textTheme.labelLarge),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _showFee = false;
                  _feeController.clear();
                }),
                child: const Text('清除'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _feeController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [decimalInputFormatter()],
            decoration: const InputDecoration(
              prefixText: '¥ ',
              hintText: '0.00',
            ),
          ),
        ],
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style:
          style ??
          Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}
