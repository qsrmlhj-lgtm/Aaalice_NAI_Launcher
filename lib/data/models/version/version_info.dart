import 'package:freezed_annotation/freezed_annotation.dart';

part 'version_info.freezed.dart';
part 'version_info.g.dart';

/// 版本信息模型
///
/// 用于存储 GitHub Release 的版本信息
@freezed
class VersionInfo with _$VersionInfo {
  const factory VersionInfo({
    /// 版本号（不含 v 前缀）
    required String version,

    /// Release 名称
    String? name,

    /// 发布说明
    String? releaseNotes,

    /// 发布时间（ISO 8601 格式）
    String? publishedAt,

    /// 下载链接（如果找不到匹配平台的资源，则为 html_url）
    String? downloadUrl,

    /// Release 页面链接
    String? htmlUrl,

    /// 是否比当前版本新
    @Default(false) bool isNewer,
  }) = _VersionInfo;

  const VersionInfo._();

  factory VersionInfo.fromJson(Map<String, dynamic> json) =>
      _$VersionInfoFromJson(json);

  /// 检查此版本是否需要从指定版本更新
  ///
  /// [current] 当前安装的版本
  /// 返回 true 如果此版本比当前版本新
  bool shouldUpdateFrom(VersionInfo current) {
    return VersionInfoComparator.isNewer(version, current.version);
  }
}

/// 版本号比较器
class VersionInfoComparator {
  /// 清理版本号字符串，移除 v 前缀
  static String _cleanVersion(String version) {
    if (version.startsWith('v') || version.startsWith('V')) {
      return version.substring(1);
    }
    return version;
  }

  /// 比较两个版本号，检查新版本是否比当前版本新
  static bool isNewer(String newVersion, String currentVersion) {
    try {
      // 清理 v 前缀
      final cleanNewVersion = _cleanVersion(newVersion);
      final cleanCurrentVersion = _cleanVersion(currentVersion);

      final newParts = cleanNewVersion.split('.').map(int.parse).toList();
      final currentParts = cleanCurrentVersion.split('.').map(int.parse).toList();

      for (var i = 0; i < newParts.length && i < currentParts.length; i++) {
        if (newParts[i] > currentParts[i]) return true;
        if (newParts[i] < currentParts[i]) return false;
      }

      return newParts.length > currentParts.length;
    } catch (_) {
      return false;
    }
  }
}
