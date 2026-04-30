import '../models/vibe/vibe_library_entry.dart';
import 'vibe_import_service.dart';
import 'vibe_library_storage_service.dart';

/// VibeLibraryNotifier 的导入仓库适配器
/// 实现 VibeLibraryImportRepository 接口以适配 VibeImportService
class VibeLibraryNotifierImportRepository implements VibeLibraryImportRepository {
  VibeLibraryNotifierImportRepository({
    required this.onGetAllEntries,
    required this.onSaveEntry,
  });

  final Future<List<VibeLibraryEntry>> Function() onGetAllEntries;
  final Future<VibeLibraryEntry?> Function(VibeLibraryEntry) onSaveEntry;

  @override
  Future<List<VibeLibraryEntry>> getAllEntries() async {
    return onGetAllEntries();
  }

  @override
  Future<VibeLibraryEntry> saveEntry(VibeLibraryEntry entry) async {
    final saved = await onSaveEntry(entry);
    if (saved == null) {
      throw StateError('Failed to save entry: ${entry.name}');
    }
    return saved;
  }
}

/// 直接使用存储层的导入仓库。
///
/// 批量导入期间避免每保存一个条目就触发 provider 全量重建，
/// 导入完成后再统一 reload UI。
class VibeLibraryStorageImportRepository implements VibeLibraryImportRepository {
  VibeLibraryStorageImportRepository(this._storage);

  final VibeLibraryStorageService _storage;

  @override
  Future<List<VibeLibraryEntry>> getAllEntries() {
    return _storage.getAllEntries();
  }

  @override
  Future<VibeLibraryEntry> saveEntry(VibeLibraryEntry entry) {
    return _storage.saveEntry(entry);
  }
}
