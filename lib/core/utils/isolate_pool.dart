import 'dart:async';
import 'dart:isolate';

/// 全局Isolate池，限制并发Isolate数量
///
/// 防止Isolate滥用导致的内存压力和系统资源耗尽
class IsolatePool {
  static final IsolatePool _instance = IsolatePool._internal();
  factory IsolatePool() => _instance;
  IsolatePool._internal();

  final _Semaphore _semaphore = _Semaphore(3); // 最多3个并发Isolate

  /// 在Isolate池中运行任务
  ///
  /// [task] 要在Isolate中执行的异步任务
  /// 返回任务结果
  Future<T> run<T>(Future<T> Function() task) async {
    await _semaphore.acquire();
    try {
      return await Isolate.run(() => task());
    } finally {
      _semaphore.release();
    }
  }

  /// 在Isolate池中运行同步任务
  ///
  /// [task] 要在Isolate中执行的同步任务
  /// 返回任务结果
  Future<T> runSync<T>(T Function() task) async {
    await _semaphore.acquire();
    try {
      return await Isolate.run(() => task());
    } finally {
      _semaphore.release();
    }
  }
}

/// 信号量实现，用于控制并发数量
class _Semaphore {
  final int maxCount;
  int _currentCount = 0;
  final _waitQueue = <Completer<void>>[];

  _Semaphore(this.maxCount);

  /// 获取许可，如果已达到最大并发数则等待
  Future<void> acquire() async {
    if (_currentCount < maxCount) {
      _currentCount++;
      return;
    }
    final completer = Completer<void>();
    _waitQueue.add(completer);
    await completer.future;
  }

  /// 释放许可
  void release() {
    if (_waitQueue.isNotEmpty) {
      final completer = _waitQueue.removeAt(0);
      completer.complete();
    } else {
      _currentCount--;
    }
  }
}
