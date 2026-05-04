import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/provider_adapters/prompt_assistant_adapter.dart';

class PromptAssistantCustomDialogResult {
  const PromptAssistantCustomDialogResult({
    required this.userRequest,
    required this.images,
  });

  final String userRequest;
  final List<PromptAssistantImageInput> images;
}

class PromptAssistantCustomDialog extends StatefulWidget {
  const PromptAssistantCustomDialog({
    super.key,
    required this.currentPrompt,
    required this.allowImages,
  });

  final String currentPrompt;
  final bool allowImages;

  @override
  State<PromptAssistantCustomDialog> createState() =>
      _PromptAssistantCustomDialogState();
}

class _PromptAssistantCustomDialogState
    extends State<PromptAssistantCustomDialog> {
  static const int _maxImages = 4;

  final TextEditingController _requestController = TextEditingController();
  final List<PromptAssistantImageInput> _images = [];
  String? _error;

  @override
  void dispose() {
    _requestController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    if (!widget.allowImages) {
      setState(() => _error = '当前自定义任务服务商未启用图片输入');
      return;
    }
    final remaining = _maxImages - _images.length;
    if (remaining <= 0) {
      setState(() => _error = '最多添加 $_maxImages 张参考图片');
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;

    final next = <PromptAssistantImageInput>[];
    for (final file in result.files.take(remaining)) {
      final bytes = await _readBytes(file);
      if (bytes == null) continue;
      final mimeType = detectImageMime(bytes);
      if (mimeType == null) {
        setState(() => _error = '不支持的图片格式: ${file.name}');
        continue;
      }
      next.add(
        PromptAssistantImageInput(
          name: file.name,
          bytes: bytes,
          mimeType: mimeType,
        ),
      );
    }

    if (next.isNotEmpty) {
      setState(() {
        _images.addAll(next);
        _error = null;
      });
    }
  }

  Future<Uint8List?> _readBytes(PlatformFile file) async {
    if (file.bytes != null) return file.bytes;
    final path = file.path;
    if (path == null || path.isEmpty) return null;
    return File(path).readAsBytes();
  }

  void _submit() {
    final request = _requestController.text.trim();
    if (request.isEmpty && _images.isEmpty) {
      setState(() => _error = '请输入自定义需求或添加参考图片');
      return;
    }
    Navigator.pop(
      context,
      PromptAssistantCustomDialogResult(
        userRequest: request,
        images: List.unmodifiable(_images),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('自定义提示词助手'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '当前提示词',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 100),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    widget.currentPrompt.trim().isEmpty
                        ? '（当前提示词为空）'
                        : widget.currentPrompt.trim(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _requestController,
                maxLines: 6,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '你的修改需求',
                  hintText: '例如：更阴森、增加雨夜街道背景、让动作更有张力，只返回最终提示词',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: widget.allowImages ? _pickImages : null,
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('添加参考图'),
                  ),
                  const SizedBox(width: 8),
                  Text('${_images.length}/$_maxImages'),
                  if (!widget.allowImages) ...[
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('当前服务商未启用图片输入'),
                    ),
                  ],
                ],
              ),
              if (_images.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _images.length; i++)
                      _ImageChip(
                        image: _images[i],
                        onRemove: () {
                          setState(() => _images.removeAt(i));
                        },
                      ),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('执行'),
        ),
      ],
    );
  }
}

class _ImageChip extends StatelessWidget {
  const _ImageChip({
    required this.image,
    required this.onRemove,
  });

  final PromptAssistantImageInput image;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(
            image.bytes,
            width: 72,
            height: 72,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: IconButton.filledTonal(
            constraints: const BoxConstraints.tightFor(width: 24, height: 24),
            padding: EdgeInsets.zero,
            iconSize: 14,
            onPressed: onRemove,
            icon: const Icon(Icons.close),
          ),
        ),
      ],
    );
  }
}
