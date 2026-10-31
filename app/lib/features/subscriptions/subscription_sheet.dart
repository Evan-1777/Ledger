import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/format/inputs.dart';
import '../../core/state/ledger_controller.dart';
import 'subscriptions_utils.dart';

class SubscriptionSheet extends StatefulWidget {
  const SubscriptionSheet({super.key, this.initial, this.defaultGroupId});

  final Subscription? initial;
  final int? defaultGroupId;

  static Future<void> show(
    BuildContext context, {
    Subscription? initial,
    int? defaultGroupId,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) =>
          SubscriptionSheet(initial: initial, defaultGroupId: defaultGroupId),
    );
  }

  @override
  State<SubscriptionSheet> createState() => _SubscriptionSheetState();
}

class _SubscriptionSheetState extends State<SubscriptionSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _amountController;
  late final TextEditingController _dayController;
  late int _groupId;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _groupId = initial?.groupId ?? widget.defaultGroupId ?? 0;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _amountController = TextEditingController(
      text: initial == null ? '' : _inputAmount(initial.amount),
    );
    _dayController = TextEditingController(
      text: initial == null ? '' : '${initial.billingDay}',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _dayController.dispose();
    super.dispose();
  }

  String _inputAmount(double value) {
    final text = value.toStringAsFixed(2);
    return text.endsWith('.00') ? text.substring(0, text.length - 3) : text;
  }

  void _fail(String message) {
    setState(() => _error = message);
  }

  Future<void> _submit(List<SubscriptionGroup> groups) async {
    if (_busy) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _fail('请输入服务名称');
      return;
    }
    final amount = parseAmountInput(_amountController.text);
    if (amount == null || amount < 0.01 || amount > 1000000) {
      _fail('金额需在 ¥0.01–¥1,000,000.00 之间');
      return;
    }
    final billingDay = int.tryParse(_dayController.text.trim());
    if (billingDay == null || billingDay < 1 || billingDay > 31) {
      _fail('扣款日需为 1–31 的整数');
      return;
    }
    if (_groupId != 0 && !groups.any((group) => group.id == _groupId)) {
      _fail('分组不存在，请重新选择');
      return;
    }

    final ledger = context.read<LedgerController>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final input = SubscriptionInput(
        name: name,
        groupId: _groupId == 0 ? null : _groupId,
        amount: amount,
        billingDay: billingDay,
        status: widget.initial?.status ?? SubscriptionStatus.active,
      );
      if (_editing) {
        await ledger.updateSubscription(widget.initial!, input);
      } else {
        await ledger.createSubscription(input);
      }
      if (!mounted) return;
      navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(_editing ? '订阅已更新' : '订阅已添加')));
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
    final groups = sortedSubscriptionGroups(
      context.watch<LedgerController>().subscriptionGroups,
    );
    final insets = MediaQuery.viewInsetsOf(context);
    final size = MediaQuery.sizeOf(context);
    final height = (size.height - insets.bottom) * 0.86;
    final groupMissing =
        _groupId != 0 && !groups.any((group) => group.id == _groupId);

    return PopScope(
      canPop: !_busy,
      child: Padding(
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
                        _editing ? '编辑订阅' : '添加订阅',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null) ...[
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
                        const SizedBox(height: 16),
                      ],
                      TextField(
                        key: const ValueKey('subscription-name'),
                        controller: _nameController,
                        textInputAction: TextInputAction.next,
                        maxLength: 60,
                        decoration: const InputDecoration(
                          labelText: '服务名称',
                          hintText: '例如：Netflix',
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int>(
                        key: const ValueKey('subscription-group'),
                        initialValue: _groupId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '分组'),
                        items: [
                          const DropdownMenuItem(value: 0, child: Text('未分组')),
                          for (final group in groups)
                            DropdownMenuItem(
                              value: group.id,
                              child: Text(group.name),
                            ),
                          if (groupMissing)
                            DropdownMenuItem(
                              value: _groupId,
                              child: const Text('分组已删除'),
                            ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _groupId = value ?? 0),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              key: const ValueKey('subscription-amount'),
                              controller: _amountController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [decimalInputFormatter()],
                              decoration: const InputDecoration(
                                labelText: '每月金额',
                                prefixText: '¥ ',
                                hintText: '0.00',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              key: const ValueKey('subscription-day'),
                              controller: _dayController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              maxLength: 2,
                              decoration: const InputDecoration(
                                labelText: '扣款日',
                                suffixText: '日',
                                hintText: '15',
                                counterText: '',
                              ),
                            ),
                          ),
                        ],
                      ),
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
                      key: const ValueKey('subscription-save'),
                      onPressed: _busy ? null : () => _submit(groups),
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                              ),
                            )
                          : const Text('保存'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
