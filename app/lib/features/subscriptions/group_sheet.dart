import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/state/ledger_controller.dart';

class GroupSheet extends StatefulWidget {
  const GroupSheet({super.key, this.initial});

  final SubscriptionGroup? initial;

  static Future<void> show(BuildContext context, {SubscriptionGroup? initial}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => GroupSheet(initial: initial),
    );
  }

  @override
  State<GroupSheet> createState() => _GroupSheetState();
}

class _GroupSheetState extends State<GroupSheet> {
  late final TextEditingController _controller;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial?.name ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请输入分组名称');
      return;
    }
    final ledger = context.read<LedgerController>();
    final lower = name.toLowerCase();
    final duplicated = ledger.subscriptionGroups.any(
      (group) =>
          group.id != widget.initial?.id && group.name.toLowerCase() == lower,
    );
    if (duplicated) {
      setState(() => _error = '分组名称已存在');
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_editing) {
        await ledger.renameSubscriptionGroup(widget.initial!, name);
      } else {
        await ledger.createSubscriptionGroup(name);
      }
      if (!mounted) return;
      navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(_editing ? '分组已重命名' : '分组已创建')));
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
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(_editing ? '重命名分组' : '新建分组'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('group-name'),
              controller: _controller,
              autofocus: true,
              maxLength: 30,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              decoration: const InputDecoration(
                labelText: '分组名称',
                hintText: '例如：影音娱乐',
                counterText: '',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('group-save'),
            onPressed: _busy ? null : _save,
            child: Text(_editing ? '保存' : '创建分组'),
          ),
        ],
      ),
    );
  }
}
