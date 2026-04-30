import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/app_logger.dart';
import '../../core/utils/vibe_performance_diagnostics.dart';
import '../models/vibe/vibe_library_category.dart';
import '../models/vibe/vibe_library_entry.dart';
import '../models/vibe/vibe_reference.dart';
import 'vibe_file_storage_service.dart';

part 'vibe_library_storage_service.g.dart';

enum VibeEntryRenameError {
  invalidName,
  entryNotFound,
  nameConflict,
  filePathMissing,
  fileRenameFailed,
}

class VibeEntryRenameResult {
  const VibeEntryRenameResult._({this.entry, this.error});

  const VibeEntryRenameResult.success(VibeLibraryEntry entry)
      : this._(entry: entry);

  const VibeEntryRenameResult.failure(VibeEntryRenameError error)
      : this._(error: error);

  final VibeLibraryEntry? entry;
  final VibeEntryRenameError? error;

  bool get isSuccess => entry != null;
}

/// Vibe 库存储服务
///
/// 负责 Vibe 库条目和分类的 CRUD 操作
/// 使用 Hive 本地存储，支持搜索、筛选和使用统计
class VibeLibraryStorageService {
  static const String _entriesBoxName = 'vibe_library_entries';
  static const String _displayEntriesBoxName =
      'vibe_library_display_entries_v2';
  static const String _thumbnailCacheBoxName =
      'vibe_library_thumbnail_cache_v1';
  static const String _categoriesBoxName = 'vibe_library_categories';
  static const String _displayCacheReadyKey =
      'vibe_library_display_cache_ready_v2';
  static const int _displayThumbnailMaxDimension = 256;
  static const int _displayThumbnailInlineLimitBytes = 64 * 1024;
  static const int _displayThumbnailJpegQuality = 78;
  static const String _tag = 'VibeLibrary';

  VibeLibraryStorageService({VibeFileStorageService? fileStorage})
      : _fileStorage = fileStorage ?? VibeFileStorageService();

  Box<VibeLibraryEntry>? _entriesBox;
  LazyBox<VibeLibraryEntry>? _lazyEntriesBox;
  Box<VibeLibraryEntry>? _displayEntriesBox;
  Box<Uint8List>? _thumbnailCacheBox;
  Box<VibeLibraryCategory>? _categoriesBox;
  Future<void>? _entriesInitFuture;
  Future<void>? _lazyEntriesInitFuture;
  Future<void>? _displayEntriesInitFuture;
  Future<void>? _thumbnailCacheInitFuture;
  Future<void>? _categoriesInitFuture;
  Future<void> _thumbnailLoadQueue = Future.value();
  final Map<String, Future<Uint8List?>> _thumbnailLoadsById = {};
  final VibeFileStorageService _fileStorage;

  void _registerAdapters() {
    if (!Hive.isAdapterRegistered(23)) {
      Hive.registerAdapter(VibeLibraryEntryAdapter());
    }
    if (!Hive.isAdapterRegistered(21)) {
      Hive.registerAdapter(VibeLibraryCategoryAdapter());
    }
  }

  /// 初始化并注册 Hive adapters
  Future<void> init() async {
    await VibePerformanceDiagnostics.measure('storage.init', () async {
      _registerAdapters();
      await Future.wait([
        _ensureDisplayEntriesBox(),
        _ensureCategoriesBox(),
      ]);
      AppLogger.d('VibeLibraryStorageService initialized', 'VibeLibrary');
    });
  }

  Future<Box<VibeLibraryEntry>> _openEntriesBox() async {
    return Hive.openBox<VibeLibraryEntry>(_entriesBoxName);
  }

  Future<LazyBox<VibeLibraryEntry>> _openLazyEntriesBox() async {
    return Hive.openLazyBox<VibeLibraryEntry>(_entriesBoxName);
  }

  Future<Box<VibeLibraryEntry>> _openDisplayEntriesBox() async {
    return Hive.openBox<VibeLibraryEntry>(_displayEntriesBoxName);
  }

  Future<Box<Uint8List>> _openThumbnailCacheBox() async {
    return Hive.openBox<Uint8List>(_thumbnailCacheBoxName);
  }

  Future<Box<VibeLibraryCategory>> _openCategoriesBox() async {
    return Hive.openBox<VibeLibraryCategory>(_categoriesBoxName);
  }

  Future<void> _ensureEntriesBox() async {
    var awaitedActiveInit = false;
    var closedLazyBox = false;
    final span = VibePerformanceDiagnostics.start(
      'storage.ensureEntriesBox',
      details: {
        'hadEntriesBox': _entriesBox?.isOpen == true,
        'hadLazyBox': _lazyEntriesBox?.isOpen == true,
      },
    );
    try {
      if (_entriesBox != null && _entriesBox!.isOpen) {
        return;
      }

      if (_lazyEntriesBox != null && _lazyEntriesBox!.isOpen) {
        closedLazyBox = true;
        await _lazyEntriesBox!.close();
        _lazyEntriesBox = null;
      }

      _registerAdapters();
      final activeInit = _entriesInitFuture;
      if (activeInit != null) {
        awaitedActiveInit = true;
        await activeInit;
        return;
      }

      final initFuture = _openEntriesBox().then((box) {
        _entriesBox = box;
      });
      _entriesInitFuture = initFuture;
      try {
        await initFuture;
      } catch (e, stackTrace) {
        AppLogger.e('VibeLibrary entries 初始化失败', e, stackTrace, _tag);
        rethrow;
      } finally {
        if (identical(_entriesInitFuture, initFuture)) {
          _entriesInitFuture = null;
        }
      }
    } finally {
      span.finish(
        details: {
          'awaitedActiveInit': awaitedActiveInit,
          'closedLazyBox': closedLazyBox,
          'entriesBoxOpen': _entriesBox?.isOpen == true,
        },
      );
    }
  }

  Future<void> _ensureLazyEntriesBox() async {
    var awaitedActiveInit = false;
    final span = VibePerformanceDiagnostics.start(
      'storage.ensureLazyEntriesBox',
      details: {
        'hadEntriesBox': _entriesBox?.isOpen == true,
        'hadLazyBox': _lazyEntriesBox?.isOpen == true,
      },
    );
    try {
      if (_entriesBox != null && _entriesBox!.isOpen) {
        return;
      }
      if (_lazyEntriesBox != null && _lazyEntriesBox!.isOpen) {
        return;
      }

      _registerAdapters();
      final activeInit = _lazyEntriesInitFuture;
      if (activeInit != null) {
        awaitedActiveInit = true;
        await activeInit;
        return;
      }

      final initFuture = _openLazyEntriesBox().then((box) {
        _lazyEntriesBox = box;
      });
      _lazyEntriesInitFuture = initFuture;
      try {
        await initFuture;
      } catch (e, stackTrace) {
        AppLogger.e('VibeLibrary lazy entries 初始化失败', e, stackTrace, _tag);
        rethrow;
      } finally {
        if (identical(_lazyEntriesInitFuture, initFuture)) {
          _lazyEntriesInitFuture = null;
        }
      }
    } finally {
      span.finish(
        details: {
          'awaitedActiveInit': awaitedActiveInit,
          'entriesBoxOpen': _entriesBox?.isOpen == true,
          'lazyBoxOpen': _lazyEntriesBox?.isOpen == true,
        },
      );
    }
  }

  Future<void> _ensureDisplayEntriesBox() async {
    var awaitedActiveInit = false;
    final span = VibePerformanceDiagnostics.start(
      'storage.ensureDisplayEntriesBox',
      details: {
        'hadDisplayBox': _displayEntriesBox?.isOpen == true,
      },
    );
    try {
      if (_displayEntriesBox != null && _displayEntriesBox!.isOpen) {
        return;
      }

      _registerAdapters();
      final activeInit = _displayEntriesInitFuture;
      if (activeInit != null) {
        awaitedActiveInit = true;
        await activeInit;
        return;
      }

      final initFuture = _openDisplayEntriesBox().then((box) {
        _displayEntriesBox = box;
      });
      _displayEntriesInitFuture = initFuture;
      try {
        await initFuture;
      } catch (e, stackTrace) {
        AppLogger.e('VibeLibrary display cache 初始化失败', e, stackTrace, _tag);
        rethrow;
      } finally {
        if (identical(_displayEntriesInitFuture, initFuture)) {
          _displayEntriesInitFuture = null;
        }
      }
    } finally {
      span.finish(
        details: {
          'awaitedActiveInit': awaitedActiveInit,
          'displayBoxOpen': _displayEntriesBox?.isOpen == true,
        },
      );
    }
  }

  Future<void> _ensureThumbnailCacheBox() async {
    var awaitedActiveInit = false;
    final span = VibePerformanceDiagnostics.start(
      'storage.ensureThumbnailCacheBox',
      details: {
        'hadThumbnailCacheBox': _thumbnailCacheBox?.isOpen == true,
      },
    );
    try {
      if (_thumbnailCacheBox != null && _thumbnailCacheBox!.isOpen) {
        return;
      }

      _registerAdapters();
      final activeInit = _thumbnailCacheInitFuture;
      if (activeInit != null) {
        awaitedActiveInit = true;
        await activeInit;
        return;
      }

      final initFuture = _openThumbnailCacheBox().then((box) {
        _thumbnailCacheBox = box;
      });
      _thumbnailCacheInitFuture = initFuture;
      try {
        await initFuture;
      } catch (e, stackTrace) {
        AppLogger.e(
          'VibeLibrary thumbnail cache 初始化失败',
          e,
          stackTrace,
          _tag,
        );
        rethrow;
      } finally {
        if (identical(_thumbnailCacheInitFuture, initFuture)) {
          _thumbnailCacheInitFuture = null;
        }
      }
    } finally {
      span.finish(
        details: {
          'awaitedActiveInit': awaitedActiveInit,
          'thumbnailCacheBoxOpen': _thumbnailCacheBox?.isOpen == true,
        },
      );
    }
  }

  Future<void> _ensureCategoriesBox() async {
    var awaitedActiveInit = false;
    final span = VibePerformanceDiagnostics.start(
      'storage.ensureCategoriesBox',
      details: {
        'hadCategoriesBox': _categoriesBox?.isOpen == true,
      },
    );
    try {
      if (_categoriesBox != null && _categoriesBox!.isOpen) {
        return;
      }

      _registerAdapters();
      final activeInit = _categoriesInitFuture;
      if (activeInit != null) {
        awaitedActiveInit = true;
        await activeInit;
        return;
      }

      final initFuture = _openCategoriesBox().then((box) {
        _categoriesBox = box;
      });
      _categoriesInitFuture = initFuture;
      try {
        await initFuture;
      } catch (e, stackTrace) {
        AppLogger.e('VibeLibrary categories 初始化失败', e, stackTrace, _tag);
        rethrow;
      } finally {
        if (identical(_categoriesInitFuture, initFuture)) {
          _categoriesInitFuture = null;
        }
      }
    } finally {
      span.finish(
        details: {
          'awaitedActiveInit': awaitedActiveInit,
          'categoriesBoxOpen': _categoriesBox?.isOpen == true,
        },
      );
    }
  }

  /// 确保完整条目和分类 Box 已初始化（线程安全）。
  Future<void> _ensureInit() async {
    await VibePerformanceDiagnostics.measure('storage.ensureInit', () async {
      await Future.wait([
        _ensureEntriesBox(),
        _ensureCategoriesBox(),
      ]);
    });
  }

  Future<bool> _isDisplayCacheReady() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_displayCacheReadyKey) == true;
  }

  Future<void> _setDisplayCacheReady(bool ready) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_displayCacheReadyKey, ready);
  }

  Future<void> _upsertDisplayEntryIfReady(VibeLibraryEntry entry) async {
    if (!await _isDisplayCacheReady()) {
      return;
    }

    await _ensureDisplayEntriesBox();
    await _displayEntriesBox!.put(entry.id, entry.toDisplayEntry());
  }

  Future<void> _deleteDisplayEntryIfReady(String id) async {
    if (!await _isDisplayCacheReady()) {
      return;
    }

    await _ensureDisplayEntriesBox();
    await _displayEntriesBox!.delete(id);
  }

  Future<void> _deleteDisplayThumbnailCache(String id) async {
    await _ensureThumbnailCacheBox();
    await _thumbnailCacheBox!.delete(id);
  }

  static Uint8List? _resizeDisplayThumbnailSync(Uint8List sourceBytes) {
    final source = img.decodeImage(sourceBytes);
    if (source == null) {
      return null;
    }

    final longestSide = math.max(source.width, source.height);
    if (longestSide <= _displayThumbnailMaxDimension &&
        sourceBytes.length <= _displayThumbnailInlineLimitBytes) {
      return sourceBytes;
    }

    final scale = _displayThumbnailMaxDimension / longestSide;
    final width = math.max(1, (source.width * scale).round());
    final height = math.max(1, (source.height * scale).round());
    final resized = img.copyResize(
      source,
      width: width,
      height: height,
      interpolation: img.Interpolation.average,
    );
    return Uint8List.fromList(
      img.encodeJpg(resized, quality: _displayThumbnailJpegQuality),
    );
  }

  Future<Uint8List?> _normalizeDisplayThumbnail(Uint8List sourceBytes) async {
    if (sourceBytes.isEmpty) {
      return null;
    }

    if (sourceBytes.length <= _displayThumbnailInlineLimitBytes) {
      return sourceBytes;
    }

    return Isolate.run(() => _resizeDisplayThumbnailSync(sourceBytes));
  }

  Uint8List? _pickDisplayThumbnailSource(VibeLibraryEntry entry) {
    final thumbnail = entry.thumbnail;
    if (thumbnail != null && thumbnail.isNotEmpty) {
      return thumbnail;
    }

    final vibeThumbnail = entry.vibeThumbnail;
    if (vibeThumbnail != null && vibeThumbnail.isNotEmpty) {
      return vibeThumbnail;
    }

    final previews = entry.bundledVibePreviews;
    if (previews != null && previews.isNotEmpty && previews.first.isNotEmpty) {
      return previews.first;
    }

    final rawImageData = entry.rawImageData;
    if (rawImageData != null && rawImageData.isNotEmpty) {
      return rawImageData;
    }

    return null;
  }

  Future<Uint8List?> _loadAndCacheDisplayThumbnail(String id) async {
    final span = VibePerformanceDiagnostics.start(
      'storage.loadDisplayThumbnail',
      details: {
        'id': id,
      },
    );
    var found = false;
    var cached = false;
    var sourceBytes = 0;
    var resultBytes = 0;
    try {
      await _ensureThumbnailCacheBox();
      final existing = _thumbnailCacheBox!.get(id);
      if (existing != null && existing.isNotEmpty) {
        cached = true;
        resultBytes = existing.length;
        return existing;
      }

      final entry = await _readStoredEntry(id);
      if (entry == null) {
        return null;
      }
      found = true;

      final source = _pickDisplayThumbnailSource(entry);
      if (source == null) {
        return null;
      }
      sourceBytes = source.length;

      final thumbnail = await _normalizeDisplayThumbnail(source);
      if (thumbnail == null || thumbnail.isEmpty) {
        return null;
      }

      resultBytes = thumbnail.length;
      await _thumbnailCacheBox!.put(id, thumbnail);
      return thumbnail;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to load display thumbnail', e, stackTrace, _tag);
      return null;
    } finally {
      span.finish(
        details: {
          'found': found,
          'cached': cached,
          'sourceBytes': sourceBytes,
          'resultBytes': resultBytes,
        },
      );
    }
  }

  Future<Uint8List?> _queueDisplayThumbnailLoad(String id) {
    final queued = _thumbnailLoadQueue.then(
      (_) => _loadAndCacheDisplayThumbnail(id),
    );
    _thumbnailLoadQueue = queued.then<void>(
      (_) {},
      onError: (_) {},
    );
    return queued;
  }

  /// 按需读取列表缩略图。
  ///
  /// 列表展示缓存本身不再携带图片字节，避免打开 Vibe 库时一次性加载
  /// 大量缩略图。卡片可调用该方法串行生成/读取小缩略图缓存。
  Future<Uint8List?> getDisplayThumbnail(String id) async {
    await _ensureThumbnailCacheBox();
    final cached = _thumbnailCacheBox!.get(id);
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    final activeLoad = _thumbnailLoadsById[id];
    if (activeLoad != null) {
      return activeLoad;
    }

    final load = _queueDisplayThumbnailLoad(id);
    _thumbnailLoadsById[id] = load;
    try {
      return await load;
    } finally {
      if (identical(_thumbnailLoadsById[id], load)) {
        _thumbnailLoadsById.remove(id);
      }
    }
  }

  Future<List<VibeLibraryEntry>> _rebuildDisplayEntriesCache() async {
    final span = VibePerformanceDiagnostics.start(
      'storage.rebuildDisplayEntriesCache',
    );
    var entryCount = 0;
    try {
      await _ensureDisplayEntriesBox();

      final displayEntries = <VibeLibraryEntry>[];
      await _forEachStoredEntryLazily((entry) async {
        displayEntries.add(entry.toDisplayEntry());

        // Hive lazy reads still decode the entry payload. Yield periodically so
        // the first library open can keep painting instead of monopolizing UI.
        await Future<void>.delayed(Duration.zero);
      });

      final entriesById = {
        for (final entry in displayEntries) entry.id: entry,
      };

      await _displayEntriesBox!.clear();
      if (entriesById.isNotEmpty) {
        await _displayEntriesBox!.putAll(entriesById);
      }
      await _setDisplayCacheReady(true);

      entryCount = displayEntries.length;
      AppLogger.i(
        'Vibe display cache rebuilt: ${displayEntries.length} entries',
        _tag,
      );
      return displayEntries;
    } finally {
      span.finish(
        details: {
          'entries': entryCount,
        },
      );
    }
  }

  Future<VibeLibraryEntry?> _readStoredEntry(String id) async {
    if (_entriesBox != null && _entriesBox!.isOpen) {
      return _entriesBox!.get(id);
    }

    await _ensureLazyEntriesBox();
    return _lazyEntriesBox!.get(id);
  }

  Future<void> _putStoredEntry(VibeLibraryEntry entry) async {
    if (_entriesBox != null && _entriesBox!.isOpen) {
      await _entriesBox!.put(entry.id, entry);
      return;
    }

    await _ensureLazyEntriesBox();
    await _lazyEntriesBox!.put(entry.id, entry);
  }

  Future<void> _deleteStoredEntry(String id) async {
    if (_entriesBox != null && _entriesBox!.isOpen) {
      await _entriesBox!.delete(id);
      return;
    }

    await _ensureLazyEntriesBox();
    await _lazyEntriesBox!.delete(id);
  }

  Future<void> _clearStoredEntries() async {
    if (_entriesBox != null && _entriesBox!.isOpen) {
      await _entriesBox!.clear();
      return;
    }

    await _ensureLazyEntriesBox();
    await _lazyEntriesBox!.clear();
  }

  Future<void> _forEachStoredEntryLazily(
    Future<void> Function(VibeLibraryEntry entry) visit,
  ) async {
    if (_entriesBox != null && _entriesBox!.isOpen) {
      for (final entry in _entriesBox!.values) {
        await visit(entry);
      }
      return;
    }

    await _ensureLazyEntriesBox();
    final keys = _lazyEntriesBox!.keys.toList(growable: false);
    for (final key in keys) {
      final entry = await _lazyEntriesBox!.get(key);
      if (entry != null) {
        await visit(entry);
      }
    }
  }

  Future<VibeLibraryEntry?> _firstStoredEntryWhere(
    bool Function(VibeLibraryEntry entry) test,
  ) async {
    var checkedCount = 0;

    if (_entriesBox != null && _entriesBox!.isOpen) {
      for (final entry in _entriesBox!.values) {
        if (test(entry)) return entry;
        checkedCount++;
        if (checkedCount % 4 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
      return null;
    }

    await _ensureLazyEntriesBox();
    final keys = _lazyEntriesBox!.keys.toList(growable: false);
    for (final key in keys) {
      final entry = await _lazyEntriesBox!.get(key);
      if (entry != null && test(entry)) {
        return entry;
      }
      checkedCount++;
      if (checkedCount % 4 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    return null;
  }

  bool _bytesEqual(Uint8List? left, Uint8List? right) {
    if (identical(left, right)) return true;
    if (left == null || right == null) return false;
    if (left.length != right.length) return false;

    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  Future<VibeLibraryEntry?> findMatchingEntry(VibeReference vibe) async {
    return VibePerformanceDiagnostics.measure(
      'storage.findMatchingEntry',
      () async {
        if (vibe.vibeEncoding.isNotEmpty) {
          final match = await _firstStoredEntryWhere((entry) {
            return entry.vibeEncoding.isNotEmpty &&
                entry.vibeEncoding == vibe.vibeEncoding;
          });
          if (match != null) return match;
        }

        final thumbnail = vibe.thumbnail;
        if (thumbnail != null && thumbnail.isNotEmpty) {
          return _firstStoredEntryWhere((entry) {
            return entry.hasThumbnail &&
                _bytesEqual(entry.thumbnail, thumbnail);
          });
        }

        return null;
      },
      details: {
        'hasEncoding': vibe.vibeEncoding.isNotEmpty,
        'hasThumbnail': vibe.thumbnail?.isNotEmpty == true,
      },
      resultDetails: (entry) => {
        'found': entry != null,
      },
    );
  }

  Future<VibeLibraryEntry?> findOverwriteCandidate(
    List<VibeReference> vibes,
  ) async {
    return VibePerformanceDiagnostics.measure(
      'storage.findOverwriteCandidate',
      () async {
        if (vibes.length != 1) {
          return null;
        }

        final vibe = vibes.single;
        return _firstStoredEntryWhere((entry) {
          final sameDisplayName = entry.displayName == vibe.displayName;
          final sameEncoding = entry.vibeEncoding == vibe.vibeEncoding;
          final sameRawImage =
              _bytesEqual(entry.rawImageData, vibe.rawImageData);
          return sameDisplayName && (sameEncoding || sameRawImage);
        });
      },
      details: {
        'vibes': vibes.length,
      },
      resultDetails: (entry) => {
        'found': entry != null,
      },
    );
  }

  Future<VibeLibraryEntry?> findEntryByName(String name) async {
    return VibePerformanceDiagnostics.measure(
      'storage.findEntryByName',
      () async {
        final normalizedName = name.trim().toLowerCase();
        if (normalizedName.isEmpty) {
          return null;
        }

        return _firstStoredEntryWhere((entry) {
          return entry.name.trim().toLowerCase() == normalizedName;
        });
      },
      details: {
        'hasName': name.trim().isNotEmpty,
      },
      resultDetails: (entry) => {
        'found': entry != null,
      },
    );
  }

  // ==================== Entry CRUD ====================

  /// 保存条目（新增或更新）
  Future<VibeLibraryEntry> saveEntry(VibeLibraryEntry entry) async {
    try {
      var entryToSave = entry;
      final filePath = entryToSave.filePath;
      if (filePath == null || filePath.isEmpty) {
        entryToSave = await _saveEntryFile(entryToSave);
      }

      await _putStoredEntry(entryToSave);
      await _upsertDisplayEntryIfReady(entryToSave);
      await _deleteDisplayThumbnailCache(entryToSave.id);
      AppLogger.d('Entry saved: ${entryToSave.displayName}', _tag);
      return entryToSave;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to save entry', e, stackTrace, _tag);
      rethrow;
    }
  }

  /// 显式保存条目参数。
  ///
  /// 仅在用户明确点击“保存参数”时调用；若条目绑定了单个 Vibe 文件，
  /// 会同步把文件里的 importInfo 一起更新，避免重新打开时被旧文件参数覆盖。
  Future<VibeLibraryEntry?> saveEntryParams(
    String id, {
    required double strength,
    required double infoExtracted,
    VibeReference? persistedVibeData,
  }) async {
    try {
      final entry = await _readStoredEntry(id);
      if (entry == null) return null;

      final updatedEntry = persistedVibeData != null
          ? entry.updateVibeData(persistedVibeData)
          : entry.updateStrength(strength).updateInfoExtracted(infoExtracted);

      final filePath = updatedEntry.filePath;
      if (!updatedEntry.isBundle && filePath != null && filePath.isNotEmpty) {
        await _fileStorage.overwriteVibeFile(
          filePath,
          updatedEntry.toVibeReference(),
          displayName: updatedEntry.displayName,
        );
      }

      await _putStoredEntry(updatedEntry);
      await _upsertDisplayEntryIfReady(updatedEntry);
      await _deleteDisplayThumbnailCache(updatedEntry.id);
      return await getEntry(updatedEntry.id) ?? updatedEntry;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to save entry params', e, stackTrace, _tag);
      rethrow;
    }
  }

  /// 保存 Bundle 条目（新增或更新）
  Future<VibeLibraryEntry> saveBundleEntry(
    List<VibeReference> vibes, {
    required String name,
    String? categoryId,
    List<String>? tags,
  }) async {
    try {
      if (vibes.isEmpty) throw ArgumentError('vibes cannot be empty');

      final filePath =
          await _fileStorage.saveBundleToFile(vibes, bundleName: name);
      final entry = VibeLibraryEntry.fromVibeReference(
        name: p.basenameWithoutExtension(filePath),
        vibeData: vibes.first,
        categoryId: categoryId,
        tags: tags,
        filePath: filePath,
      ).copyWith(
        bundleId: p.basenameWithoutExtension(filePath),
        bundledVibeNames: vibes.map((v) => v.displayName).toList(),
        bundledVibePreviews: () {
          final previews = vibes
              .where((v) => v.thumbnail != null)
              .take(4)
              .map((v) => v.thumbnail!)
              .toList();
          return previews.isEmpty ? null : previews;
        }(),
        bundledVibeEncodings: vibes.map((v) => v.vibeEncoding).toList(),
      );

      await _putStoredEntry(entry);
      await _upsertDisplayEntryIfReady(entry);
      await _deleteDisplayThumbnailCache(entry.id);
      AppLogger.d('Bundle entry saved: ${entry.displayName}', _tag);
      return entry;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to save bundle entry', e, stackTrace, _tag);
      rethrow;
    }
  }

  /// 根据 ID 获取条目
  Future<VibeLibraryEntry?> getEntry(String id) async {
    final span = VibePerformanceDiagnostics.start(
      'storage.getEntry',
      details: {
        'id': id,
      },
    );
    var found = false;
    var hasFile = false;
    var fileLoaded = false;
    var fileMissing = false;
    var isBundle = false;
    var previewsLoaded = false;
    try {
      final entry = await _readStoredEntry(id);
      if (entry == null) return null;
      found = true;
      isBundle = entry.isBundle;

      final filePath = entry.filePath;
      if (filePath == null || filePath.isEmpty) return entry;
      hasFile = true;

      final vibeData = await _fileStorage.loadVibeFromFile(filePath);
      if (vibeData == null) {
        fileMissing = true;
        AppLogger.w('Entry file missing or invalid: $filePath', _tag);
        return null;
      }
      fileLoaded = true;

      // 旧库里存在“文件只保存编码，原图仍只留在 Hive 条目里”的情况。
      // 回读文件时要保住这份原图来源，否则条目会意外失去重新编码能力。
      final effectiveThumbnail =
          vibeData.thumbnail ?? entry.vibeThumbnail ?? entry.thumbnail;
      final effectiveRawImageData = vibeData.rawImageData ?? entry.rawImageData;
      var mergedEntry = entry
          .updateVibeData(
            vibeData.copyWith(
              thumbnail: effectiveThumbnail,
              rawImageData: effectiveRawImageData,
            ),
          )
          .copyWith(filePath: filePath);
      if (entry.isBundle) {
        final previews = await _fileStorage.extractPreviewsFromBundle(filePath);
        if (previews.isNotEmpty) {
          previewsLoaded = true;
          mergedEntry = mergedEntry.copyWith(bundledVibePreviews: previews);
        }
      }

      return mergedEntry;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to get entry', e, stackTrace, _tag);
      return null;
    } finally {
      span.finish(
        details: {
          'found': found,
          'hasFile': hasFile,
          'fileLoaded': fileLoaded,
          'fileMissing': fileMissing,
          'isBundle': isBundle,
          'previewsLoaded': previewsLoaded,
        },
      );
    }
  }

  /// 获取所有条目
  Future<List<VibeLibraryEntry>> getAllEntries() async {
    return VibePerformanceDiagnostics.measure(
      'storage.getAllEntries',
      () async {
        await _ensureInit();
        try {
          final entries = _entriesBox!.values.toList(growable: false);
          return Future.wait(
            entries.map(_resolveEntryDisplayParams),
          );
        } catch (e, stackTrace) {
          AppLogger.e(
            'Failed to get all entries: $e',
            'VibeLibrary',
            stackTrace,
          );
          return [];
        }
      },
      resultDetails: (entries) => {
        'entries': entries.length,
      },
    );
  }

  /// 获取展示列表用的轻量条目。
  ///
  /// 该路径不会读取或解析每个 .naiv4vibe/.naiv4vibebundle 文件，也不会把
  /// vibeEncoding、rawImageData、bundle encodings 等重负载放进 UI 状态。
  /// 需要真正导入、导出、编辑时，再通过 getEntry(id) 按需读取完整数据。
  Future<List<VibeLibraryEntry>> getDisplayEntries() async {
    final span = VibePerformanceDiagnostics.start('storage.getDisplayEntries');
    var cacheReady = false;
    var rebuilt = false;
    var entryCount = 0;
    try {
      await _ensureDisplayEntriesBox();
      cacheReady = await _isDisplayCacheReady();
      if (cacheReady) {
        final entries = _displayEntriesBox!.values.toList(growable: false);
        entryCount = entries.length;
        return entries;
      }

      rebuilt = true;
      final entries = await _rebuildDisplayEntriesCache();
      entryCount = entries.length;
      return entries;
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to get display entries: $e',
        'VibeLibrary',
        stackTrace,
      );
      return [];
    } finally {
      span.finish(
        details: {
          'cacheReady': cacheReady,
          'rebuilt': rebuilt,
          'entries': entryCount,
        },
      );
    }
  }

  /// 根据分类 ID 获取条目
  Future<List<VibeLibraryEntry>> getEntriesByCategory(
    String? categoryId,
  ) async {
    final entries = await getAllEntries();
    return entries.where((entry) => entry.categoryId == categoryId).toList();
  }

  Future<VibeLibraryEntry> _resolveEntryDisplayParams(
    VibeLibraryEntry entry,
  ) async {
    final filePath = entry.filePath;
    if (filePath == null || filePath.isEmpty) {
      return entry;
    }

    final storedParams = await _fileStorage.loadImportParams(filePath);
    if (storedParams == null) {
      return entry;
    }

    if (entry.strength == storedParams.strength &&
        entry.infoExtracted == storedParams.infoExtracted) {
      return entry;
    }

    return entry.copyWith(
      strength: storedParams.strength,
      infoExtracted: storedParams.infoExtracted,
    );
  }

  /// 删除条目
  ///
  /// 注意：即使文件删除失败，也会删除 Hive 条目以保持数据一致性。
  /// 文件删除失败会被记录但不会阻止条目删除。
  Future<bool> deleteEntry(String id) async {
    try {
      final entry = await _readStoredEntry(id);
      if (entry == null) return false;

      final filePath = entry.filePath;
      if (filePath != null && filePath.isNotEmpty) {
        final fileDeleted = await _fileStorage.deleteVibeFile(filePath);
        if (!fileDeleted) {
          AppLogger.w(
            'File delete failed but continuing to delete Hive entry: $id',
            _tag,
          );
          // 不返回 false，继续删除 Hive 条目以保持数据一致性
        }
      }

      await _deleteStoredEntry(id);
      await _deleteDisplayEntryIfReady(id);
      await _deleteDisplayThumbnailCache(id);
      AppLogger.d('Entry deleted: $id', _tag);
      return true;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to delete entry', e, stackTrace, _tag);
      return false;
    }
  }

  /// 批量删除条目
  Future<int> deleteEntries(List<String> ids) async {
    var deletedCount = 0;
    try {
      for (final id in ids) {
        final deleted = await deleteEntry(id);
        if (deleted) {
          deletedCount++;
        }
      }
      AppLogger.d('Entries deleted: $deletedCount', _tag);
      return deletedCount;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to delete entries', e, stackTrace, _tag);
      return deletedCount;
    }
  }

  /// 搜索条目
  Future<List<VibeLibraryEntry>> searchEntries(String query) async {
    await _ensureInit();
    try {
      final allEntries = _entriesBox!.values.toList();
      if (query.isEmpty) return allEntries;

      final lowerQuery = query.toLowerCase();
      return allEntries.where((entry) {
        return entry.name.toLowerCase().contains(lowerQuery) ||
            entry.vibeDisplayName.toLowerCase().contains(lowerQuery) ||
            entry.tags.any((tag) => tag.toLowerCase().contains(lowerQuery));
      }).toList();
    } catch (e, stackTrace) {
      AppLogger.e('Failed to search entries: $e', 'VibeLibrary', stackTrace);
      return [];
    }
  }

  /// 获取收藏的条目
  Future<List<VibeLibraryEntry>> getFavoriteEntries() async {
    await _ensureInit();
    try {
      return _entriesBox!.values.where((entry) => entry.isFavorite).toList();
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to get favorite entries: $e',
        'VibeLibrary',
        stackTrace,
      );
      return [];
    }
  }

  /// 获取最近使用的条目（按最后使用时间排序）
  Future<List<VibeLibraryEntry>> getRecentEntries({int limit = 20}) async {
    try {
      await _ensureInit();
      final entries = _entriesBox!.values
          .where((entry) => entry.lastUsedAt != null)
          .toList();
      entries.sort((a, b) => b.lastUsedAt!.compareTo(a.lastUsedAt!));
      return entries.take(limit).toList();
    } catch (e, stackTrace) {
      AppLogger.e('Failed to get recent entries', e, stackTrace, _tag);
      return [];
    }
  }

  /// 获取最近使用的轻量展示条目（按最后使用时间排序）。
  ///
  /// 用于生成页/画布的最近列表，避免仅为了展示最近项就打开完整条目 Box。
  Future<List<VibeLibraryEntry>> getRecentDisplayEntries({
    int limit = 20,
  }) async {
    return VibePerformanceDiagnostics.measure(
      'storage.getRecentDisplayEntries',
      () async {
        final entries = await getDisplayEntries();
        final recentEntries = entries
            .where((entry) => entry.lastUsedAt != null)
            .toList(growable: false);
        recentEntries.sort((a, b) => b.lastUsedAt!.compareTo(a.lastUsedAt!));
        return recentEntries.take(limit).toList(growable: false);
      },
      details: {
        'limit': limit,
      },
      resultDetails: (entries) => {
        'entries': entries.length,
      },
    );
  }

  /// 增加使用次数
  Future<VibeLibraryEntry?> incrementUsedCount(String id) async {
    try {
      final entry = await _readStoredEntry(id);
      if (entry == null) return null;

      final updatedEntry = entry.recordUsage();
      await _putStoredEntry(updatedEntry);
      await _upsertDisplayEntryIfReady(updatedEntry);
      AppLogger.d(
        'Entry usage incremented: ${entry.displayName}',
        'VibeLibrary',
      );
      return updatedEntry;
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to increment used count: $e',
        'VibeLibrary',
        stackTrace,
      );
      return null;
    }
  }

  /// 切换收藏状态
  Future<VibeLibraryEntry?> toggleFavorite(String id) async {
    try {
      final entry = await _readStoredEntry(id);
      if (entry == null) return null;

      final updatedEntry = entry.toggleFavorite();
      await _putStoredEntry(updatedEntry);
      await _upsertDisplayEntryIfReady(updatedEntry);
      AppLogger.d(
        'Entry favorite toggled: ${entry.displayName}',
        'VibeLibrary',
      );
      return updatedEntry;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to toggle favorite: $e', 'VibeLibrary', stackTrace);
      return null;
    }
  }

  /// 更新条目分类
  Future<VibeLibraryEntry?> updateEntryCategory(
    String id,
    String? categoryId,
  ) async {
    try {
      final entry = await _readStoredEntry(id);
      if (entry == null) return null;

      final updatedEntry = entry.copyWith(categoryId: categoryId);
      await _putStoredEntry(updatedEntry);
      await _upsertDisplayEntryIfReady(updatedEntry);
      AppLogger.d(
        'Entry category updated: ${entry.displayName}',
        'VibeLibrary',
      );
      return updatedEntry;
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to update entry category: $e',
        'VibeLibrary',
        stackTrace,
      );
      return null;
    }
  }

  /// 更新条目标签
  Future<VibeLibraryEntry?> updateEntryTags(
    String id,
    List<String> tags,
  ) async {
    try {
      final entry = await _readStoredEntry(id);
      if (entry == null) return null;

      final updatedEntry = entry.copyWith(tags: tags);
      await _putStoredEntry(updatedEntry);
      await _upsertDisplayEntryIfReady(updatedEntry);
      AppLogger.d('Entry tags updated: ${entry.displayName}', 'VibeLibrary');
      return updatedEntry;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to update entry tags: $e', 'VibeLibrary', stackTrace);
      return null;
    }
  }

  /// 更新条目缩略图
  Future<VibeLibraryEntry?> updateEntryThumbnail(
    String id,
    Uint8List? thumbnail,
  ) async {
    try {
      final entry = await _readStoredEntry(id);
      if (entry == null) return null;

      final updatedEntry = entry.copyWith(thumbnail: thumbnail);
      await _putStoredEntry(updatedEntry);
      await _upsertDisplayEntryIfReady(updatedEntry);
      await _deleteDisplayThumbnailCache(id);
      AppLogger.d(
        'Entry thumbnail updated: ${entry.displayName}',
        'VibeLibrary',
      );
      return updatedEntry;
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to update entry thumbnail: $e',
        'VibeLibrary',
        stackTrace,
      );
      return null;
    }
  }

  /// 获取条目数量
  Future<int> getEntriesCount() async {
    await _ensureInit();
    try {
      return _entriesBox!.length;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to get entries count: $e', 'VibeLibrary', stackTrace);
      return 0;
    }
  }

  /// 获取指定分类的条目数量
  Future<int> getEntriesCountByCategory(String? categoryId) async {
    await _ensureInit();
    try {
      return _entriesBox!.values
          .where((entry) => entry.categoryId == categoryId)
          .length;
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to get entries count by category: $e',
        'VibeLibrary',
        stackTrace,
      );
      return 0;
    }
  }

  /// 检查条目是否存在
  Future<bool> entryExists(String id) async {
    try {
      if (_entriesBox != null && _entriesBox!.isOpen) {
        return _entriesBox!.containsKey(id);
      }

      await _ensureLazyEntriesBox();
      return _lazyEntriesBox!.containsKey(id);
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to check entry existence: $e',
        'VibeLibrary',
        stackTrace,
      );
      return false;
    }
  }

  /// 清除所有条目
  Future<void> clearAllEntries() async {
    try {
      await _clearStoredEntries();
      await _ensureDisplayEntriesBox();
      await _displayEntriesBox!.clear();
      await _ensureThumbnailCacheBox();
      await _thumbnailCacheBox!.clear();
      await _setDisplayCacheReady(true);
      AppLogger.i('All entries cleared', 'VibeLibrary');
    } catch (e, stackTrace) {
      AppLogger.e('Failed to clear all entries: $e', 'VibeLibrary', stackTrace);
      rethrow;
    }
  }

  /// 扫描文件夹并同步到 Hive
  Future<VibeFolderSyncResult> syncWithFileSystem({
    bool removeMissingEntries = true,
  }) async {
    final span = VibePerformanceDiagnostics.start(
      'storage.syncWithFileSystem',
      details: {
        'removeMissingEntries': removeMissingEntries,
      },
    );
    VibeFolderSyncResult? syncResult;
    try {
      await _ensureInit();
      final existingEntries = _entriesBox!.values.toList(growable: false);

      final result = await _fileStorage.syncFolderToHive(
        existingEntries: existingEntries,
        onUpsertEntry: (entry) async {
          await _entriesBox!.put(entry.id, entry);
          await _upsertDisplayEntryIfReady(entry);
          await _deleteDisplayThumbnailCache(entry.id);
        },
        onDeleteEntry: removeMissingEntries
            ? (entry) async {
                await _entriesBox!.delete(entry.id);
                await _deleteDisplayEntryIfReady(entry.id);
                await _deleteDisplayThumbnailCache(entry.id);
              }
            : null,
      );
      syncResult = result;

      AppLogger.i(
        'File system sync completed: scanned=${result.scannedCount}, '
        'upserted=${result.upsertedCount}, deleted=${result.deletedCount}, '
        'failed=${result.failedCount}',
        _tag,
      );
      return result;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to sync with file system', e, stackTrace, _tag);
      return VibeFolderSyncResult(
        scannedCount: 0,
        upsertedCount: 0,
        deletedCount: 0,
        failedCount: 1,
        errors: [e.toString()],
      );
    } finally {
      span.finish(
        details: {
          'scanned': syncResult?.scannedCount,
          'upserted': syncResult?.upsertedCount,
          'deleted': syncResult?.deletedCount,
          'failed': syncResult?.failedCount,
        },
      );
    }
  }

  /// 重命名条目文件并更新路径
  Future<VibeLibraryEntry?> updateEntryFile(String id, String newName) async {
    try {
      final entry = await _readStoredEntry(id);
      if (entry == null) {
        return null;
      }

      final filePath = entry.filePath;
      if (filePath == null || filePath.isEmpty) {
        AppLogger.w('Skip renaming entry without filePath: $id', _tag);
        return null;
      }

      final renamedPath = await _fileStorage.renameVibeFile(filePath, newName);
      if (renamedPath == null) {
        return null;
      }

      final updatedEntry = entry.copyWith(
        name: newName.trim(),
        filePath: renamedPath,
      );
      await _putStoredEntry(updatedEntry);
      await _upsertDisplayEntryIfReady(updatedEntry);
      AppLogger.d('Entry file renamed: $filePath -> $renamedPath', _tag);
      return updatedEntry;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to update entry file', e, stackTrace, _tag);
      return null;
    }
  }

  /// 重命名条目名称，并同步重命名文件后更新条目路径
  Future<VibeEntryRenameResult> renameEntry(
    String entryId,
    String newName,
  ) async {
    try {
      final trimmedName = newName.trim();
      if (trimmedName.isEmpty) {
        return const VibeEntryRenameResult.failure(
          VibeEntryRenameError.invalidName,
        );
      }

      final entry = await _readStoredEntry(entryId);
      if (entry == null) {
        return const VibeEntryRenameResult.failure(
          VibeEntryRenameError.entryNotFound,
        );
      }

      var hasConflict = false;
      await _forEachStoredEntryLazily((candidate) async {
        if (candidate.id != entryId &&
            candidate.name.trim().toLowerCase() == trimmedName.toLowerCase()) {
          hasConflict = true;
        }
      });
      if (hasConflict) {
        return const VibeEntryRenameResult.failure(
          VibeEntryRenameError.nameConflict,
        );
      }

      final filePath = entry.filePath;
      if (filePath == null || filePath.isEmpty) {
        return const VibeEntryRenameResult.failure(
          VibeEntryRenameError.filePathMissing,
        );
      }

      final renamedPath =
          await _fileStorage.renameVibeFile(filePath, trimmedName);
      if (renamedPath == null) {
        return const VibeEntryRenameResult.failure(
          VibeEntryRenameError.fileRenameFailed,
        );
      }

      final updatedEntry =
          entry.copyWith(name: trimmedName, filePath: renamedPath);
      await _putStoredEntry(updatedEntry);
      await _upsertDisplayEntryIfReady(updatedEntry);
      AppLogger.d('Entry renamed: $filePath -> $renamedPath', _tag);
      return VibeEntryRenameResult.success(updatedEntry);
    } catch (e, stackTrace) {
      AppLogger.e('Failed to rename entry', e, stackTrace, _tag);
      return const VibeEntryRenameResult.failure(
        VibeEntryRenameError.fileRenameFailed,
      );
    }
  }

  /// 更新 bundle 预览缓存
  Future<VibeLibraryEntry?> updateEntryPreviews(
    String id, {
    int maxCount = 4,
  }) async {
    try {
      final entry = await _readStoredEntry(id);
      if (entry == null) {
        return null;
      }

      final filePath = entry.filePath;
      if (filePath == null || filePath.isEmpty || !entry.isBundle) {
        return entry;
      }

      final previews = await _fileStorage.extractPreviewsFromBundle(
        filePath,
        maxCount: maxCount,
      );
      final updatedEntry = entry.copyWith(bundledVibePreviews: previews);
      await _putStoredEntry(updatedEntry);
      await _upsertDisplayEntryIfReady(updatedEntry);
      AppLogger.d('Entry previews updated: ${entry.displayName}', _tag);
      return updatedEntry;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to update entry previews', e, stackTrace, _tag);
      return null;
    }
  }

  Future<VibeLibraryEntry> _saveEntryFile(VibeLibraryEntry entry) async {
    try {
      final vibeData = entry.toVibeReference();
      final savedPath = entry.isBundle
          ? await _fileStorage.saveBundleToFile(
              _buildBundleVibeReferences(entry),
              bundleName: entry.name,
            )
          : await _fileStorage.saveVibeToFile(
              vibeData,
              customName: entry.name,
            );

      if (savedPath.isEmpty) {
        throw StateError('Saved vibe file path is empty');
      }

      // 从实际保存的文件路径提取文件名（不含扩展名），确保 name 与文件名一致
      final actualFileName = p.basenameWithoutExtension(savedPath);

      return entry.copyWith(
        filePath: savedPath,
        name: actualFileName,
      );
    } catch (e, stackTrace) {
      AppLogger.e('Failed to save entry file', e, stackTrace, _tag);
      rethrow;
    }
  }

  /// 构建 bundle 中所有 vibes 的 VibeReference 列表
  List<VibeReference> _buildBundleVibeReferences(VibeLibraryEntry entry) {
    final encodings = entry.bundledVibeEncodings;
    final names = entry.bundledVibeNames;
    final previews = entry.bundledVibePreviews;

    if (encodings == null || encodings.isEmpty) {
      // 如果没有存储编码列表，只返回第一个 vibe
      return [entry.toVibeReference()];
    }

    final results = <VibeReference>[];
    for (var i = 0; i < encodings.length; i++) {
      final encoding = encodings[i];
      final name =
          names != null && i < names.length ? names[i] : '${entry.name}#$i';
      final thumbnail =
          previews != null && i < previews.length ? previews[i] : null;

      results.add(
        VibeReference(
          displayName: name,
          vibeEncoding: encoding,
          thumbnail: thumbnail,
          strength: entry.strength,
          infoExtracted: entry.infoExtracted,
          sourceType: VibeSourceType.naiv4vibebundle,
        ),
      );
    }

    return results;
  }

  // ==================== Category CRUD ====================

  /// 保存分类（新增或更新）
  Future<VibeLibraryCategory> saveCategory(VibeLibraryCategory category) async {
    await _ensureCategoriesBox();
    try {
      await _categoriesBox!.put(category.id, category);
      AppLogger.d('Category saved: ${category.name}', 'VibeLibrary');
      return category;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to save category: $e', 'VibeLibrary', stackTrace);
      rethrow;
    }
  }

  /// 根据 ID 获取分类
  Future<VibeLibraryCategory?> getCategory(String id) async {
    await _ensureCategoriesBox();
    try {
      return _categoriesBox!.get(id);
    } catch (e, stackTrace) {
      AppLogger.e('Failed to get category: $e', 'VibeLibrary', stackTrace);
      return null;
    }
  }

  /// 获取所有分类
  Future<List<VibeLibraryCategory>> getAllCategories() async {
    await _ensureCategoriesBox();
    try {
      return _categoriesBox!.values.toList();
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to get all categories: $e',
        'VibeLibrary',
        stackTrace,
      );
      return [];
    }
  }

  /// 获取根级分类
  Future<List<VibeLibraryCategory>> getRootCategories() async {
    await _ensureCategoriesBox();
    try {
      return _categoriesBox!.values
          .where((category) => category.parentId == null)
          .toList();
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to get root categories: $e',
        'VibeLibrary',
        stackTrace,
      );
      return [];
    }
  }

  /// 获取子分类
  Future<List<VibeLibraryCategory>> getChildCategories(String parentId) async {
    await _ensureCategoriesBox();
    try {
      return _categoriesBox!.values
          .where((category) => category.parentId == parentId)
          .toList();
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to get child categories: $e',
        'VibeLibrary',
        stackTrace,
      );
      return [];
    }
  }

  /// 删除分类
  ///
  /// [moveEntriesToParent] 如果为 true，将分类下的条目移动到父分类；
  /// 如果为 false，将条目设为无分类（categoryId = null）
  Future<bool> deleteCategory(
    String id, {
    bool moveEntriesToParent = true,
  }) async {
    await Future.wait([
      _ensureEntriesBox(),
      _ensureCategoriesBox(),
    ]);
    try {
      final category = _categoriesBox!.get(id);
      if (category == null) return false;

      // 更新该分类下的条目
      final entriesInCategory = await getEntriesByCategory(id);
      for (final entry in entriesInCategory) {
        if (moveEntriesToParent && category.parentId != null) {
          await updateEntryCategory(entry.id, category.parentId);
        } else {
          await updateEntryCategory(entry.id, null);
        }
      }

      // 更新子分类的 parentId
      final childCategories = await getChildCategories(id);
      for (final child in childCategories) {
        final updatedChild = child.moveTo(category.parentId);
        await saveCategory(updatedChild);
      }

      await _categoriesBox!.delete(id);
      AppLogger.d('Category deleted: ${category.name}', 'VibeLibrary');
      return true;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to delete category: $e', 'VibeLibrary', stackTrace);
      return false;
    }
  }

  /// 批量删除分类
  Future<int> deleteCategories(List<String> ids) async {
    await _ensureCategoriesBox();
    var deletedCount = 0;
    try {
      for (final id in ids) {
        if (await deleteCategory(id)) {
          deletedCount++;
        }
      }
      AppLogger.d('Categories deleted: $deletedCount', 'VibeLibrary');
      return deletedCount;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to delete categories: $e', 'VibeLibrary', stackTrace);
      return deletedCount;
    }
  }

  /// 更新分类名称
  Future<VibeLibraryCategory?> updateCategoryName(
    String id,
    String newName,
  ) async {
    await _ensureCategoriesBox();
    try {
      final category = _categoriesBox!.get(id);
      if (category == null) return null;

      final updatedCategory = category.updateName(newName);
      await _categoriesBox!.put(id, updatedCategory);
      AppLogger.d('Category name updated: $newName', 'VibeLibrary');
      return updatedCategory;
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to update category name: $e',
        'VibeLibrary',
        stackTrace,
      );
      return null;
    }
  }

  /// 移动分类到新父分类
  Future<VibeLibraryCategory?> moveCategory(
    String id,
    String? newParentId,
  ) async {
    await _ensureCategoriesBox();
    try {
      final category = _categoriesBox!.get(id);
      if (category == null) return null;

      // 检查循环引用
      if (newParentId != null) {
        final allCategories = await getAllCategories();
        if (allCategories.wouldCreateCycle(id, newParentId)) {
          throw ArgumentError('Cannot move category: would create cycle');
        }
      }

      final updatedCategory = category.moveTo(newParentId);
      await _categoriesBox!.put(id, updatedCategory);
      AppLogger.d('Category moved: ${category.name}', 'VibeLibrary');
      return updatedCategory;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to move category: $e', 'VibeLibrary', stackTrace);
      return null;
    }
  }

  /// 获取分类数量
  Future<int> getCategoriesCount() async {
    await _ensureCategoriesBox();
    try {
      return _categoriesBox!.length;
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to get categories count: $e',
        'VibeLibrary',
        stackTrace,
      );
      return 0;
    }
  }

  /// 检查分类是否存在
  Future<bool> categoryExists(String id) async {
    await _ensureCategoriesBox();
    try {
      return _categoriesBox!.containsKey(id);
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to check category existence: $e',
        'VibeLibrary',
        stackTrace,
      );
      return false;
    }
  }

  /// 清除所有分类
  Future<void> clearAllCategories() async {
    await _ensureCategoriesBox();
    try {
      await _categoriesBox!.clear();
      AppLogger.i('All categories cleared', 'VibeLibrary');
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to clear all categories: $e',
        'VibeLibrary',
        stackTrace,
      );
      rethrow;
    }
  }

  // ==================== Utility ====================

  /// 获取所有标签
  Future<Set<String>> getAllTags() async {
    await _ensureInit();
    try {
      final tags = <String>{};
      for (final entry in _entriesBox!.values) {
        tags.addAll(entry.tags);
      }
      return tags;
    } catch (e, stackTrace) {
      AppLogger.e('Failed to get all tags: $e', 'VibeLibrary', stackTrace);
      return {};
    }
  }

  /// 按标签筛选条目
  Future<List<VibeLibraryEntry>> getEntriesByTag(String tag) async {
    await _ensureInit();
    try {
      return _entriesBox!.values
          .where((entry) => entry.tags.contains(tag))
          .toList();
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to get entries by tag: $e',
        'VibeLibrary',
        stackTrace,
      );
      return [];
    }
  }

  /// 获取按使用次数排序的条目
  Future<List<VibeLibraryEntry>> getEntriesByUsage({int limit = 20}) async {
    await _ensureInit();
    try {
      final entries = _entriesBox!.values.toList();
      entries.sort((a, b) => b.usedCount.compareTo(a.usedCount));
      return entries.take(limit).toList();
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to get entries by usage: $e',
        'VibeLibrary',
        stackTrace,
      );
      return [];
    }
  }

  // ==================== Generation State Persistence ====================

  static const String _generationStateKey = 'generation_state';
  static const String _generationStateFileName = 'generation_state.json';
  String? _generationStateFilePath;

  Future<File?> _resolveGenerationStateFile({
    required bool createDirectory,
  }) async {
    try {
      final cachedPath = _generationStateFilePath;
      if (cachedPath != null) {
        final file = File(cachedPath);
        if (createDirectory) {
          await file.parent.create(recursive: true);
        }
        return file;
      }

      final appDir = await getApplicationSupportDirectory();
      final dir = Directory(p.join(appDir.path, 'generation_state'));
      if (createDirectory) {
        await dir.create(recursive: true);
      }

      final file = File(p.join(dir.path, _generationStateFileName));
      _generationStateFilePath = file.path;
      return file;
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to resolve generation state file, falling back to SharedPreferences',
        e,
        stackTrace,
        _tag,
      );
      return null;
    }
  }

  /// 保存生成参数中的 Vibe 和精准参考状态
  Future<void> saveGenerationState({
    required List<Map<String, dynamic>> vibeReferences,
    required List<Map<String, dynamic>> preciseReferences,
    required bool normalizeVibeStrength,
  }) async {
    try {
      final stateData = {
        'vibeReferences': vibeReferences,
        'preciseReferences': preciseReferences,
        'normalizeVibeStrength': normalizeVibeStrength,
        'savedAt': DateTime.now().toIso8601String(),
      };
      await saveGenerationStateJson(jsonEncode(stateData));
      AppLogger.d(
        'Generation state saved: ${vibeReferences.length} vibes, ${preciseReferences.length} precise refs',
        'VibeLibrary',
      );
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to save generation state',
        e,
        stackTrace,
        'VibeLibrary',
      );
    }
  }

  /// 保存已序列化的生成状态。
  ///
  /// 生成状态可能包含多张 Vibe/Precise Reference 图片。独立文件比
  /// SharedPreferences 更适合承载这类较大 payload，旧 SharedPreferences
  /// 键仍保留为读取兼容 fallback。
  Future<void> saveGenerationStateJson(String stateJson) async {
    final span = VibePerformanceDiagnostics.start(
      'storage.saveGenerationStateJson',
      details: {
        'chars': stateJson.length,
      },
    );
    var target = 'none';
    try {
      final file = await _resolveGenerationStateFile(createDirectory: true);
      if (file != null) {
        try {
          await file.writeAsString(stateJson);
          target = 'file';
          unawaited(_removeLegacyGenerationStatePreference());
          AppLogger.d('Generation state JSON saved to file', 'VibeLibrary');
          return;
        } catch (e, stackTrace) {
          AppLogger.e(
            'Failed to write generation state file, falling back to SharedPreferences',
            e,
            stackTrace,
            'VibeLibrary',
          );
        }
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_generationStateKey, stateJson);
      target = 'sharedPreferences';
      AppLogger.d(
        'Generation state JSON saved to SharedPreferences',
        'VibeLibrary',
      );
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to save generation state JSON',
        e,
        stackTrace,
        'VibeLibrary',
      );
    } finally {
      span.finish(
        details: {
          'target': target,
        },
      );
    }
  }

  /// 加载生成参数状态
  Future<Map<String, dynamic>?> loadGenerationState() async {
    try {
      final jsonString = await loadGenerationStateJson();
      if (jsonString != null) {
        final stateData = jsonDecode(jsonString) as Map<String, dynamic>;
        AppLogger.d('Generation state loaded', 'VibeLibrary');
        return stateData;
      }
      return null;
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to load generation state',
        e,
        stackTrace,
        'VibeLibrary',
      );
      return null;
    }
  }

  /// 加载已序列化的生成状态。
  Future<String?> loadGenerationStateJson() async {
    final span = VibePerformanceDiagnostics.start(
      'storage.loadGenerationStateJson',
    );
    var source = 'missing';
    var chars = 0;
    try {
      final file = await _resolveGenerationStateFile(createDirectory: false);
      if (file != null) {
        try {
          if (await file.exists()) {
            final jsonString = await file.readAsString();
            source = 'file';
            chars = jsonString.length;
            AppLogger.d(
              'Generation state JSON loaded from file',
              'VibeLibrary',
            );
            return jsonString;
          }
        } catch (e, stackTrace) {
          AppLogger.e(
            'Failed to read generation state file, falling back to SharedPreferences',
            e,
            stackTrace,
            'VibeLibrary',
          );
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_generationStateKey);
      if (jsonString != null) {
        source = 'sharedPreferences';
        chars = jsonString.length;
        AppLogger.d(
          'Generation state JSON loaded from SharedPreferences',
          'VibeLibrary',
        );
      }
      return jsonString;
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to load generation state JSON',
        e,
        stackTrace,
        'VibeLibrary',
      );
      return null;
    } finally {
      span.finish(
        details: {
          'source': source,
          'chars': chars,
        },
      );
    }
  }

  Future<void> _removeLegacyGenerationStatePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_generationStateKey)) {
        await prefs.remove(_generationStateKey);
      }
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to remove legacy generation state preference',
        e,
        stackTrace,
        'VibeLibrary',
      );
    }
  }

  /// 清除保存的生成状态
  Future<void> clearGenerationState() async {
    try {
      final file = await _resolveGenerationStateFile(createDirectory: false);
      if (file != null && await file.exists()) {
        await file.delete();
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_generationStateKey);
      AppLogger.d('Generation state cleared', 'VibeLibrary');
    } catch (e, stackTrace) {
      AppLogger.e(
        'Failed to clear generation state: $e',
        'VibeLibrary',
        stackTrace,
      );
    }
  }

  /// 关闭存储（清理资源）
  Future<void> close() async {
    try {
      if (_entriesBox != null && _entriesBox!.isOpen) {
        await _entriesBox!.close();
      }
      if (_lazyEntriesBox != null && _lazyEntriesBox!.isOpen) {
        await _lazyEntriesBox!.close();
      }
      if (_displayEntriesBox != null && _displayEntriesBox!.isOpen) {
        await _displayEntriesBox!.close();
      }
      if (_thumbnailCacheBox != null && _thumbnailCacheBox!.isOpen) {
        await _thumbnailCacheBox!.close();
      }
      if (_categoriesBox != null && _categoriesBox!.isOpen) {
        await _categoriesBox!.close();
      }
      AppLogger.d('VibeLibraryStorageService closed', 'VibeLibrary');
    } catch (e, stackTrace) {
      AppLogger.e('Failed to close storage: $e', 'VibeLibrary', stackTrace);
    }
  }
}

/// Provider
@Riverpod(keepAlive: true)
VibeLibraryStorageService vibeLibraryStorageService(Ref ref) {
  return VibeLibraryStorageService(
    fileStorage: VibeFileStorageService(),
  );
}
