import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/models.dart';
import '../../core/format/money.dart';
import '../../core/state/ledger_controller.dart';
import '../../core/state/preferences_controller.dart';
import '../../core/widgets/ledger_widgets.dart';
import '../auth/session_controller.dart';
import 'channel_sheet.dart';
import 'tag_sheet.dart';

enum SettingsSection { categories, channels }

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.section,
    required this.onSectionChanged,
  });

  final SettingsSection section;
  final ValueChanged<SettingsSection> onSectionChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  CategoryType _categoryType = CategoryType.expense;

  @override
  Widget build(BuildContext context) {
    final ledger = context.watch<LedgerController>();
    final session = context.watch<SessionController>();
    final preferences = context.watch<PreferencesController>();

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        const SliverAppBar.large(title: Text('设置')),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              SegmentedButton<SettingsSection>(
                showSelectedIcon: false,
                expandedInsets: EdgeInsets.zero,
                segments: const [
                  ButtonSegment(
                    value: SettingsSection.categories,
                    label: Text('分类与标签'),
                  ),
                  ButtonSegment(
                    value: SettingsSection.channels,
                    label: Text('渠道与账户'),
                  ),
                ],
                selected: {widget.section},
                onSelectionChanged: (selection) =>
                    widget.onSectionChanged(selection.first),
              ),
              const SizedBox(height: 20),
              if (widget.section == SettingsSection.categories)
                ..._categoryWidgets(ledger)
              else
                ..._channelWidgets(ledger),
              const SectionHeader(
                title: '偏好与服务',
                padding: EdgeInsets.only(top: 28, bottom: 8),
              ),
              _themeCard(preferences),
              const SizedBox(height: 12),
              _serviceCard(session),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  '版本 $_appVersion',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  List<Widget> _categoryWidgets(LedgerController ledger) {
    final list = ledger.categoriesOfType(_categoryType);
    final system = ledger.categories
        .where((category) => category.type == CategoryType.system)
        .toList();

    if (ledger.configLoading && ledger.categories.isEmpty) {
      return const [SkeletonList(rows: 4)];
    }
    if (ledger.configError != null && ledger.categories.isEmpty) {
      return [
        ErrorState(message: ledger.configError!, onRetry: ledger.loadConfig),
      ];
    }

    return [
      SegmentedButton<CategoryType>(
        showSelectedIcon: false,
        expandedInsets: EdgeInsets.zero,
        segments: const [
          ButtonSegment(value: CategoryType.expense, label: Text('支出分类')),
          ButtonSegment(value: CategoryType.income, label: Text('收入分类')),
        ],
        selected: {_categoryType},
        onSelectionChanged: (selection) =>
            setState(() => _categoryType = selection.first),
      ),
      const SizedBox(height: 16),
      if (list.isEmpty)
        LedgerCard(
          child: EmptyState(
            title: '暂无分类',
            icon: Icons.category_outlined,
            actionLabel: '新增分类',
            onAction: () => _openCategoryDialog(null, _categoryType),
          ),
        )
      else
        LedgerCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < list.length; i++) ...[
                _CategoryRow(
                  category: list[i],
                  canMoveUp: i > 0,
                  canMoveDown: i < list.length - 1,
                  onTap: () => TagSheet.show(context, list[i]),
                  onRename: () => _openCategoryDialog(list[i], _categoryType),
                  onMoveUp: () => _move(list[i], -1),
                  onMoveDown: () => _move(list[i], 1),
                  onDelete: () => _deleteCategory(list[i]),
                ),
                if (i != list.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () => _openCategoryDialog(null, _categoryType),
        icon: const Icon(Icons.add_rounded),
        label: const Text('新增分类'),
      ),
      if (system.isNotEmpty) ...[
        const SectionHeader(title: '系统分类'),
        LedgerCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < system.length; i++) ...[
                _SystemCategoryRow(category: system[i]),
                if (i != system.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
      ],
    ];
  }

  List<Widget> _channelWidgets(LedgerController ledger) {
    if (ledger.configLoading && ledger.channels.isEmpty) {
      return const [SkeletonList(rows: 4)];
    }
    if (ledger.configError != null && ledger.channels.isEmpty) {
      return [
        ErrorState(message: ledger.configError!, onRetry: ledger.loadConfig),
      ];
    }
    return [
      SectionHeader(
        title: '资产账户',
        padding: EdgeInsets.zero,
        actionLabel: '新增',
        onAction: () =>
            ChannelSheet.show(context, initialType: ChannelType.asset),
      ),
      _channelGroup(ledger.assetChannels, ChannelType.asset),
      const SectionHeader(title: '负债账户'),
      _channelGroup(ledger.liabilityChannels, ChannelType.liability),
    ];
  }

  Widget _channelGroup(List<PaymentMethod> channels, ChannelType type) {
    if (channels.isEmpty) {
      return LedgerCard(
        child: EmptyState(
          title: type == ChannelType.asset ? '暂无资产账户' : '暂无负债账户',
          icon: type == ChannelType.asset
              ? Icons.account_balance_wallet_outlined
              : Icons.credit_card_outlined,
          actionLabel: '新增',
          onAction: () => ChannelSheet.show(context, initialType: type),
        ),
      );
    }
    return LedgerCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < channels.length; i++) ...[
            _ChannelRow(
              channel: channels[i],
              onEdit: () => ChannelSheet.show(
                context,
                initialType: type,
                initial: channels[i],
              ),
              onDelete: () => _deleteChannel(channels[i]),
            ),
            if (i != channels.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  Widget _themeCard(PreferencesController preferences) {
    final theme = Theme.of(context);
    return LedgerCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '主题',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mode in ThemeMode.values)
                ChoiceChip(
                  label: Text(switch (mode) {
                    ThemeMode.system => '跟随系统',
                    ThemeMode.light => '浅色',
                    ThemeMode.dark => '深色',
                  }),
                  selected: preferences.themeMode == mode,
                  onSelected: (_) => preferences.setThemeMode(mode),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _serviceCard(SessionController session) {
    final theme = Theme.of(context);
    return LedgerCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('服务器'),
            subtitle: Text(
              session.serverUrl ?? '未设置',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _editServer(session),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.logout_rounded, color: theme.colorScheme.error),
            title: Text(
              '退出登录',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            onTap: () => _logout(session),
          ),
        ],
      ),
    );
  }

  Future<void> _openCategoryDialog(
    Category? category,
    CategoryType initialType,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _CategoryDialog(category: category, initialType: initialType),
    );
    if (saved == true && mounted) {
      showLedgerSnackBar(context, category == null ? '分类已创建' : '分类已更新');
    }
  }

  Future<void> _move(Category category, int direction) async {
    try {
      await context.read<LedgerController>().moveCategory(category, direction);
    } on ApiException catch (error) {
      if (!mounted) return;
      showLedgerSnackBar(context, error.message, isError: true);
    }
  }

  Future<void> _deleteCategory(Category category) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: '删除分类',
      message: '删除后该分类及其细分标签不可恢复。\n${category.name}',
    );
    if (!confirmed || !mounted) return;
    try {
      await context.read<LedgerController>().deleteCategory(category);
      if (!mounted) return;
      showLedgerSnackBar(context, '分类已删除');
    } on ApiException catch (error) {
      if (!mounted) return;
      showLedgerSnackBar(context, error.message, isError: true);
    }
  }

  Future<void> _deleteChannel(PaymentMethod channel) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: '删除账户',
      message: '删除后该账户不可恢复。\n${channel.name}',
    );
    if (!confirmed || !mounted) return;
    try {
      await context.read<LedgerController>().deleteChannel(channel);
      if (!mounted) return;
      showLedgerSnackBar(context, '账户已删除');
    } on ApiException catch (error) {
      if (!mounted) return;
      showLedgerSnackBar(context, error.message, isError: true);
    }
  }

  Future<void> _editServer(SessionController session) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ServerDialog(initialUrl: session.serverUrl ?? ''),
    );
    if (changed == true && mounted) {
      showLedgerSnackBar(context, '服务器地址已更新');
    }
  }

  Future<void> _logout(SessionController session) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: '退出登录',
      message: '将清除本机登录凭证并返回登录页。',
      confirmLabel: '退出',
    );
    if (!confirmed || !mounted) return;
    await session.logout();
  }
}

const _appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '0.1.1',
);

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onTap,
    required this.onRename,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
  });

  final Category category;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.category_outlined,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge,
                  ),
                  Text(
                    '${category.tags.length} 个细分标签',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: '分类操作',
              onSelected: (value) {
                switch (value) {
                  case 'rename':
                    onRename();
                  case 'up':
                    onMoveUp();
                  case 'down':
                    onMoveDown();
                  case 'delete':
                    onDelete();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'rename', child: Text('重命名')),
                PopupMenuItem(
                  value: 'up',
                  enabled: canMoveUp,
                  child: const Text('上移'),
                ),
                PopupMenuItem(
                  value: 'down',
                  enabled: canMoveDown,
                  child: const Text('下移'),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    '删除',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemCategoryRow extends StatelessWidget {
  const _SystemCategoryRow({required this.category});

  final Category category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.lock_outline_rounded,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(category.name, style: theme.textTheme.bodyLarge),
                Text(
                  category.tags.map((tag) => tag.name).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '系统 · 只读',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.channel,
    required this.onEdit,
    required this.onDelete,
  });

  final PaymentMethod channel;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                channel.type == ChannelType.asset
                    ? Icons.account_balance_wallet_outlined
                    : Icons.credit_card_outlined,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge,
                  ),
                  if (channel.type == ChannelType.liability)
                    Text(
                      channel.creditLimit > 0
                          ? '额度 ${formatMoney(channel.creditLimit)}'
                          : '不设额度',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: '账户操作',
              onSelected: (value) {
                if (value == 'edit') {
                  onEdit();
                } else {
                  onDelete();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Text('编辑')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    '删除',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({this.category, required this.initialType});

  final Category? category;
  final CategoryType initialType;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final TextEditingController _controller;
  late CategoryType _type;
  bool _busy = false;
  String? _error;

  bool get _editing => widget.category != null;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.category?.name ?? '');
    _type = widget.category?.type == CategoryType.income
        ? CategoryType.income
        : widget.initialType;
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
      setState(() => _error = '请输入分类名称');
      return;
    }
    final ledger = context.read<LedgerController>();
    if (ledger.categories.any(
      (category) =>
          category.id != widget.category?.id &&
          category.name == name &&
          category.type != CategoryType.system,
    )) {
      setState(() => _error = '已存在同名分类');
      return;
    }
    if (_type == CategoryType.system) {
      setState(() => _error = '类型无效');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_editing) {
        await ledger.updateCategory(
          widget.category!,
          name: name,
          sortOrder: widget.category!.sortOrder,
          type: _type,
        );
      } else {
        await ledger.createCategory(name, _type);
      }
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
      title: Text(_editing ? '重命名分类' : '新增分类'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(labelText: '分类名称'),
          ),
          if (_editing) ...[
            const SizedBox(height: 14),
            SegmentedButton<CategoryType>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: CategoryType.expense, label: Text('支出')),
                ButtonSegment(value: CategoryType.income, label: Text('收入')),
              ],
              selected: {_type},
              onSelectionChanged: (selection) =>
                  setState(() => _type = selection.first),
            ),
          ],
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

class _ServerDialog extends StatefulWidget {
  const _ServerDialog({required this.initialUrl});

  final String initialUrl;

  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}

class _ServerDialogState extends State<_ServerDialog> {
  late final TextEditingController _controller;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final raw = _controller.text.trim();
    try {
      normalizeServerUrl(raw);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await context.read<SessionController>().updateServer(raw);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = '正式版仅支持 HTTPS';
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('服务器地址'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(
              hintText: 'https://ledger.example.com',
            ),
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
