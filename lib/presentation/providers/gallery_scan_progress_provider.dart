import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_logger.dart';

/// 扫描进度状态
class ScanProgressState {
  final bool isScanning;
  final int processed;
  final int total;
  final String currentFile;
  final String phase;
  final double progress;
  final int filesAdded;
  final int filesUpdated;
  final int filesRemoved;
  final List<String> errors;

  const ScanProgressState({
    this.isScanning = false,
    this.processed = 0,
    this.total = 0,
    this.currentFile = '',
    this.phase = '',
    this.progress = 0.0,
    this.filesAdded = 0,
    this.filesUpdated = 0,
    this.filesRemoved = 0,
    this.errors = const [],
  });

  ScanProgressState copyWith({
    bool? isScanning,
    int? processed,
    int? total,
    String? currentFile,
    String? phase,
    double? progress,
    int? filesAdded,
    int? filesUpdated,
    int? filesRemoved,
    List<String>? errors,
  }) {
    return ScanProgressState(
      isScanning: isScanning ?? this.isScanning,
      processed: processed ?? this.processed,
      total: total ?? this.total,
      currentFile: currentFile ?? this.currentFile,
      phase: phase ?? this.phase,
      progress: progress ?? this.progress,
      filesAdded: filesAdded ?? this.filesAdded,
      filesUpdated: filesUpdated ?? this.filesUpdated,
      filesRemoved: filesRemoved ?? this.filesRemoved,
      errors: errors ?? this.errors,
    );
  }
}

/// 画廊扫描进度Provider
///
/// 用于监听和显示本地画廊的扫描进度
class GalleryScanProgressNotifier extends StateNotifier<ScanProgressState> {
  GalleryScanProgressNotifier() : super(const ScanProgressState());

  Timer? _hideTimer;

  /// 开始扫描
  void startScan({required int total}) {
    _hideTimer?.cancel();
    state = ScanProgressState(
      isScanning: true,
      processed: 0,
      total: total,
      currentFile: '',
      phase: 'scanning',
      progress: 0.0,
    );
    AppLogger.d('[ScanProgress] Scan started: $total files', 'GalleryScanProgress');
  }

  /// 更新进度
  void updateProgress({
    required int processed,
    required int total,
    String? currentFile,
    required String phase,
  }) {
    if (!state.isScanning) return;

    final progress = total > 0 ? processed / total : 0.0;
    state = state.copyWith(
      processed: processed,
      total: total,
      currentFile: currentFile,
      phase: phase,
      progress: progress,
    );
  }

  /// 更新统计
  void updateStats({
    int? filesAdded,
    int? filesUpdated,
    int? filesRemoved,
  }) {
    state = state.copyWith(
      filesAdded: filesAdded ?? state.filesAdded,
      filesUpdated: filesUpdated ?? state.filesUpdated,
      filesRemoved: filesRemoved ?? state.filesRemoved,
    );
  }

  /// 添加错误
  void addError(String error) {
    final errors = [...state.errors, error];
    state = state.copyWith(errors: errors);
  }

  /// 完成扫描
  void completeScan() {
    state = state.copyWith(
      isScanning: false,
      phase: 'completed',
      progress: 1.0,
    );
    AppLogger.d('[ScanProgress] Scan completed', 'GalleryScanProgress');

    // 3秒后自动隐藏进度条
    _hideTimer = Timer(const Duration(seconds: 3), () {
      state = const ScanProgressState();
    });
  }

  /// 重置状态
  void reset() {
    _hideTimer?.cancel();
    state = const ScanProgressState();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }
}

/// 全局扫描进度Provider
final galleryScanProgressProvider =
    StateNotifierProvider<GalleryScanProgressNotifier, ScanProgressState>(
  (ref) => GalleryScanProgressNotifier(),
);

/// 用于包装扫描回调的辅助函数
///
/// 返回一个符合 ScanProgressCallback 签名的函数
void Function({
  required int processed,
  required int total,
  String? currentFile,
  required String phase,
}) createScanProgressCallback(GalleryScanProgressNotifier notifier) {
  return ({
    required int processed,
    required int total,
    String? currentFile,
    required String phase,
  }) {
    // 检测是否开始新扫描
    if (processed == 0 && phase == 'indexing') {
      notifier.startScan(total: total);
    }

    // 更新进度
    notifier.updateProgress(
      processed: processed,
      total: total,
      currentFile: currentFile,
      phase: phase,
    );

    // 检测完成
    if (processed >= total && total > 0) {
      notifier.completeScan();
    }
  };
}
