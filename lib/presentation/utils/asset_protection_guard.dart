import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../providers/cost_estimate_provider.dart';
import '../providers/share_image_settings_provider.dart';
import '../widgets/common/themed_confirm_dialog.dart';

class AssetProtectionGuard {
  const AssetProtectionGuard._();

  static ShareImageSettings settings(WidgetRef ref) =>
      ref.read(shareImageSettingsProvider);

  static bool isEnabled(WidgetRef ref) =>
      ref.read(shareImageSettingsProvider).protectionMode;

  static bool shouldPreventOverwrite(WidgetRef ref) =>
      ref.read(shareImageSettingsProvider).effectivePreventOverwrite;

  static Future<bool> confirmDangerousAction({
    required BuildContext context,
    required WidgetRef ref,
    required String title,
    required String content,
    String confirmText = '继续',
    IconData icon = Icons.shield_outlined,
  }) async {
    if (!ref
        .read(shareImageSettingsProvider)
        .effectiveConfirmDangerousActions) {
      return true;
    }
    return ThemedConfirmDialog.show(
      context: context,
      title: title,
      content: content,
      confirmText: confirmText,
      cancelText: '取消',
      type: ThemedConfirmDialogType.warning,
      icon: icon,
    );
  }

  static Future<bool> confirmExternalImageSend({
    required BuildContext context,
    required WidgetRef ref,
    required String targetName,
    int imageCount = 1,
  }) {
    if (!ref.read(shareImageSettingsProvider).effectiveWarnExternalImageSend) {
      return Future.value(true);
    }
    return ThemedConfirmDialog.show(
      context: context,
      title: '保护模式：确认外部发送',
      content: '即将把 $imageCount 张本地图片发送到 $targetName。图片会离开本地应用边界，请确认这符合你的预期。',
      confirmText: '确认发送',
      cancelText: '取消',
      type: ThemedConfirmDialogType.warning,
      icon: Icons.cloud_upload_outlined,
    );
  }

  static Future<bool> confirmHighAnlasCost({
    required BuildContext context,
    required WidgetRef ref,
    int? cost,
  }) {
    final settings = ref.read(shareImageSettingsProvider);
    if (!settings.effectiveWarnHighAnlasCost) {
      return Future.value(true);
    }

    final estimatedCost = cost ?? ref.read(estimatedCostProvider) ?? 0;
    if (estimatedCost < settings.highAnlasCostThreshold) {
      return Future.value(true);
    }

    return ThemedConfirmDialog.show(
      context: context,
      title: '保护模式：Anlas 消耗较高',
      content: '本次预计消耗 $estimatedCost Anlas，已达到或超过你设置的 '
          '${settings.highAnlasCostThreshold} Anlas 警告阈值。请确认是否继续生成。',
      confirmText: '继续生成',
      cancelText: '取消',
      type: ThemedConfirmDialogType.warning,
      icon: Icons.toll_outlined,
    );
  }

  static Future<String> resolveNonOverwritingPath(String requestedPath) async {
    final file = File(requestedPath);
    if (!await file.exists()) {
      return requestedPath;
    }

    final directory = p.dirname(requestedPath);
    final extension = p.extension(requestedPath);
    final baseName = p.basenameWithoutExtension(requestedPath);

    var index = 1;
    while (true) {
      final candidate = p.join(directory, '$baseName ($index)$extension');
      if (!await File(candidate).exists()) {
        return candidate;
      }
      index += 1;
    }
  }
}
