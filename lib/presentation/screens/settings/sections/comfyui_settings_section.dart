import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/comfyui/comfyui_models.dart';
import '../../../../core/comfyui/workflow_template.dart';
import '../../../providers/comfyui/comfyui_provider.dart';
import '../../../widgets/common/app_toast.dart';
import '../../../widgets/common/themed_input.dart';
import '../widgets/settings_card.dart';
import '../widgets/workflow_import_wizard.dart';

/// ComfyUI 设置板块
class ComfyUISettingsSection extends ConsumerStatefulWidget {
  const ComfyUISettingsSection({super.key});

  @override
  ConsumerState<ComfyUISettingsSection> createState() =>
      _ComfyUISettingsSectionState();
}

class _ComfyUISettingsSectionState
    extends ConsumerState<ComfyUISettingsSection> {
  final _urlController = TextEditingController();
  bool _isTesting = false;
  String? _testResult;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(comfyUISettingsProvider);
    final connStatus = ref.watch(comfyUIConnectionProvider);
    final workflows = ref.watch(comfyUIWorkflowsProvider);

    if (_urlController.text.isEmpty ||
        _urlController.text != settings.serverUrl) {
      _urlController.text = settings.serverUrl;
    }

    final customWorkflows =
        workflows.where((t) => !t.isBuiltin).toList();
    final builtinWorkflows =
        workflows.where((t) => t.isBuiltin).toList();

    return Column(
      children: [
        SettingsCard(
          title: 'ComfyUI',
          icon: Icons.auto_fix_high,
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.power),
                title: const Text('启用 ComfyUI 集成'),
                subtitle: Text(
                  settings.enabled
                      ? _connectionStatusText(connStatus)
                      : '关闭后将隐藏本地超分等 ComfyUI 功能',
                ),
                value: settings.enabled,
                onChanged: (value) {
                  ref.read(comfyUISettingsProvider.notifier).setEnabled(value);
                  if (!value) {
                    ref.read(comfyUIConnectionProvider.notifier).disconnect();
                  }
                },
              ),
              if (settings.enabled) ...[
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: ThemedInput(
                          controller: _urlController,
                          decoration: const InputDecoration(
                            labelText: '服务器地址',
                            hintText: 'http://127.0.0.1:8188',
                            border: OutlineInputBorder(),
                            isDense: true,
                            prefixIcon: Icon(Icons.dns_outlined),
                          ),
                          onChanged: (value) {
                            ref
                                .read(comfyUISettingsProvider.notifier)
                                .setServerUrl(value);
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.tonal(
                        onPressed: _isTesting ? null : _testConnection,
                        child: _isTesting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('测试连接'),
                      ),
                    ],
                  ),
                ),
                if (_testResult != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          _testResult == 'ok'
                              ? Icons.check_circle
                              : Icons.error_outline,
                          size: 16,
                          color: _testResult == 'ok'
                              ? Colors.green
                              : theme.colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _testResult == 'ok'
                              ? '连接成功'
                              : '连接失败: $_testResult',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _testResult == 'ok'
                                ? Colors.green
                                : theme.colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (connStatus == ComfyUIConnectionStatus.connected)
                  ListTile(
                    leading: const Icon(
                      Icons.circle,
                      color: Colors.green,
                      size: 12,
                    ),
                    title: const Text('已连接'),
                    subtitle: Text(settings.serverUrl),
                    trailing: TextButton(
                      onPressed: () {
                        ref
                            .read(comfyUIConnectionProvider.notifier)
                            .disconnect();
                      },
                      child: const Text('断开'),
                    ),
                  ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),

        // 工作流管理
        if (settings.enabled) ...[
          const SizedBox(height: 16),
          SettingsCard(
            title: '工作流管理',
            icon: Icons.account_tree,
            child: Column(
              children: [
                // 内置工作流列表
                if (builtinWorkflows.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.inventory_2,
                            size: 16,
                            color:
                                theme.colorScheme.onSurface.withOpacity(0.5)),
                        const SizedBox(width: 8),
                        Text('内置工作流',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withOpacity(0.5),
                            )),
                      ],
                    ),
                  ),
                  ...builtinWorkflows
                      .map((t) => _buildWorkflowTile(theme, t)),
                ],

                // 用户自定义工作流
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.person,
                          size: 16,
                          color:
                              theme.colorScheme.onSurface.withOpacity(0.5)),
                      const SizedBox(width: 8),
                      Text('自定义工作流',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withOpacity(0.5),
                          )),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () =>
                            WorkflowImportWizard.show(context),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('导入'),
                      ),
                    ],
                  ),
                ),
                if (customWorkflows.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Text(
                      '暂无自定义工作流，点击「导入」添加 ComfyUI 工作流',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withOpacity(0.4),
                      ),
                    ),
                  )
                else
                  ...customWorkflows
                      .map((t) => _buildWorkflowTile(theme, t)),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWorkflowTile(ThemeData theme, WorkflowTemplate template) {
    final categoryLabel = switch (template.category) {
      WorkflowCategory.enhance => '增强/超分',
      WorkflowCategory.img2img => '图生图',
      WorkflowCategory.inpaint => '重绘',
      WorkflowCategory.txt2img => '文生图',
      WorkflowCategory.custom => '自定义',
    };

    return ListTile(
      leading: Icon(
        template.isBuiltin ? Icons.inventory_2 : Icons.account_tree,
        color: template.isBuiltin
            ? theme.colorScheme.primary
            : theme.colorScheme.tertiary,
      ),
      title: Text(template.name),
      subtitle: Text(
        '$categoryLabel · ${template.slots.length} 个槽位'
        '${template.description.isNotEmpty ? " · ${template.description}" : ""}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: template.isBuiltin
          ? Chip(
              label: const Text('内置'),
              labelStyle: theme.textTheme.bodySmall,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            )
          : IconButton(
              icon: Icon(Icons.delete_outline,
                  color: theme.colorScheme.error, size: 20),
              onPressed: () => _confirmDeleteWorkflow(template),
            ),
    );
  }

  Future<void> _confirmDeleteWorkflow(WorkflowTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除工作流'),
        content: Text('确定要删除工作流「${template.name}」吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref
          .read(comfyUIWorkflowsProvider.notifier)
          .removeCustomTemplate(template.id);
      if (mounted) AppToast.success(context, '已删除: ${template.name}');
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      final ok = await ref
          .read(comfyUIConnectionProvider.notifier)
          .testConnection();
      if (mounted) {
        setState(() {
          _testResult = ok ? 'ok' : '服务器无响应';
          _isTesting = false;
        });
        if (ok) {
          AppToast.success(context, 'ComfyUI 连接成功');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testResult = e.toString();
          _isTesting = false;
        });
      }
    }
  }

  String _connectionStatusText(ComfyUIConnectionStatus status) {
    switch (status) {
      case ComfyUIConnectionStatus.disconnected:
        return '未连接';
      case ComfyUIConnectionStatus.connecting:
        return '正在连接...';
      case ComfyUIConnectionStatus.connected:
        return '已连接';
      case ComfyUIConnectionStatus.error:
        return '连接异常';
    }
  }
}
