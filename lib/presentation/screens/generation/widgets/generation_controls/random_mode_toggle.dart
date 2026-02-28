import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../l10n/app_localizations.dart';
import '../../../../providers/random_prompt_mode_provider.dart';

/// 抽卡模式开关
class RandomModeToggle extends ConsumerStatefulWidget {
  final bool enabled;

  const RandomModeToggle({super.key, required this.enabled});

  @override
  ConsumerState<RandomModeToggle> createState() => _RandomModeToggleState();
}

class _RandomModeToggleState extends ConsumerState<RandomModeToggle>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotateAnimation;
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _rotateAnimation = Tween<double>(begin: 0, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(RandomModeToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled) {
      _controller.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: widget.enabled
            ? context.l10n.randomMode_enabledTip
            : context.l10n.randomMode_disabledTip,
        preferBelow: true,
        child: GestureDetector(
          onTap: () {
            ref.read(randomPromptModeProvider.notifier).toggle();
            if (!widget.enabled) {
              _controller.forward(from: 0);
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: widget.enabled
                  ? (_isHovering
                      ? theme.colorScheme.primary.withOpacity(0.25)
                      : theme.colorScheme.primary.withOpacity(0.15))
                  : (_isHovering
                      ? theme.colorScheme.surfaceContainerHighest
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: widget.enabled
                    ? theme.colorScheme.primary.withOpacity(0.5)
                    : theme.colorScheme.outline.withOpacity(0.3),
                width: widget.enabled ? 1.5 : 1,
              ),
            ),
            child: AnimatedBuilder(
              animation: _rotateAnimation,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _rotateAnimation.value * 3.14159,
                  child: child,
                );
              },
              child: Icon(
                Icons.casino_outlined,
                size: 20,
                color: widget.enabled
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withOpacity(0.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
