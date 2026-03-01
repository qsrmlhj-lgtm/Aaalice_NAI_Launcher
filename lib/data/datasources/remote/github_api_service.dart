import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../models/version/version_info.dart';

part 'github_api_service.g.dart';

/// GitHub API 异常
class GitHubApiException implements Exception {
  final String message;
  final Object? originalError;

  GitHubApiException(this.message, {this.originalError});

  @override
  String toString() => 'GitHubApiException: $message';
}

/// GitHub API 服务
/// 
/// 用于获取 GitHub Releases 最新版本信息
class GitHubApiService {
  /// 默认 GitHub API 基础 URL
  static const String defaultBaseUrl = 'https://api.github.com';
  
  /// 连接超时时间
  static const Duration connectTimeout = Duration(seconds: 10);
  
  /// 接收超时时间
  static const Duration receiveTimeout = Duration(seconds: 30);

  final Dio _dio;

  GitHubApiService({required Dio dio}) : _dio = dio;

  /// 获取最新 Release 版本信息
  ///
  /// [owner] 仓库所有者
  /// [repo] 仓库名称
  /// [currentVersion] 当前版本号（用于计算是否需要更新）
  /// [platform] 目标平台（windows, android 等）
  Future<VersionInfo> fetchLatestRelease({
    required String owner,
    required String repo,
    required String currentVersion,
    String platform = 'windows',
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/repos/$owner/$repo/releases/latest',
        options: Options(
          connectTimeout: connectTimeout,
          receiveTimeout: receiveTimeout,
          headers: {
            'Accept': 'application/vnd.github.v3+json',
          },
        ),
      );

      final data = response.data;
      if (data == null) {
        throw GitHubApiException('Empty response from GitHub API');
      }

      return _parseReleaseData(data, currentVersion, platform);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw GitHubApiException(
          'Release not found for $owner/$repo',
          originalError: e,
        );
      }
      throw GitHubApiException(
        'Failed to fetch release: ${e.message}',
        originalError: e,
      );
    } catch (e) {
      throw GitHubApiException(
        'Unexpected error: $e',
        originalError: e,
      );
    }
  }

  /// 解析 Release 数据
  VersionInfo _parseReleaseData(
    Map<String, dynamic> data,
    String currentVersion,
    String platform,
  ) {
    final tagName = data['tag_name'] as String? ?? '';
    final version = _extractVersion(tagName);
    final name = data['name'] as String? ?? '';
    final body = data['body'] as String? ?? '';
    final publishedAt = data['published_at'] as String? ?? '';
    final htmlUrl = data['html_url'] as String? ?? '';
    final assets = data['assets'] as List<dynamic>? ?? [];

    // 查找匹配平台的下载链接
    final downloadUrl = _findDownloadUrl(assets, platform) ?? htmlUrl;

    return VersionInfo(
      version: version,
      name: name,
      releaseNotes: body,
      publishedAt: publishedAt,
      downloadUrl: downloadUrl,
      htmlUrl: htmlUrl,
      isNewer: _isNewerVersion(version, currentVersion),
    );
  }

  /// 从 tag_name 提取版本号（移除 v 前缀）
  String _extractVersion(String tagName) {
    if (tagName.startsWith('v')) {
      return tagName.substring(1);
    }
    return tagName;
  }

  /// 查找匹配平台的下载链接
  String? _findDownloadUrl(List<dynamic> assets, String platform) {
    for (final asset in assets) {
      if (asset is Map<String, dynamic>) {
        final name = asset['name'] as String? ?? '';
        final downloadUrl = asset['browser_download_url'] as String?;
        
        if (downloadUrl != null && _matchesPlatform(name, platform)) {
          return downloadUrl;
        }
      }
    }
    return null;
  }

  /// 检查资源文件名是否匹配平台
  bool _matchesPlatform(String fileName, String platform) {
    final lowerName = fileName.toLowerCase();
    final lowerPlatform = platform.toLowerCase();
    
    return lowerName.contains(lowerPlatform) ||
           (lowerPlatform == 'windows' && lowerName.endsWith('.exe')) ||
           (lowerPlatform == 'windows' && lowerName.endsWith('.zip')) ||
           (lowerPlatform == 'android' && lowerName.endsWith('.apk'));
  }

  /// 比较版本号，检查新版本是否比当前版本新
  bool _isNewerVersion(String newVersion, String currentVersion) {
    try {
      final newParts = newVersion.split('.').map(int.parse).toList();
      final currentParts = currentVersion.split('.').map(int.parse).toList();
      
      for (var i = 0; i < newParts.length && i < currentParts.length; i++) {
        if (newParts[i] > currentParts[i]) return true;
        if (newParts[i] < currentParts[i]) return false;
      }
      
      return newParts.length > currentParts.length;
    } catch (_) {
      // 如果解析失败，默认返回 false
      return false;
    }
  }
}

/// GitHubApiService Provider
@riverpod
GitHubApiService gitHubApiService(Ref ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: GitHubApiService.defaultBaseUrl,
      connectTimeout: GitHubApiService.connectTimeout,
      receiveTimeout: GitHubApiService.receiveTimeout,
    ),
  );
  return GitHubApiService(dio: dio);
}
