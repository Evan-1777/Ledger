import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/format/inputs.dart';
import '../../core/state/ledger_controller.dart';

class ChannelSheet extends StatefulWidget {
  const ChannelSheet({super.key, required this.initialType, this.initial});

  final ChannelType initialType;
  final PaymentMethod? initial;

  static Future<void> show(
    BuildContext context, {
    required ChannelType initialType,
    PaymentMethod? initial,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ChannelSheet(initialType: initialType, initial: initial),
    );
  }

  @override
  State<ChannelSheet> createState() => _ChannelSheetState();
}

class _ChannelSheetState extends State<ChannelSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _balanceController;
  late final TextEditingController _limitController;
  late ChannelType _type;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _type = initial?.type ?? widget.initialType;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _balanceController = TextEditingController(
      text: initial == null ? '' : _inputAmount(initial.initialBalance),
    );
    _limitController = TextEditingController(
      text: initial == null || initial.creditLimit == 0
          ? ''
          : _inputAmount(initial.creditLimit),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    _limitController.dispose();
    super.dispose();
  }

  String _inputAmount(double value) {
    final text = value.toStringAsFixed(2);
    return text.endsWith('.00') ? text.substring(0, text.length - 3) : text;
  }

  Future<void> _submit() async {
    if (_busy) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请输入账户名称');
      return;
    }
    final balance = parseAmountInput(_balanceController.text, allowEmpty: true);
    if (balance == null || balance < 0) {
      setState(() => _error = '初始金额不能为负数');
      return;
    }
    final limit = _type == ChannelType.liability
        ? parseAmountInput(_limitController.text, allowEmpty: true)
        : 0.0;
    if (limit == null || limit < 0) {
      setState(() => _error = '授信额度不能为负数');
      return;
    }

    final ledger = context.read<LedgerController>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_editing) {
        await ledger.updateChannel(
          widget.initial!,
          name: name,
          type: _type,
          initialBalance: balance,
          creditLimit: limit,
        );
      } else {
        await ledger.createChannel(
          name: name,
          type: _type,
          initialBalance: balance,
          creditLimit: limit,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(_editing ? '账户已更新' : '账户已创建')));
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final insets = MediaQuery.viewInsetsOf(context);
    final size = MediaQuery.sizeOf(context);
    final height = (size.height - insets.bottom) * 0.82;

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
                      _editing ? '编辑账户' : '新增账户',
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
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SegmentedButton<ChannelType>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: ChannelType.asset,
                          label: Text('资产账户'),
                        ),
                        ButtonSegment(
                          value: ChannelType.liability,
                          label: Text('负债账户'),
                        ),
                      ],
                      selected: {_type},
                      onSelectionChanged: (selection) =>
                          setState(() => _type = selection.first),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: '名称',
                        hintText: '例如：招商银行卡',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _balanceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [decimalInputFormatter()],
                      decoration: InputDecoration(
                        labelText: _type == ChannelType.asset ? '初始余额' : '初始欠款',
                        prefixText: '¥ ',
                        hintText: '0.00',
                      ),
                    ),
                    if (_type == ChannelType.liability) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _limitController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [decimalInputFormatter()],
                        decoration: const InputDecoration(
                          labelText: '授信额度',
                          prefixText: '¥ ',
                          hintText: '0.00',
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
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
}
