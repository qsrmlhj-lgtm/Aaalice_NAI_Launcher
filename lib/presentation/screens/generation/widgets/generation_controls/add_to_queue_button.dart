import 'package:flutter/material.dart';

import 'package:nai_launcher/core/utils/localization_extension.dart';

/// 加入队列按钮（仅图标）
class AddToQueueIconButton extends StatelessWidget {
  final VoidCallback onPressed;

  const AddToQueueIconButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 48,
      height: 48,
      child: Tooltip(
        message: context.l10n.queue_addToQueue,
        child: FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Icon(Icons.playlist_add, size: 24),
        ),
      ),
    );
  }
}
