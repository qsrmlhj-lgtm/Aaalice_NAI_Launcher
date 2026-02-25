/// 本地画廊服务统一导出文件
library;
///
/// 此文件提供所有画廊相关服务的统一入口，简化导入路径。
///
/// 使用示例:
/// ```dart
/// import 'package:nai_launcher/data/services/gallery/index.dart';
///
/// // 使用画廊扫描服务
/// final scanService = GalleryScanService(dataSource: dataSource);
///
/// // 使用过滤服务
/// final filterService = GalleryFilterService(dataSource);
/// ```

// 扫描配置和状态
export 'scan_config.dart' show
    ScanPriority,
    ScanConfig,
    ScanType,
    ScanPhase;

// 扫描状态相关
export 'scan_state_manager.dart' show
    ScanStatus,
    ScanProgressInfo;

// 扫描状态管理
export 'scan_state_manager.dart' show
    ScanStateManager,
    ScanStatus,
    ScanProgressCallback,
    ScanProgressInfo;

// 扫描服务
export 'gallery_scan_service.dart' show
    GalleryScanService,
    ScanResult,
    ScanResultBuilder;

// 过滤服务
export 'gallery_filter_service.dart' show
    GalleryFilterService,
    FilterCriteria;
