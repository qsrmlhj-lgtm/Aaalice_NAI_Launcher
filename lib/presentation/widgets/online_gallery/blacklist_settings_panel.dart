import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/danbooru_auth_service.dart';
import '../../providers/online_gallery_blacklist_provider.dart';
import '../autocomplete/autocomplete_controller.dart';
import '../autocomplete/autocomplete_strategy.dart';
import '../autocomplete/autocomplete_wrapper.dart';
import '../autocomplete/strategies/local_tag_strategy.dart';
import '../danbooru_login_dialog.dart';

class OnlineGalleryBlacklistSettingsPanel extends ConsumerStatefulWidget {
  final bool compact;
  final bool showSyncStatus;

  const OnlineGalleryBlacklistSettingsPanel({
    super.key,
    this.compact = false,
    this.showSyncStatus = true,
  });

  @override
  ConsumerState<OnlineGalleryBlacklistSettingsPanel> createState() =>
      _OnlineGalleryBlacklistSettingsPanelState();
}

class _OnlineGalleryBlacklistSettingsPanelState
    extends ConsumerState<OnlineGalleryBlacklistSettingsPanel> {
  final TextEditingController _tagController = TextEditingController();
  final FocusNode _tagFocusNode = FocusNode();
  late final Future<AutocompleteStrategy> _autocompleteStrategyFuture;

  @override
  void initState() {
    super.initState();
    _autocompleteStrategyFuture = LocalTagStrategy.create(
      ref,
      const AutocompleteConfig(
        minQueryLength: 1,
        autoInsertComma: false,
      ),
    );
  }

  @override
  void dispose() {
    _tagController.dispose();
    _tagFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(onlineGalleryBlacklistNotifierProvider);
    final notifier = ref.read(onlineGalleryBlacklistNotifierProvider.notifier);

    final localTags = state.localTags.toList()..sort();

    return Card(
      margin: widget.compact ? EdgeInsets.zero : const EdgeInsets.symmetric(vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.block,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '在线画廊黑名单',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: state.isSyncing ? null : () => notifier.syncNow(),
                  icon: state.isSyncing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync, size: 16),
                  label: const Text('立即同步'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '包含黑名单标签的图片会在在线画廊中直接隐藏。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AutocompleteWrapper(
                    controller: _tagController,
                    focusNode: _tagFocusNode,
                    asyncStrategy: _autocompleteStrategyFuture,
                    onSuggestionSelected: (_) => _addTag(),
                    child: TextField(
                      controller: _tagController,
                      focusNode: _tagFocusNode,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                        hintText: '添加黑名单标签',
                      ),
                      onSubmitted: (_) => _addTag(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '添加',
                  onPressed: _addTag,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (localTags.isEmpty)
              Text(
                '暂无本地黑名单标签',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: localTags
                    .map(
                      (tag) => InputChip(
                        label: Text(tag),
                        onDeleted: () {
                          ref
                              .read(onlineGalleryBlacklistNotifierProvider.notifier)
                              .removeLocalTag(tag);
                        },
                      ),
                    )
                    .toList(),
              ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('启动时自动同步'),
              subtitle: const Text('默认开启，可随时关闭'),
              value: state.autoSyncOnStartup,
              onChanged: notifier.setAutoSyncOnStartup,
            ),
            if (widget.showSyncStatus) ...[
              const SizedBox(height: 4),
              _buildSyncStatus(theme, state),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSyncStatus(ThemeData theme, OnlineGalleryBlacklistState state) {
    if (state.lastSyncError != null && state.lastSyncError!.isNotEmpty) {
      return Text(
        '上次同步失败: ${state.lastSyncError}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      );
    }

    if (state.lastSyncAt == null) {
      return Text(
        '尚未同步过 Danbooru 黑名单',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final ts = state.lastSyncAt!;
    final text =
        '${ts.year}-${ts.month.toString().padLeft(2, '0')}-${ts.day.toString().padLeft(2, '0')} '
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';

    return Text(
      '上次同步: $text',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  void _addTag() {
    final value = _tagController.text.trim();
    if (value.isEmpty) return;

    ref.read(onlineGalleryBlacklistNotifierProvider.notifier).addLocalTag(value);
    _tagController.clear();
    _tagFocusNode.requestFocus();
  }
}

Future<void> showOnlineGalleryBlacklistDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final notifier = ref.read(onlineGalleryBlacklistNotifierProvider.notifier);
  notifier.ensureInitialized();

  await showDialog<void>(
    context: context,
    builder: (context) {
      final isLoggedIn = ref.read(danbooruAuthProvider).isLoggedIn;
      return AlertDialog(
        title: const Text('在线画廊黑名单设置'),
        content: SizedBox(
          width: 700,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isLoggedIn) ...[
                  Row(
                    children: [
                      const Icon(Icons.info_outline, size: 16),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          '未登录 Danbooru，仍可使用本地黑名单；同步需要先登录。',
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          showDialog<void>(
                            context: context,
                            builder: (_) => const DanbooruLoginDialog(),
                          );
                        },
                        child: const Text('登录'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                const OnlineGalleryBlacklistSettingsPanel(
                  compact: true,
                  showSyncStatus: false,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      );
    },
  );
}
