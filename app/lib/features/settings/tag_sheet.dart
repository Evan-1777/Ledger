import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/state/ledger_controller.dart';
import '../../core/widgets/ledger_widgets.dart';

class TagSheet extends StatefulWidget {
  const TagSheet({super.key, required this.categoryId});

  final int categoryId;

  static Future<void> show(BuildContext context, Category category) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => TagSheet(categoryId: category.id),
    );
  }

  @override
  State<TagSheet> createState() => _TagSheetState();
}

class _TagSheetState extends State<TagSheet> {
  final _addController = TextEditingController();
  final _addFocus = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _addController.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  Category? _category(LedgerController ledger) {
    for (final category in ledger.categories) {
      if (category.id == widget.categoryId) return category;
    }
    return null;
  }

  Future<void> _add(Category category) async {
    if (_busy) return;
    final name = _addController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请输入标签名称');
      return;
    }
    if (category.tags.any((tag) => tag.name == name)) {
      setState(() => _error = '该分类下已存在同名标签');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<LedgerController>().createTag(category, name);
      if (!mounted) return;
      _addController.clear();
      _addFocus.requestFocus();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rename(Category category, Tag tag) async {
    final renamed = await showDialog<bool>(
      context: context,
      builder: (_) => _TagRenameDialog(category: category, tag: tag),
    );
    if (renamed == true && mounted) {
      showLedgerSnackBar(context, '标签已重命名');
    }
  }

  Future<void> _delete(Category category, Tag tag) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: '删除标签',
      message: '删除后该标签不可恢复。\n${tag.name}',
    );
    if (!confirmed || !mounted) return;
    try {
      await context.read<LedgerController>().deleteTag(tag);
      if (!mounted) return;
      showLedgerSnackBar(context, '标签已删除');
    } on ApiException catch (error) {
      if (!mounted) return;
      showLedgerSnackBar(context, error.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ledger = context.watch<LedgerController>();
    final category = _category(ledger);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final insets = MediaQuery.viewInsetsOf(context);
    final size = MediaQuery.sizeOf(context);
    final height = (size.height - insets.bottom) * 0.85;
    final readOnly = category == null || category.type == CategoryType.system;

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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '细分标签',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (category != null)
                          Text(
                            category.name,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!readOnly)
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _addController,
                              focusNode: _addFocus,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _add(category),
                              decoration: const InputDecoration(
                                hintText: '新增标签',
                                prefixIcon: Icon(Icons.sell_outlined),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton.filledTonal(
                            tooltip: '添加标签',
                            onPressed: _busy ? null : () => _add(category),
                            icon: _busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.add_rounded),
                          ),
                        ],
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (category == null)
                      const EmptyState(title: '分类已不存在')
                    else if (category.tags.isEmpty)
                      const EmptyState(
                        title: '暂无细分标签',
                        icon: Icons.sell_outlined,
                      )
                    else
                      LedgerCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (var i = 0; i < category.tags.length; i++) ...[
                              _TagRow(
                                tag: category.tags[i],
                                readOnly: readOnly,
                                onRename: () =>
                                    _rename(category, category.tags[i]),
                                onDelete: () =>
                                    _delete(category, category.tags[i]),
                              ),
                              if (i != category.tags.length - 1)
                                const Divider(height: 1),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.tag,
    required this.readOnly,
    required this.onRename,
    required this.onDelete,
  });

  final Tag tag;
  final bool readOnly;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      child: Row(
        children: [
          Icon(
            Icons.tag_rounded,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(tag.name, style: theme.textTheme.bodyLarge)),
          if (readOnly)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                '只读',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            PopupMenuButton<_TagAction>(
              tooltip: '标签操作',
              clipBehavior: Clip.antiAlias,
              onSelected: (action) {
                switch (action) {
                  case _TagAction.rename:
                    onRename();
                  case _TagAction.delete:
                    onDelete();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _TagAction.rename,
                  child: Text('重命名'),
                ),
                PopupMenuItem(
                  value: _TagAction.delete,
                  child: Text(
                    '删除',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

enum _TagAction { rename, delete }

class _TagRenameDialog extends StatefulWidget {
  const _TagRenameDialog({required this.category, required this.tag});

  final Category category;
  final Tag tag;

  @override
  State<_TagRenameDialog> createState() => _TagRenameDialogState();
}

class _TagRenameDialogState extends State<_TagRenameDialog> {
  late final TextEditingController _controller;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.tag.name);
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
      setState(() => _error = '请输入标签名称');
      return;
    }
    if (widget.category.tags.any(
      (tag) => tag.id != widget.tag.id && tag.name == name,
    )) {
      setState(() => _error = '该分类下已存在同名标签');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<LedgerController>().updateTag(widget.tag, name);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('重命名标签'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(labelText: '标签名称'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('保存')),
      ],
    );
  }
}
