import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../migration_engine.dart';

/// 迁移：添加画廊表索引优化扫描性能
///
/// 添加 file_hash 和 file_path 索引，大幅提升画廊扫描性能
class AddGalleryIndexesMigration extends Migration {
  @override
  int get version => 1;

  @override
  String get description => 'Add file_hash and file_path indexes to gallery_images table';

  @override
  Future<void> up(Database db) async {
    // 添加 file_hash 索引（部分索引，只包含未删除的记录）
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_gallery_images_file_hash
      ON gallery_images(file_hash) WHERE is_deleted = 0
    ''');

    // 添加 file_path 索引（部分索引，只包含未删除的记录）
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_gallery_images_file_path
      ON gallery_images(file_path) WHERE is_deleted = 0
    ''');
  }

  @override
  Future<void> down(Database db) async {
    // 回滚：删除索引
    await db.execute('DROP INDEX IF EXISTS idx_gallery_images_file_hash');
    await db.execute('DROP INDEX IF EXISTS idx_gallery_images_file_path');
  }
}
