import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nai_launcher/l10n/app_localizations.dart';

import '../../../app.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/first_launch_detector.dart';
import '../../providers/locale_provider.dart';
import '../../providers/update_provider.dart';
import '../../providers/warmup_provider.dart';
import '../../widgets/common/update_check_dialog.dart';
import 'splash_screen.dart';

/// 应用启动引导器
/// 管理预加载流程和页面切换
class AppBootstrap extends ConsumerStatefulWidget {
  const AppBootstrap({super.key});

  @override
  ConsumerState<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends ConsumerState<AppBootstrap> {
  bool _showMainApp = false;
  bool _hasCheckedFirstLaunch = false;

  @override
  Widget build(BuildContext context) {
    final warmupState = ref.watch(warmupNotifierProvider);

    // 预加载完成后显示主应用
    if (warmupState.isComplete && !_showMainApp) {
      // 延迟一帧后切换，确保动画流畅
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _showMainApp = true;
          });
        }
      });
    }

    // 如果显示主应用，直接返回（NAILauncherApp 自带 MaterialApp）
    if (_showMainApp) {
      return _MainAppWrapper(
        hasCheckedFirstLaunch: _hasCheckedFirstLaunch,
        onFirstLaunchChecked: () {
          _hasCheckedFirstLaunch = true;
        },
      );
    }

    // SplashScreen 需要 MaterialApp 提供基础上下文
    final locale = ref.watch(localeNotifierProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: const SplashScreen(key: ValueKey('splash')),
    );
  }
}

/// 主应用包装器，用于在应用启动后触发首次启动检测
class _MainAppWrapper extends ConsumerStatefulWidget {
  final bool hasCheckedFirstLaunch;
  final VoidCallback onFirstLaunchChecked;

  const _MainAppWrapper({
    required this.hasCheckedFirstLaunch,
    required this.onFirstLaunchChecked,
  });

  @override
  ConsumerState<_MainAppWrapper> createState() => _MainAppWrapperState();
}

class _MainAppWrapperState extends ConsumerState<_MainAppWrapper> {
  @override
  void initState() {
    super.initState();

    // 在应用启动后检查首次启动
    if (!widget.hasCheckedFirstLaunch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkFirstLaunch();
      });
    }

    // 延迟3秒后执行自动更新检查（不阻塞启动）
    _scheduleAutoUpdateCheck();
  }

  /// 调度自动更新检查
  ///
  /// 延迟3秒后检查是否需要更新，失败时静默处理
  void _scheduleAutoUpdateCheck() {
    Future.delayed(const Duration(seconds: 3), () async {
      try {
        // 检查是否应该检查更新（24小时冷却）
        final shouldCheck = await ref.read(
          checkUpdateOnStartupProvider.future,
        );
        if (!shouldCheck) return;

        // 执行更新检查
        await ref.read(updateStateProvider.notifier).checkForUpdates();

        // 如果有更新，显示对话框
        final state = ref.read(updateStateProvider);
        if (state.hasUpdate && mounted) {
          await UpdateCheckDialog.show(context);
        }
      } catch (e) {
        // 静默处理错误，不显示错误弹窗
        AppLogger.d('Auto update check failed: $e', 'AppBootstrap');
      }
    });
  }

  Future<void> _checkFirstLaunch() async {
    if (!mounted) return;

    widget.onFirstLaunchChecked();

    // 执行首次启动检测和同步
    await ref.read(firstLaunchNotifierProvider.notifier).checkAndSync(context);
  }

  @override
  Widget build(BuildContext context) {
    return const NAILauncherApp(key: ValueKey('main'));
  }
}
