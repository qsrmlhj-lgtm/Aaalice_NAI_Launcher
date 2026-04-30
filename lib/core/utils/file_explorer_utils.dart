import 'dart:io';

import 'package:path/path.dart' as path;

typedef FileExplorerProcessLauncher = Future<void> Function(
  String executable,
  List<String> arguments,
);

class FileExplorerUtils {
  FileExplorerUtils._();

  static List<String> windowsRevealFileArguments(String filePath) {
    return ['/select,', filePath];
  }

  static Future<void> openDirectory(
    String directoryPath, {
    FileExplorerProcessLauncher? startProcess,
  }) async {
    final dir = Directory(directoryPath.trim());
    if (dir.path.isEmpty) {
      throw ArgumentError.value(directoryPath, 'directoryPath', 'is empty');
    }
    if (!await dir.exists()) {
      throw FileSystemException('Directory does not exist', dir.path);
    }

    final launcher = startProcess ?? _startProcess;
    final absolutePath = dir.absolute.path;
    if (Platform.isWindows) {
      await launcher('explorer.exe', [absolutePath]);
    } else if (Platform.isMacOS) {
      await launcher('open', [absolutePath]);
    } else if (Platform.isLinux) {
      await launcher('xdg-open', [absolutePath]);
    }
  }

  static Future<void> revealFile(
    String filePath, {
    FileExplorerProcessLauncher? startProcess,
  }) async {
    final file = File(filePath.trim());
    if (file.path.isEmpty) {
      throw ArgumentError.value(filePath, 'filePath', 'is empty');
    }
    if (!await file.exists()) {
      throw FileSystemException('File does not exist', file.path);
    }

    final launcher = startProcess ?? _startProcess;
    final absolutePath = file.absolute.path;
    if (Platform.isWindows) {
      await launcher('explorer.exe', windowsRevealFileArguments(absolutePath));
    } else if (Platform.isMacOS) {
      await launcher('open', ['-R', absolutePath]);
    } else if (Platform.isLinux) {
      await launcher('xdg-open', [path.dirname(absolutePath)]);
    }
  }

  static Future<void> _startProcess(
    String executable,
    List<String> arguments,
  ) async {
    await Process.start(executable, arguments);
  }
}
