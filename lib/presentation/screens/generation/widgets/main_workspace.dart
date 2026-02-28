import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/layout_state_provider.dart';
import '../../../providers/prompt_maximize_provider.dart';
import 'generation_controls/generation_controls.dart';
import 'image_preview.dart';
import 'prompt_input.dart';
import 'resize_handle.dart';

/// 主工作区组件
///
/// 显示提示词输入区、图像预览区和生成控制按钮。
/// 支持提示词区域最大化/还原功能。
class MainWorkspace extends ConsumerWidget {
  final VoidCallback onToggleMaximize;

  const MainWorkspace({
    super.key,
    required this.onToggleMaximize,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final layoutState = ref.watch(layoutStateNotifierProvider);
    final isPromptMaximized = ref.watch(promptMaximizeNotifierProvider);

    return Column(
      children: [
        // 顶部 Prompt 输入区（最大化时占满空间）
        isPromptMaximized
            ? Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withOpacity(0.5),
                  ),
                  child: PromptInputWidget(
                    onToggleMaximize: onToggleMaximize,
                    isMaximized: isPromptMaximized,
                  ),
                ),
              )
            : SizedBox(
                height: layoutState.promptAreaHeight,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withOpacity(0.5),
                  ),
                  child: PromptInputWidget(
                    onToggleMaximize: onToggleMaximize,
                    isMaximized: isPromptMaximized,
                  ),
                ),
              ),

        // 提示词区域拖拽分隔条（最大化时隐藏）
        if (!isPromptMaximized)
          VerticalResizeHandle(
            onDrag: (dy) {
              final currentHeight =
                  ref.read(layoutStateNotifierProvider).promptAreaHeight;
              const minHeight = 100.0;
              const maxHeight = 500.0;
              final newHeight =
                  (currentHeight + dy).clamp(minHeight, maxHeight);
              ref
                  .read(layoutStateNotifierProvider.notifier)
                  .setPromptAreaHeight(newHeight);
            },
          ),

        // 中间图像预览区（最大化时隐藏）
        if (!isPromptMaximized)
          const Expanded(
            child: ImagePreviewWidget(),
          ),

        // 底部生成控制区
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withOpacity(0.5),
            border: Border(
              top: BorderSide(
                color: theme.dividerColor,
                width: 1,
              ),
            ),
          ),
          child: const GenerationControls(),
        ),
      ],
    );
  }
}
