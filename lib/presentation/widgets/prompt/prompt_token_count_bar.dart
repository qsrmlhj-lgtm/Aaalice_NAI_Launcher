import 'package:flutter/material.dart';

import '../../../core/services/prompt_token_counter_service.dart';

class PromptTokenCountBar extends StatelessWidget {
  const PromptTokenCountBar({
    super.key,
    required this.usage,
  });

  final PromptTokenUsage usage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = usage.isOverLimit
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;
    final tokenText = '${usage.usedTokens} / ${usage.limit}';
    final label = Text(
      tokenText,
      style: theme.textTheme.bodySmall?.copyWith(
        color: color,
        fontWeight: usage.isOverLimit ? FontWeight.w600 : FontWeight.w500,
      ),
    );

    return Align(
      alignment: Alignment.centerRight,
      child: usage.breakdown.isEmpty
          ? label
          : Tooltip(
              message: _buildTooltipMessage(),
              waitDuration: const Duration(milliseconds: 250),
              child: label,
            ),
    );
  }

  String _buildTooltipMessage() {
    return usage.breakdown
        .map((entry) => '${entry.label} ${entry.tokens}')
        .join('\n');
  }
}
