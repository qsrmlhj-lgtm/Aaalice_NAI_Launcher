import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/comfyui/workflow_analyzer.dart';
import '../../../../core/comfyui/workflow_template.dart';
import '../../../providers/comfyui/comfyui_provider.dart';
import '../../../widgets/common/app_toast.dart';

/// 工作流导入向导（多步对话框）
///
/// Step 0: 选择 JSON 文件
/// Step 1: 自动分析结果 + 元信息编辑
/// Step 2: 槽位确认/调整
/// Step 3: 确认保存
class WorkflowImportWizard extends ConsumerStatefulWidget {
  const WorkflowImportWizard({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const WorkflowImportWizard(),
    );
  }

  @override
  ConsumerState<WorkflowImportWizard> createState() =>
      _WorkflowImportWizardState();
}

class _WorkflowImportWizardState extends ConsumerState<WorkflowImportWizard> {
  int _step = 0;
  Map<String, dynamic>? _workflowJson;
  WorkflowAnalysisResult? _analysis;
  String? _fileName;

  // Step 1: 元信息
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  WorkflowCategory _category = WorkflowCategory.custom;

  // Step 2: 槽位选择
  final Set<String> _enabledSlotIds = {};

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(theme),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: _buildStepContent(theme),
              ),
            ),
            _buildFooter(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final titles = ['选择工作流文件', '工作流信息', '确认槽位配置', '完成导入'];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Row(
        children: [
          Icon(Icons.upload_file, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('导入 ComfyUI 工作流',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  '步骤 ${_step + 1}/4: ${titles[_step]}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent(ThemeData theme) {
    switch (_step) {
      case 0:
        return _buildFilePickStep(theme);
      case 1:
        return _buildMetaStep(theme);
      case 2:
        return _buildSlotsStep(theme);
      case 3:
        return _buildConfirmStep(theme);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildFooter(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outline.withOpacity(0.2),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_step > 0)
            TextButton(
              onPressed: () => setState(() => _step--),
              child: const Text('上一步'),
            )
          else
            const SizedBox.shrink(),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              if (_step < 3)
                FilledButton(
                  onPressed: _canProceed ? _nextStep : null,
                  child: const Text('下一步'),
                )
              else
                FilledButton.icon(
                  onPressed: _saveWorkflow,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('完成导入'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  bool get _canProceed {
    switch (_step) {
      case 0:
        return _workflowJson != null;
      case 1:
        return _nameController.text.trim().isNotEmpty;
      case 2:
        return _enabledSlotIds.any((id) =>
            _analysis!.outputSlots.any((s) => s.id == id));
      default:
        return true;
    }
  }

  void _nextStep() {
    if (_step == 0 && _workflowJson != null && _analysis == null) {
      _runAnalysis();
    }
    setState(() => _step++);
  }

  void _runAnalysis() {
    _analysis = WorkflowAnalyzer.analyze(_workflowJson!);
    for (final slot in _analysis!.allSlots) {
      _enabledSlotIds.add(slot.id);
    }
    if (_nameController.text.isEmpty) {
      _nameController.text = _fileName?.replaceAll('.json', '') ?? '自定义工作流';
    }
  }

  // ==================== Step 0: 文件选择 ====================

  Widget _buildFilePickStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '请选择 ComfyUI 导出的 workflow_api.json 文件。\n\n'
          '在 ComfyUI 中，点击菜单 → 导出 (API格式) 即可获得此文件。',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        InkWell(
          onTap: _pickWorkflowFile,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 140,
            decoration: BoxDecoration(
              border: Border.all(
                color: _workflowJson != null
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline.withOpacity(0.5),
                width: _workflowJson != null ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(12),
              color: _workflowJson != null
                  ? theme.colorScheme.primaryContainer.withOpacity(0.1)
                  : null,
            ),
            child: Center(
              child: _workflowJson != null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle,
                            color: theme.colorScheme.primary, size: 36),
                        const SizedBox(height: 8),
                        Text(_fileName ?? 'workflow.json',
                            style: theme.textTheme.titleSmall),
                        Text(
                          '${_workflowJson!.length} 个节点',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('点击重新选择',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                            )),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.upload_file,
                            size: 40,
                            color: theme.colorScheme.onSurface.withOpacity(0.4)),
                        const SizedBox(height: 8),
                        Text('点击选择 workflow_api.json',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(0.5),
                            )),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickWorkflowFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      String content;
      if (file.bytes != null) {
        content = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        content = await File(file.path!).readAsString();
      } else {
        return;
      }

      final parsed = json.decode(content);
      if (parsed is! Map<String, dynamic>) {
        if (mounted) AppToast.error(context, '文件格式无效：顶层应为 JSON 对象');
        return;
      }

      // 基本验证：至少有一个含 class_type 的节点
      final hasNodes = parsed.values.any((v) =>
          v is Map<String, dynamic> && v.containsKey('class_type'));
      if (!hasNodes) {
        if (mounted) {
          AppToast.error(context, '未检测到 ComfyUI 节点，请确认是 API 格式导出');
        }
        return;
      }

      setState(() {
        _workflowJson = parsed;
        _fileName = file.name;
        _analysis = null;
      });
    } catch (e) {
      if (mounted) AppToast.error(context, '读取文件失败: $e');
    }
  }

  // ==================== Step 1: 元信息编辑 ====================

  Widget _buildMetaStep(ThemeData theme) {
    final a = _analysis!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 分析摘要
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('自动分析结果', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              _infoRow(theme, Icons.input, '输入图像节点',
                  '${a.inputSlots.length} 个'),
              _infoRow(theme, Icons.tune, '可调参数',
                  '${a.parameterSlots.length} 个'),
              _infoRow(theme, Icons.output, '输出节点',
                  '${a.outputSlots.length} 个'),
              _infoRow(theme, Icons.widgets_outlined, '总节点数',
                  '${a.nodes.length} 个'),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // 名称
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: '工作流名称 *',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),

        // 描述
        TextField(
          controller: _descController,
          decoration: const InputDecoration(
            labelText: '描述',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 12),

        // 分类
        Text('分类', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: WorkflowCategory.values.map((cat) {
            return ChoiceChip(
              label: Text(_categoryLabel(cat)),
              selected: _category == cat,
              onSelected: (selected) {
                if (selected) setState(() => _category = cat);
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _infoRow(ThemeData theme, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(label, style: theme.textTheme.bodySmall),
          const Spacer(),
          Text(value,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ==================== Step 2: 槽位确认 ====================

  Widget _buildSlotsStep(ThemeData theme) {
    final a = _analysis!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '勾选需要暴露给 UI 的槽位。输入/输出槽位建议保留；不需要用户调整的参数可以取消勾选。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 16),
        if (a.inputSlots.isNotEmpty) ...[
          _sectionHeader(theme, '输入', Icons.input),
          ...a.inputSlots.map((s) => _slotTile(theme, s)),
          const SizedBox(height: 12),
        ],
        if (a.outputSlots.isNotEmpty) ...[
          _sectionHeader(theme, '输出', Icons.output),
          ...a.outputSlots.map((s) => _slotTile(theme, s)),
          const SizedBox(height: 12),
        ],
        if (a.parameterSlots.isNotEmpty) ...[
          _sectionHeader(theme, '参数', Icons.tune),
          ...a.parameterSlots.map((s) => _slotTile(theme, s)),
        ],
        if (a.allSlots.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '未检测到任何可用槽位。该工作流可能无法正常集成。\n'
              '请确认工作流中包含 LoadImage 和 SaveImage/SaveImageWebsocket 节点。',
            ),
          ),
      ],
    );
  }

  Widget _sectionHeader(ThemeData theme, String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(title,
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: theme.colorScheme.primary)),
        ],
      ),
    );
  }

  Widget _slotTile(ThemeData theme, WorkflowSlot slot) {
    final enabled = _enabledSlotIds.contains(slot.id);
    return CheckboxListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(slot.label, style: theme.textTheme.bodyMedium),
      subtitle: Text(
        '${slot.direction.name} · ${slot.dataType.name} · '
        '节点 ${slot.nodeId}${slot.field != null ? ".${slot.field}" : ""}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withOpacity(0.5),
        ),
      ),
      value: enabled,
      onChanged: (value) {
        setState(() {
          if (value == true) {
            _enabledSlotIds.add(slot.id);
          } else {
            _enabledSlotIds.remove(slot.id);
          }
        });
      },
    );
  }

  // ==================== Step 3: 确认 ====================

  Widget _buildConfirmStep(ThemeData theme) {
    final enabledSlots = _analysis!.allSlots
        .where((s) => _enabledSlotIds.contains(s.id))
        .toList();
    final inputs =
        enabledSlots.where((s) => s.direction == SlotDirection.input).length;
    final outputs =
        enabledSlots.where((s) => s.direction == SlotDirection.output).length;
    final params = enabledSlots
        .where((s) => s.direction == SlotDirection.parameter)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.check_circle_outline,
            size: 48, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text('即将导入以下工作流',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 16),
        _confirmRow(theme, '名称', _nameController.text.trim()),
        if (_descController.text.trim().isNotEmpty)
          _confirmRow(theme, '描述', _descController.text.trim()),
        _confirmRow(theme, '分类', _categoryLabel(_category)),
        _confirmRow(theme, '输入槽位', '$inputs 个'),
        _confirmRow(theme, '参数槽位', '$params 个'),
        _confirmRow(theme, '输出槽位', '$outputs 个'),
        _confirmRow(theme, '总节点数', '${_workflowJson!.length}'),
        const SizedBox(height: 16),
        Text(
          '导入后可在生成界面的 ComfyUI 工作流列表中使用。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.6),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _confirmRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Flexible(
            child: Text(value,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }

  // ==================== 保存 ====================

  Future<void> _saveWorkflow() async {
    if (_workflowJson == null || _analysis == null) return;

    final enabledSlots = _analysis!.allSlots
        .where((s) => _enabledSlotIds.contains(s.id))
        .toList();

    final name = _nameController.text.trim();
    final id =
        'custom_${name.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_').toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}';

    final template = WorkflowTemplate(
      id: id,
      name: name,
      description: _descController.text.trim(),
      version: '1.0.0',
      author: 'User',
      category: _category,
      requiresInputImage: enabledSlots
          .any((s) => s.direction == SlotDirection.input),
      requiresMask: enabledSlots
          .any((s) => s.dataType == SlotDataType.mask),
      slots: enabledSlots,
      workflowJson: _workflowJson!,
      isBuiltin: false,
    );

    await ref
        .read(comfyUIWorkflowsProvider.notifier)
        .addCustomTemplate(template);

    if (mounted) {
      AppToast.success(context, '工作流 "$name" 导入成功');
      Navigator.of(context).pop();
    }
  }

  String _categoryLabel(WorkflowCategory cat) {
    return switch (cat) {
      WorkflowCategory.enhance => '增强/超分',
      WorkflowCategory.img2img => '图生图',
      WorkflowCategory.inpaint => '重绘',
      WorkflowCategory.txt2img => '文生图',
      WorkflowCategory.custom => '自定义',
    };
  }
}
