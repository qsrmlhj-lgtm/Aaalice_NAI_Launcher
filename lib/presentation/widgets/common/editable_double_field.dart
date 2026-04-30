import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EditableDoubleField extends StatefulWidget {
  const EditableDoubleField({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.decimals = 2,
    this.width = 64,
    this.textStyle,
    this.enabled = true,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int decimals;
  final double width;
  final TextStyle? textStyle;
  final bool enabled;

  @override
  State<EditableDoubleField> createState() => _EditableDoubleFieldState();
}

class _EditableDoubleFieldState extends State<EditableDoubleField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant EditableDoubleField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && oldWidget.value != widget.value) {
      _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      _commit();
    }
  }

  void _commit() {
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed == null) {
      _controller.text = _format(widget.value);
      return;
    }

    final normalized = parsed.clamp(widget.min, widget.max).toDouble();
    if (normalized != widget.value) {
      widget.onChanged(normalized);
    }
    _controller.text = _format(normalized);
  }

  String _format(double value) => value.toStringAsFixed(widget.decimals);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        enabled: widget.enabled,
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]')),
        ],
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          filled: true,
          fillColor: theme.colorScheme.primaryContainer.withOpacity(0.5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: theme.colorScheme.primary),
          ),
        ),
        style: widget.textStyle,
        onSubmitted: (_) => _commit(),
      ),
    );
  }
}
