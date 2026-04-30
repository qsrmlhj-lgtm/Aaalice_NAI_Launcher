import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../../core/utils/app_logger.dart';
import '../../../core/utils/focused_inpaint_utils.dart';
import '../../../core/utils/inpaint_mask_utils.dart';
import '../../../core/utils/localization_extension.dart';
import '../../widgets/common/app_toast.dart';
import 'core/canvas_controller.dart';
import 'core/editor_state.dart';
import 'core/focused_selection_state.dart';
import 'layers/layer.dart';
import 'painters/focused_overlay_painter.dart';
import 'tools/tool_base.dart';
import 'canvas/editor_canvas.dart';
import 'widgets/toolbar/desktop_toolbar.dart';
import 'widgets/toolbar/mobile_toolbar.dart';
import 'widgets/panels/layer_panel.dart';
import 'widgets/panels/color_panel.dart';
import 'widgets/panels/canvas_size_dialog.dart';
import 'export/image_exporter_new.dart';
import '../../widgets/common/themed_divider.dart';

enum ImageEditorMode {
  edit,
  inpaint,
}

/// 图像编辑器返回结果
class ImageEditorResult {
  /// 修改后的图像（涂鸦合并）
  final Uint8List? modifiedImage;

  /// Inpainting蒙版图像
  final Uint8List? maskImage;

  /// 是否有图像修改
  final bool hasImageChanges;

  /// 是否有蒙版修改
  final bool hasMaskChanges;

  /// Focused Inpaint 选区范围
  final Rect? focusAreaRect;

  /// Focused Inpaint 上下文带宽
  final double minimumContextMegaPixels;

  /// 是否启用 Focused Inpaint
  final bool focusedInpaintEnabled;

  const ImageEditorResult({
    this.modifiedImage,
    this.maskImage,
    this.hasImageChanges = false,
    this.hasMaskChanges = false,
    this.focusAreaRect,
    this.minimumContextMegaPixels = 88.0,
    this.focusedInpaintEnabled = false,
  });
}

/// 图像编辑器主界面
class ImageEditorScreen extends StatefulWidget {
  /// 初始图像（可选，用于编辑已有图像）
  final Uint8List? initialImage;

  /// 初始画布尺寸（当没有初始图像时使用）
  final Size? initialSize;

  /// 已有的蒙版图像
  final Uint8List? existingMask;

  /// 已有的 Focused Inpaint 选区范围
  final Rect? existingFocusRect;

  /// Focused Inpaint 上下文带宽
  final double initialMinimumContextMegaPixels;

  /// 是否启用 Focused Inpaint
  final bool initialFocusedInpaintEnabled;

  /// 是否显示蒙版导出选项
  final bool showMaskExport;

  /// 编辑器模式
  final ImageEditorMode mode;

  /// 标题
  final String title;

  const ImageEditorScreen({
    super.key,
    this.initialImage,
    this.initialSize,
    this.existingMask,
    this.existingFocusRect,
    this.initialMinimumContextMegaPixels = 88.0,
    this.initialFocusedInpaintEnabled = false,
    this.showMaskExport = true,
    this.mode = ImageEditorMode.edit,
    this.title = '画板',
  });

  /// 显示编辑器
  static Future<ImageEditorResult?> show(
    BuildContext context, {
    Uint8List? initialImage,
    Size? initialSize,
    Uint8List? existingMask,
    Rect? existingFocusRect,
    double initialMinimumContextMegaPixels = 88.0,
    bool initialFocusedInpaintEnabled = false,
    bool showMaskExport = true,
    ImageEditorMode mode = ImageEditorMode.edit,
    String title = '画板',
  }) {
    return Navigator.push<ImageEditorResult>(
      context,
      MaterialPageRoute(
        builder: (context) => ImageEditorScreen(
          initialImage: initialImage,
          initialSize: initialSize,
          existingMask: existingMask,
          existingFocusRect: existingFocusRect,
          initialMinimumContextMegaPixels: initialMinimumContextMegaPixels,
          initialFocusedInpaintEnabled: initialFocusedInpaintEnabled,
          showMaskExport: showMaskExport,
          mode: mode,
          title: title,
        ),
      ),
    );
  }

  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends State<ImageEditorScreen> {
  static const Set<String> _inpaintToolIds = {
    'brush',
    'eraser',
    'rect_selection',
    'ellipse_selection',
    'lasso_selection',
  };

  late EditorState _state;
  late FocusedSelectionState _focusedSelectionState;
  late double _minimumContextMegaPixels;
  late bool _focusedInpaintEnabled;
  bool _isMaskFillMode = false;
  bool _isInitialized = false;
  bool _showLayerPanel = true;
  String? _sourceLayerId;

  bool get _isInpaintMode => widget.mode == ImageEditorMode.inpaint;

  @override
  void initState() {
    super.initState();
    _state = EditorState();
    _state.selectionManager.selectionNotifier.addListener(
      _consumeFocusedSelection,
    );
    _focusedSelectionState = FocusedSelectionState(
      canvasSize: const Size(1024, 1024),
      initialRect: widget.existingFocusRect,
    );
    _minimumContextMegaPixels =
        widget.initialMinimumContextMegaPixels.clamp(0.0, 192.0);
    _focusedInpaintEnabled =
        widget.initialFocusedInpaintEnabled || widget.existingFocusRect != null;
    _initializeCanvas();
  }

  Future<void> _initializeCanvas() async {
    if (widget.initialImage != null) {
      // 从已有图像初始化
      await _loadInitialImage();
    } else {
      // 显示尺寸选择对话框或使用默认尺寸
      final size = widget.initialSize ?? const Size(1024, 1024);
      _state.initNewCanvas(size);
      _focusedSelectionState.canvasSize = size;

      // 加载已有蒙版（如果有）
      await _loadExistingMask();
      _loadExistingFocusSelection();
    }

    setState(() {
      _isInitialized = true;
    });

    if (_isInpaintMode) {
      _state.setForegroundColor(const Color(0xFF60AAFF));
      _state.setBrushOpacity(0.55);
      _state.setBrushHardness(1.0);
      _state.setToolById(
        _focusedInpaintEnabled && widget.existingFocusRect == null
            ? 'rect_selection'
            : 'brush',
      );
    }

    // 适应视口
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _state.canvasController.fitToViewport(_state.canvasSize);
    });
  }

  Future<void> _loadInitialImage() async {
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(widget.initialImage!);
      final frame = await codec.getNextFrame();
      final image = frame.image;

      _state.initNewCanvas(
        Size(
          image.width.toDouble(),
          image.height.toDouble(),
        ),
      );
      _focusedSelectionState.canvasSize = _state.canvasSize;

      // 将图像添加为底图图层
      final sourceLayer = await _state.layerManager.addLayerFromImage(
        widget.initialImage!,
        name: '底图',
      );
      _sourceLayerId = sourceLayer?.id;
      if (_isInpaintMode && sourceLayer != null) {
        sourceLayer.locked = true;
      }

      // 选中"图层 1"作为默认绘制图层（而非底图）
      final layer1 = _state.layerManager.layers.firstWhere(
        (l) => l.name == '图层 1',
        orElse: () => _state.layerManager.layers.last,
      );
      _state.layerManager.setActiveLayer(layer1.id);

      // 加载已有蒙版
      await _loadExistingMask();
      _loadExistingFocusSelection();

      image.dispose();
    } catch (e) {
      AppLogger.w('Failed to load initial image: $e', 'ImageEditor');
      _state.initNewCanvas(widget.initialSize ?? const Size(1024, 1024));
      _focusedSelectionState.canvasSize = _state.canvasSize;
    } finally {
      codec?.dispose();
    }
  }

  Future<void> _loadExistingMask() async {
    if (widget.existingMask == null) return;

    try {
      final overlayBytes = InpaintMaskUtils.maskToEditorOverlay(
        widget.existingMask!,
      );

      // 将已有蒙版添加为图层
      final layer = await _addMaskLayerAboveSource(
        overlayBytes,
        name: '已有蒙版',
      );

      if (layer != null) {
        AppLogger.i(
          'Existing mask loaded as layer: ${layer.id}',
          'ImageEditor',
        );
      } else {
        AppLogger.w('Failed to load existing mask as layer', 'ImageEditor');
      }
    } catch (e) {
      AppLogger.e('Error loading existing mask: $e', 'ImageEditor');
    }
  }

  void _loadExistingFocusSelection() {
    if (!_isInpaintMode || widget.existingFocusRect == null) {
      return;
    }
    _focusedSelectionState.load(widget.existingFocusRect);
  }

  @override
  void dispose() {
    _state.selectionManager.selectionNotifier.removeListener(
      _consumeFocusedSelection,
    );
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 900;
        return isDesktop ? _buildDesktopLayout() : _buildMobileLayout();
      },
    );
  }

  /// 桌面端布局
  Widget _buildDesktopLayout() {
    return Scaffold(
      body: Column(
        children: [
          // 顶部菜单栏
          _buildDesktopMenuBar(),

          // 主体区域
          Expanded(
            child: Row(
              children: [
                // 左侧工具栏
                DesktopToolbar(
                  state: _state,
                  onClear: _isInpaintMode ? _resetInpaintMask : null,
                  onFillMask:
                      _isInpaintMode ? _handleFillClosedMaskRegions : null,
                  canFillMask: _isInpaintMode ? _hasMaskContent : null,
                  allowedToolIds: _isInpaintMode ? _inpaintToolIds : null,
                ),

                // 中间画布区域
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: _buildCanvasArea(),
                      ),
                      // 底部状态栏
                      _buildStatusBar(),
                    ],
                  ),
                ),

                // 右侧面板
                if (_showLayerPanel)
                  SizedBox(
                    width: 280,
                    child: Column(
                      children: [
                        // 图层面板
                        Expanded(
                          flex: 2,
                          child: LayerPanel(state: _state),
                        ),
                        const ThemedDivider(height: 1),
                        // 工具设置面板
                        Expanded(
                          flex: 2,
                          child: _buildToolSettingsPanel(),
                        ),
                        const ThemedDivider(height: 1),
                        // 颜色面板
                        if (!_isInpaintMode) ColorPanel(state: _state),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 移动端布局
  Widget _buildMobileLayout() {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          // 图层按钮
          IconButton(
            icon: const Icon(Icons.layers),
            onPressed: _showMobileLayerSheet,
            tooltip: '图层',
          ),
          // 加载蒙版按钮
          if (_isInpaintMode)
            IconButton(
              icon: const Icon(Icons.upload_file),
              onPressed: _loadMask,
              tooltip: '加载蒙版',
            ),
          // 导出按钮
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _exportAndClose,
            tooltip: '完成',
          ),
        ],
      ),
      body: Column(
        children: [
          // 画布区域
          Expanded(
            child: _buildCanvasArea(),
          ),

          // 工具设置（可折叠）
          _buildMobileToolSettings(),

          // 底部工具栏
          MobileToolbar(
            state: _state,
            onClear: _isInpaintMode ? _resetInpaintMask : null,
            onFillMask: _isInpaintMode ? _handleFillClosedMaskRegions : null,
            canFillMask: _isInpaintMode ? _hasMaskContent : null,
            onLayersPressed: _showMobileLayerSheet,
            allowedToolIds: _isInpaintMode ? _inpaintToolIds : null,
          ),
        ],
      ),
    );
  }

  /// 桌面端菜单栏
  Widget _buildDesktopMenuBar() {
    final theme = Theme.of(context);

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          // 返回按钮
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            onPressed: () => _confirmExit(),
            tooltip: '返回',
          ),

          Text(widget.title, style: theme.textTheme.titleSmall),

          const Spacer(),

          // 画布尺寸按钮（使用细粒度监听）
          TextButton.icon(
            icon: const Icon(Icons.aspect_ratio, size: 18),
            label: ValueListenableBuilder<Size>(
              valueListenable: _state.canvasSizeNotifier,
              builder: (context, size, _) => Text(
                '${size.width.toInt()} x ${size.height.toInt()}',
              ),
            ),
            onPressed: _changeCanvasSize,
          ),

          // 加载蒙版按钮
          if (_isInpaintMode)
            IconButton(
              icon: const Icon(Icons.upload_file, size: 20),
              onPressed: _loadMask,
              tooltip: '加载蒙版',
            ),

          const ThemedDivider(
            height: 1,
            vertical: true,
            indent: 8,
            endIndent: 8,
          ),

          // 切换面板
          IconButton(
            icon: Icon(
              _showLayerPanel
                  ? Icons.view_sidebar
                  : Icons.view_sidebar_outlined,
              size: 20,
            ),
            onPressed: () {
              setState(() {
                _showLayerPanel = !_showLayerPanel;
              });
            },
            tooltip: '切换面板',
          ),

          // 快捷键帮助
          IconButton(
            icon: const Icon(Icons.keyboard, size: 20),
            onPressed: _showShortcutHelp,
            tooltip: '快捷键帮助',
          ),

          const ThemedDivider(
            height: 1,
            vertical: true,
            indent: 8,
            endIndent: 8,
          ),

          // 导出按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FilledButton.icon(
              icon: const Icon(Icons.check, size: 18),
              label: const Text('完成'),
              onPressed: _exportAndClose,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 状态栏
  /// 使用 Listenable.merge 实现细粒度监听
  Widget _buildStatusBar() {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge([
        _state.canvasController, // 缩放、旋转、镜像
        _state.canvasSizeNotifier, // 画布尺寸
        _state.layerManager, // 图层数量
        _state.selectionManager, // 选区状态
      ]),
      builder: (context, _) {
        return Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border(
              top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
            ),
          ),
          child: Row(
            children: [
              Text(
                '缩放: ${(_state.canvasController.scale * 100).round()}%',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(width: 16),
              Text(
                '画布: ${_state.canvasSize.width.toInt()} x ${_state.canvasSize.height.toInt()}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(width: 16),
              Text(
                '图层: ${_state.layerManager.layerCount}',
                style: theme.textTheme.bodySmall,
              ),
              if (_state.selectionPath != null) ...[
                const SizedBox(width: 16),
                Text(
                  '有选区',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
              // 旋转角度显示
              if (_state.canvasController.rotation != 0) ...[
                const SizedBox(width: 16),
                Text(
                  '旋转: ${(_state.canvasController.rotation * 180 / 3.14159265359).round()}°',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ],
              // 镜像状态显示
              if (_state.canvasController.isMirroredHorizontally) ...[
                const SizedBox(width: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.flip,
                      size: 14,
                      color: theme.colorScheme.secondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '镜像',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.secondary,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// 工具设置面板
  /// 使用 toolChangeNotifier 实现细粒度监听，仅在工具切换时重建
  Widget _buildToolSettingsPanel() {
    return ValueListenableBuilder<EditorTool?>(
      valueListenable: _state.toolChangeNotifier,
      builder: (context, tool, _) {
        if (tool == null) {
          return Center(child: Text(context.l10n.image_editor_select_tool));
        }
        return SingleChildScrollView(
          child: tool.buildSettingsPanel(context, _state),
        );
      },
    );
  }

  /// 移动端工具设置
  /// 使用 toolChangeNotifier 实现细粒度监听
  Widget _buildMobileToolSettings() {
    return ValueListenableBuilder<EditorTool?>(
      valueListenable: _state.toolChangeNotifier,
      builder: (context, tool, _) {
        if (tool == null) return const SizedBox.shrink();

        return Container(
          constraints: const BoxConstraints(maxHeight: 150),
          child: SingleChildScrollView(
            child: tool.buildSettingsPanel(context, _state),
          ),
        );
      },
    );
  }

  /// 显示移动端图层面板
  void _showMobileLayerSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return LayerPanel(state: _state);
        },
      ),
    );
  }

  /// 显示快捷键帮助
  void _showShortcutHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.keyboard),
            SizedBox(width: 8),
            Text('快捷键帮助'),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 500, maxWidth: 350),
          child: SingleChildScrollView(
            primary: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildShortcutSection('绘画工具', [
                  ('B', '画笔'),
                  ('E', '橡皮擦'),
                  ('P', '拾色器'),
                  ('Alt 按住', '临时拾色器'),
                ]),
                _buildShortcutSection('选区工具', [
                  ('M', '矩形选区'),
                  ('U', '椭圆选区'),
                  ('L', '套索选区'),
                ]),
                _buildShortcutSection('画布视图', [
                  ('1', '100% 缩放'),
                  ('2', '适应高度'),
                  ('3', '适应宽度'),
                  ('4', '向左旋转 15°'),
                  ('5', '重置旋转'),
                  ('6', '向右旋转 15°'),
                  ('F', '水平镜像'),
                  ('R', '重置视图'),
                  ('滚轮', '缩放'),
                  ('Ctrl+0', '100% 缩放'),
                  ('Ctrl++', '放大'),
                  ('Ctrl+-', '缩小'),
                ]),
                _buildShortcutSection('笔刷调整', [
                  ('[', '减小笔刷'),
                  (']', '增大笔刷'),
                  ('I', '降低透明度'),
                  ('O', '提高透明度'),
                  ('Shift + 拖动', '调整笔刷大小'),
                ]),
                _buildShortcutSection('颜色', [
                  ('X', '交换前景/背景色'),
                ]),
                _buildShortcutSection('画布操作', [
                  ('空格 + 拖动', '平移画布'),
                  ('中键拖动', '平移画布'),
                ]),
                _buildShortcutSection('历史操作', [
                  ('Ctrl+Z', '撤销'),
                  ('Ctrl+Shift+Z', '重做'),
                  ('Ctrl+Y', '重做'),
                ]),
                _buildShortcutSection('选区操作', [
                  ('Delete', '清除选区内容'),
                  ('Backspace', '清除选区内容'),
                  ('Esc', '取消当前操作'),
                ]),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildShortcutSection(String title, List<(String, String)> shortcuts) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          ...shortcuts.map(
            (s) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      s.$1,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(s.$2, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 更改画布尺寸
  Future<void> _changeCanvasSize() async {
    final result = await CanvasSizeDialog.show(
      context,
      initialSize: _state.canvasSize,
      title: '更改画布尺寸',
    );

    if (result != null && result.size != _state.canvasSize) {
      try {
        // 验证尺寸范围
        final newWidth = result.size.width.toInt();
        final newHeight = result.size.height.toInt();
        const minSize = 64;
        const maxSize = 4096;

        if (newWidth < minSize || newHeight < minSize) {
          _showError('画布尺寸太小，最小尺寸为 $minSize x $minSize 像素');
          return;
        }

        if (newWidth > maxSize || newHeight > maxSize) {
          _showError('画布尺寸太大，最大尺寸为 $maxSize x $maxSize 像素');
          return;
        }

        // 将 ContentHandlingMode 转换为 CanvasResizeMode
        final mode = _convertContentModeToResizeMode(result.mode);

        // 使用新的 resizeCanvas 方法，支持图层内容变换
        _state.resizeCanvas(result.size, mode);

        // 显示成功消息
        if (mounted) {
          AppToast.success(context, '画布已调整为 $newWidth x $newHeight');
        }
      } catch (e) {
        // 显示错误信息
        _showError('调整画布尺寸失败: $e');
        AppLogger.e('Failed to resize canvas: $e', 'ImageEditor');
      }
    }
  }

  /// 显示错误消息
  void _showError(String message) {
    if (mounted) {
      AppToast.error(context, message);
    }
  }

  /// 将内容处理模式转换为画布调整模式
  CanvasResizeMode _convertContentModeToResizeMode(ContentHandlingMode mode) {
    switch (mode) {
      case ContentHandlingMode.crop:
        return CanvasResizeMode.crop;
      case ContentHandlingMode.pad:
        return CanvasResizeMode.pad;
      case ContentHandlingMode.stretch:
        return CanvasResizeMode.stretch;
    }
  }

  /// 确认退出
  Future<void> _confirmExit() async {
    // 检查是否有修改：检查历史记录或图层内容
    final hasChanges = _state.historyManager.canUndo ||
        _state.layerManager.layers.any(
          (l) => l.strokes.isNotEmpty || l.baseImage != null,
        );

    if (hasChanges) {
      final shouldExit = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('确认退出'),
          content: const Text('有未保存的修改，确定要退出吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('退出'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context, false);
                await _exportAndClose();
              },
              child: const Text('保存并退出'),
            ),
          ],
        ),
      );

      if (shouldExit != true) return;
    }

    if (mounted) {
      Navigator.pop(context);
    }
  }

  /// 导出并关闭
  Future<void> _exportAndClose() async {
    if (!mounted) return;

    // 用于跟踪加载对话框是否已显示
    bool loadingDialogShown = false;

    try {
      // 显示加载指示器
      loadingDialogShown = true;
      unawaited(
        showDialog(
          context: context,
          barrierDismissible: false,
          useRootNavigator: true,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );

      // 检查是否有图像修改（检查是否有笔画或多个图层）
      final hasImageChanges = _state.historyManager.canUndo ||
          _state.layerManager.layers.any((l) => l.strokes.isNotEmpty) ||
          _state.layerManager.layerCount > 1;

      // 检查是否有蒙版修改
      final hasMaskChanges = _hasMaskContent();
      final focusAreaRect =
          _focusedInpaintEnabled ? _focusedSelectionState.committedRect : null;
      final focusedInpaintEnabled =
          _focusedInpaintEnabled && focusAreaRect != null;
      final useFocusedSelectionAsMask =
          focusedInpaintEnabled && !hasMaskChanges;
      AppLogger.d(
        'Export editor result: inpaint=$_isInpaintMode, '
            'hasImageChanges=$hasImageChanges, hasMaskChanges=$hasMaskChanges, '
            'selection=${_state.selectionPath != null}, focusRect=$focusAreaRect, '
            'focusedEnabled=$focusedInpaintEnabled, '
            'useFocusedSelectionAsMask=$useFocusedSelectionAsMask, '
            'layers=${_state.layerManager.layerCount}',
        'ImageEditor',
      );

      // 导出合并图像
      Uint8List? modifiedImage;
      if (!_isInpaintMode && hasImageChanges) {
        modifiedImage = await ImageExporterNew.exportMergedImage(
          _state.layerManager,
          _state.canvasSize,
        );
      }

      // 导出蒙版图像
      Uint8List? maskImage;
      if (_isInpaintMode && widget.showMaskExport && hasMaskChanges) {
        maskImage = await ImageExporterNew.exportMaskFromLayers(
          _state.layerManager,
          _state.canvasSize,
          excludedBaseImageLayerIds: {
            if (_sourceLayerId != null) _sourceLayerId!,
          },
          forceHardEdges: true,
        );
        AppLogger.d(
          'Exported inpaint mask bytes: ${maskImage.length}',
          'ImageEditor',
        );
      } else if (_isInpaintMode &&
          widget.showMaskExport &&
          useFocusedSelectionAsMask) {
        maskImage = await ImageExporterNew.exportMask(
          Path()..addRect(focusAreaRect),
          _state.canvasSize,
          forceHardEdges: true,
        );
        AppLogger.d(
          'Exported focused selection mask bytes: ${maskImage.length}',
          'ImageEditor',
        );
      }

      // 关闭加载指示器
      if (mounted && loadingDialogShown) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingDialogShown = false;
      }

      // 返回结果
      if (mounted) {
        Navigator.of(context).pop(
          ImageEditorResult(
            modifiedImage: modifiedImage,
            maskImage: maskImage,
            hasImageChanges: !_isInpaintMode && hasImageChanges,
            hasMaskChanges:
                _isInpaintMode && (hasMaskChanges || useFocusedSelectionAsMask),
            focusAreaRect: focusAreaRect,
            minimumContextMegaPixels: _minimumContextMegaPixels,
            focusedInpaintEnabled: focusedInpaintEnabled,
          ),
        );
      }
    } catch (e) {
      // 关闭加载指示器
      if (mounted && loadingDialogShown) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      // 显示错误
      if (mounted) {
        AppToast.error(context, '导出失败: $e');
      }
    }
  }

  bool _hasMaskContent() {
    for (final layer in _state.layerManager.layers) {
      if (!layer.visible || layer.id == _sourceLayerId) {
        continue;
      }
      if (layer.hasBaseImage || layer.strokes.isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  void _handleFillClosedMaskRegions() {
    if (!_isInpaintMode) {
      return;
    }

    setState(() {
      _isMaskFillMode = !_isMaskFillMode;
    });

    if (_isMaskFillMode) {
      AppToast.info(context, '请点击封闭区域内部进行填充。');
    }
  }

  Future<void> _fillClosedMaskRegionsAt(Offset localPosition) async {
    if (!_isInpaintMode || !mounted) {
      return;
    }

    try {
      final canvasPoint = _state.canvasController.screenToCanvas(
        localPosition,
        canvasSize: _state.canvasSize,
      );
      final originalMask = await ImageExporterNew.exportMaskFromLayers(
        _state.layerManager,
        _state.canvasSize,
        excludedBaseImageLayerIds: {
          if (_sourceLayerId != null) _sourceLayerId!,
        },
        forceHardEdges: true,
      );
      if (!mounted) {
        return;
      }
      if (!InpaintMaskUtils.hasMaskedPixels(originalMask)) {
        AppToast.warning(context, '请先绘制封闭的蒙版轮廓。');
        return;
      }

      final filledMask = InpaintMaskUtils.fillMaskRegionAtPoint(
        originalMask,
        x: canvasPoint.dx.floor(),
        y: canvasPoint.dy.floor(),
      );
      final deltaMask = InpaintMaskUtils.extractFilledMaskDelta(
        originalMask,
        filledMask,
      );
      if (!InpaintMaskUtils.hasMaskedPixels(deltaMask)) {
        AppToast.info(context, '该位置没有可填充的封闭区域。');
        return;
      }

      final overlayBytes = InpaintMaskUtils.maskToEditorOverlay(filledMask);
      final removableLayerIds = _state.layerManager.layers
          .where((layer) => layer.id != _sourceLayerId)
          .map((layer) => layer.id)
          .toList(growable: false);

      for (final layerId in removableLayerIds) {
        _state.layerManager.removeLayer(layerId);
      }

      final layer = await _addMaskLayerAboveSource(
        overlayBytes,
        name: '蒙版',
      );
      if (layer == null) {
        throw Exception('无法更新蒙版图层');
      }

      _state.requestUiUpdate();
      if (mounted) {
        _isMaskFillMode = false;
        setState(() {});
        AppToast.success(context, '封闭区域已填充为蒙版。');
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, '填充蒙版失败: $e');
      }
    }
  }

  int? _resolveMaskLayerInsertIndex() {
    if (_sourceLayerId == null) {
      return null;
    }

    final sourceIndex = _state.layerManager.layers.indexWhere(
      (layer) => layer.id == _sourceLayerId,
    );
    if (sourceIndex == -1) {
      return null;
    }

    // 蒙版图层应插入到底图上方，否则会被底图完全覆盖。
    return sourceIndex;
  }

  Future<Layer?> _addMaskLayerAboveSource(
    Uint8List imageBytes, {
    required String name,
  }) {
    return _state.layerManager.addLayerFromImage(
      imageBytes,
      name: name,
      index: _resolveMaskLayerInsertIndex(),
    );
  }

  Layer _addEmptyMaskLayerAboveSource({required String name}) {
    return _state.layerManager.addLayer(
      name: name,
      index: _resolveMaskLayerInsertIndex(),
    );
  }

  void _resetInpaintMask() {
    if (!_isInpaintMode) {
      _state.clearActiveLayerWithHistory();
      return;
    }

    final removableLayerIds = _state.layerManager.layers
        .where((layer) => layer.id != _sourceLayerId)
        .map((layer) => layer.id)
        .toList(growable: false);

    for (final layerId in removableLayerIds) {
      _state.layerManager.removeLayer(layerId);
    }

    _state.clearSelection(saveHistory: false);
    _state.clearPreview();
    _focusedSelectionState.clear();
    _isMaskFillMode = false;
    _addEmptyMaskLayerAboveSource(name: '蒙版');
    _state.setToolById(_focusedInpaintEnabled ? 'rect_selection' : 'brush');
    _state.requestUiUpdate();
    setState(() {});
  }

  Widget _buildCanvasArea() {
    final focusAreaRect = _focusedInpaintEnabled
        ? _focusedSelectionState.resolveActiveRect(
            previewPath: _state.previewPath,
          )
        : null;
    final contextCrop = focusAreaRect == null
        ? null
        : FocusedInpaintUtils.resolveContextCropForSelection(
            sourceWidth: _state.canvasSize.width.round(),
            sourceHeight: _state.canvasSize.height.round(),
            selectionRect: focusAreaRect,
            minContextMegaPixels: _minimumContextMegaPixels,
          );

    return Stack(
      children: [
        Positioned.fill(
          child: EditorCanvas(
            state: _state,
            suppressSelectionOverlay: _focusedSelectionState
                .shouldSuppressSelectionOverlay(
              focusedEnabled: _isInpaintMode && _focusedInpaintEnabled,
              currentToolId: _state.currentTool?.id,
              previewPath: _state.previewPath,
            ),
          ),
        ),
        if (_isInpaintMode && focusAreaRect != null && contextCrop != null)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _FocusedContextOverlayPainter(
                  canvasController: _state.canvasController,
                  focusAreaRect: focusAreaRect,
                  contextCrop: contextCrop,
                  repaint: Listenable.merge([
                    _state.renderNotifier,
                    _state.canvasController,
                  ]),
                ),
              ),
            ),
          ),
        if (_isInpaintMode && _isMaskFillMode)
          Positioned.fill(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) {
                  unawaited(_fillClosedMaskRegionsAt(event.localPosition));
                },
                child: const SizedBox.expand(),
              ),
            ),
          ),
        if (_isInpaintMode)
          Positioned(
            top: 16,
            left: 16,
            child: _buildFocusedSelectionCard(),
          ),
      ],
    );
  }

  Widget _buildFocusedSelectionCard() {
    final theme = Theme.of(context);
    final hasFocusArea =
        _focusedInpaintEnabled && _focusedSelectionState.hasCommittedRect;

    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _toggleFocusedInpaint,
                  icon: Icon(
                    _focusedInpaintEnabled
                        ? Icons.crop_free
                        : Icons.filter_center_focus,
                    size: 16,
                  ),
                  label: Text(
                    _focusedInpaintEnabled
                        ? 'Focused Area Selection'
                        : 'Focused Inpaint',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            !_focusedInpaintEnabled
                ? '点击按钮后进入聚焦模式，再框选区域并绘制蒙版。'
                : hasFocusArea
                    ? '已选定聚焦区域，可继续用画笔编辑蒙版。'
                    : '先框选聚焦区域，再切换画笔绘制蒙版。',
            style: theme.textTheme.bodySmall,
          ),
          if (_focusedInpaintEnabled) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                _buildFocusModeButton(
                  icon: Icons.crop_square,
                  label: '选区',
                  toolId: 'rect_selection',
                ),
                const SizedBox(width: 8),
                _buildFocusModeButton(
                  icon: Icons.brush_outlined,
                  label: '画笔',
                  toolId: 'brush',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _focusedSelectionState.hasCommittedRect
                    ? () {
                        setState(() {
                          _focusedSelectionState.clear();
                          _state.clearSelection(saveHistory: false);
                          _state.clearPreview();
                          _state.setToolById('rect_selection');
                        });
                      }
                    : null,
                icon: const Icon(Icons.clear, size: 16),
                label: const Text('清除选区'),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Minimum Context Area: ${_minimumContextMegaPixels.round()}',
              style: theme.textTheme.labelMedium,
            ),
            Slider(
              value: _minimumContextMegaPixels,
              min: 0,
              max: 192,
              divisions: 192,
              onChanged: (value) {
                setState(() {
                  _minimumContextMegaPixels = value;
                });
              },
            ),
            Text(
              '外框是实际送去 Focused Inpaint 的区域，内框是主要重绘区域；两框之间的带宽就是 Minimum Context Area。',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  void _toggleFocusedInpaint() {
    setState(() {
      _focusedInpaintEnabled = !_focusedInpaintEnabled;
      if (_focusedInpaintEnabled) {
        if (!_focusedSelectionState.hasCommittedRect) {
          _state.setToolById('rect_selection');
        }
      } else {
        _state.clearSelection(saveHistory: false);
        _state.clearPreview();
        _focusedSelectionState.clear();
        _state.setToolById('brush');
      }
    });
  }

  void _consumeFocusedSelection() {
    if (!_isInpaintMode || !_focusedInpaintEnabled) {
      return;
    }
    if (_state.currentTool?.id != 'rect_selection') {
      return;
    }
    final consumed = _focusedSelectionState.captureSelection(_state.selectionPath);
    if (!consumed) {
      return;
    }

    _state.clearSelection(saveHistory: false);
    _state.clearPreview();
    _state.setToolById('brush');
    _state.requestUiUpdate();
    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildFocusModeButton({
    required IconData icon,
    required String label,
    required String toolId,
  }) {
    final theme = Theme.of(context);
    final selected = _state.currentTool?.id == toolId;

    return Expanded(
      child: OutlinedButton.icon(
        onPressed: () {
          _state.setToolById(toolId);
        },
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface,
          backgroundColor: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          side: BorderSide(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withValues(alpha: 0.35),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  /// 加载蒙版文件
  Future<void> _loadMaskFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        // 用户取消了文件选择
        return;
      }

      final file = result.files.first;

      // 验证文件扩展名（额外的安全检查）
      if (file.path != null) {
        final extension = file.path!.split('.').last.toLowerCase();
        const validImageExtensions = [
          'png',
          'jpg',
          'jpeg',
          'webp',
          'bmp',
          'gif',
        ];

        if (!validImageExtensions.contains(extension)) {
          AppLogger.w('Invalid file extension: $extension', 'ImageEditor');
          if (mounted) {
            AppToast.error(
              context,
              '不支持的文件格式: .$extension\n请选择图像文件（PNG、JPG、WEBP等）',
            );
          }
          return;
        }
      }

      // 读取文件字节数据
      Uint8List? bytes;
      if (file.bytes != null) {
        bytes = file.bytes;
      } else if (file.path != null) {
        try {
          bytes = await File(file.path!).readAsBytes();
        } catch (e) {
          AppLogger.e('Failed to read file: $e', 'ImageEditor');
          if (mounted) {
            AppToast.error(context, '无法读取文件: $e');
          }
          return;
        }
      }

      // 验证字节数据
      if (bytes == null) {
        AppLogger.w('File bytes is null', 'ImageEditor');
        if (mounted) {
          AppToast.error(context, '无法获取文件数据');
        }
        return;
      }

      // 检查文件是否为空
      if (bytes.isEmpty) {
        AppLogger.w('File is empty (0 bytes)', 'ImageEditor');
        if (mounted) {
          AppToast.error(context, '文件为空，请选择有效的图像文件');
        }
        return;
      }

      // 检查文件大小（限制为 50MB 以防止内存问题）
      const maxFileSize = 50 * 1024 * 1024; // 50MB
      if (bytes.length > maxFileSize) {
        final sizeMB = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
        AppLogger.w('File too large: ${bytes.length} bytes', 'ImageEditor');
        if (mounted) {
          AppToast.error(context, '文件过大（$sizeMB MB），请选择小于 50MB 的图像');
        }
        return;
      }

      // 将蒙版添加为新图层
      final layer = await _addMaskLayerAboveSource(
        bytes,
        name: '蒙版',
      );

      if (layer != null) {
        AppLogger.i('Mask layer added: ${layer.id}', 'ImageEditor');
        if (mounted) {
          AppToast.success(context, '蒙版图层已添加');
        }
      } else {
        // 图像解码失败或格式不支持
        AppLogger.w(
          'Failed to decode image or unsupported format',
          'ImageEditor',
        );
        if (mounted) {
          AppToast.error(context, '无法解析图像文件\n请确保文件未损坏且格式受支持');
        }
      }
    } catch (e) {
      AppLogger.e('Unexpected error loading mask file: $e', 'ImageEditor');
      if (mounted) {
        AppToast.error(context, '加载蒙版时发生错误: $e');
      }
    }
  }

  /// 加载蒙版
  Future<void> _loadMask() async {
    await _loadMaskFile();
  }
}

class _FocusedContextOverlayPainter extends CustomPainter {
  _FocusedContextOverlayPainter({
    required this.canvasController,
    required this.focusAreaRect,
    required this.contextCrop,
    super.repaint,
  });

  final CanvasController canvasController;
  final Rect focusAreaRect;
  final FocusedInpaintCrop contextCrop;

  @override
  void paint(Canvas canvas, Size size) {
    final matrix = canvasController.transformMatrix.storage;
    final screenSelectionPath = (Path()..addRect(focusAreaRect)).transform(
      matrix,
    );
    final screenContextPath = (Path()
          ..addRect(
            Rect.fromLTWH(
              contextCrop.x.toDouble(),
              contextCrop.y.toDouble(),
              contextCrop.width.toDouble(),
              contextCrop.height.toDouble(),
            ),
          ))
        .transform(matrix);

    FocusedOverlayPainter(
      contextPath: screenContextPath,
      focusPath: screenSelectionPath,
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant _FocusedContextOverlayPainter oldDelegate) {
    return contextCrop.x != oldDelegate.contextCrop.x ||
        contextCrop.y != oldDelegate.contextCrop.y ||
        contextCrop.width != oldDelegate.contextCrop.width ||
        contextCrop.height != oldDelegate.contextCrop.height ||
        focusAreaRect != oldDelegate.focusAreaRect ||
        canvasController != oldDelegate.canvasController;
  }
}
