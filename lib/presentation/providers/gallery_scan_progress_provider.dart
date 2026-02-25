import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_logger.dart';
import '../../data/services/gallery/scan_state_manager.dart';

/// 扫描进度状态 - 改进版
/// 
/// 改进：进度计算包含跳过的文件，提供更直观的用户体验
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
  final int filesSkipped;  // 新增：跳过的文件数
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
    this.filesSkipped = 0,  // 新增
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
    int? filesSkipped,  // 新增
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
      filesSkipped: filesSkipped ?? this.filesSkipped,  // 新增
      errors: errors ?? this.errors,
    );
  }

  /// 计算包含跳过文件的总进度
  int get effectiveProcessed => processed + filesSkipped;
  
  /// 计算包含跳过文件的进度比例
  double get effectiveProgress => total > 0 ? effectiveProcessed / total : 0.0;
}

/// 画廊扫描进度Provider
///
/// 用于监听和显示本地画廊的扫描进度
/// 
/// 改进：自动订阅 ScanStateManager，即使页面切换也能接收进度更新
class GalleryScanProgressNotifier extends StateNotifier<ScanProgressState> {
  StreamSubscription<ScanProgressInfo>? _progressSubscription;
  StreamSubscription<ScanStatus>? _statusSubscription;
  Timer? _hideTimer;

  GalleryScanProgressNotifier() : super(const ScanProgressState()) {
    // 自动订阅 ScanStateManager 的进度流和状态流
    // 这样即使页面切换，Provider 仍然存活并接收进度更新
    final scanManager = ScanStateManager.instance;
    
    _progressSubscription = scanManager.progressStream.listen(_onProgressUpdate);
    _statusSubscription = scanManager.statusStream.listen(_onStatusChange);
    
    // 初始化时同步当前状态（如果扫描正在进行中）
    if (scanManager.isScanning) {
      state = state.copyWith(
        isScanning: true,
        total: scanManager.progress.total,
        processed: scanManager.progress.processed,
        currentFile: scanManager.progress.currentFile ?? '',
        phase: scanManager.progress.phase.name,
        progress: scanManager.progress.total > 0 
            ? scanManager.progress.processed / scanManager.progress.total 
            : 0.0,
      );
    }
  }

  /// 处理进度更新
  void _onProgressUpdate(ScanProgressInfo progress) {
    // 如果扫描刚开始，自动调用 startScan
    if (!state.isScanning && progress.processed == 0 && progress.total > 0) {
      startScan(total: progress.total);
      return;
    }
    
    if (!state.isScanning) return;

    // 使用 effectiveProgress（包含跳过的文件）计算进度
    final effectiveProcessed = progress.processed + state.filesSkipped;
    final progressValue = progress.total > 0 ? effectiveProcessed / progress.total : 0.0;
    
    state = state.copyWith(
      processed: progress.processed,
      total: progress.total,
      currentFile: progress.currentFile ?? '',
      phase: progress.phase.name,
      progress: progressValue,
    );

    // 检测完成
    if (progress.processed >= progress.total && progress.total > 0) {
      completeScan();
    }
  }

  /// 处理状态改变
  void _onStatusChange(ScanStatus status) {
    switch (status) {
      case ScanStatus.scanning:
        // 扫描开始，确保状态正确
        if (!state.isScanning) {
          final scanManager = ScanStateManager.instance;
          startScan(total: scanManager.progress.total);
        }
        break;
      case ScanStatus.completed:
        // 扫描完成
        if (state.isScanning) {
          completeScan();
        }
        break;
      case ScanStatus.error:
      case ScanStatus.cancelled:
        // 扫描出错或被取消，停止显示进度
        if (state.isScanning) {
          state = state.copyWith(isScanning: false);
        }
        break;
      case ScanStatus.paused:
      case ScanStatus.idle:
        // 暂停或空闲，不做特殊处理
        break;
    }
  }

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
      filesAdded: state.filesAdded,
      filesUpdated: state.filesUpdated,
      filesRemoved: state.filesRemoved,
      filesSkipped: state.filesSkipped,
    );
    AppLogger.d('[ScanProgress] Scan started: $total files', 'GalleryScanProgress');
  }

  /// 更新进度
  void updateProgress({
    required int processed,
    required int total,
    String? currentFile,
    required String phase,
    int? filesSkipped,  // 新增：跳过的文件数
  }) {
    if (!state.isScanning) return;

    // 使用 effectiveProgress（包含跳过的文件）计算进度
    final effectiveProcessed = processed + (filesSkipped ?? state.filesSkipped);
    final progress = total > 0 ? effectiveProcessed / total : 0.0;
    
    state = state.copyWith(
      processed: processed,
      total: total,
      currentFile: currentFile,
      phase: phase,
      progress: progress,
      filesSkipped: filesSkipped,
    );
  }

  /// 更新统计
  void updateStats({
    int? filesAdded,
    int? filesUpdated,
    int? filesRemoved,
    int? filesSkipped,  // 新增
  }) {
    state = state.copyWith(
      filesAdded: filesAdded ?? state.filesAdded,
      filesUpdated: filesUpdated ?? state.filesUpdated,
      filesRemoved: filesRemoved ?? state.filesRemoved,
      filesSkipped: filesSkipped ?? state.filesSkipped,
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
    _progressSubscription?.cancel();
    _statusSubscription?.cancel();
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
/// 所有状态更新都延迟到下一帧执行，避免在构建期间修改 provider
void Function({
  required int processed,
  required int total,
  String? currentFile,
  required String phase,
  int? filesSkipped,  // 新增
}) createScanProgressCallback(GalleryScanProgressNotifier notifier) {
  return ({
    required int processed,
    required int total,
    String? currentFile,
    required String phase,
    int? filesSkipped,  // 新增
  }) {
    // 延迟到下一帧执行，避免在构建期间修改 provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 检测是否开始新扫描
      // 注意：phase 可能是 'indexing' 或 'ScanPhase.indexing'（枚举转字符串）
      if (processed == 0 && (phase == 'indexing' || phase == 'ScanPhase.indexing')) {
        notifier.startScan(total: total);
      }

      // 更新进度（包含跳过的文件）
      notifier.updateProgress(
        processed: processed,
        total: total,
        currentFile: currentFile,
        phase: phase,
        filesSkipped: filesSkipped,
      );

      // 检测完成
      if (processed >= total && total > 0) {
        notifier.completeScan();
      }
    });
  };
}
