import 'dart:io';

import 'package:path/path.dart' as p;

/// Keeps existing logs intact when checking or changing their storage directory.
abstract final class ErrorLogStorage {
  static const filename = '.pili_logs.json';

  static Future<void> validateDirectory(String directory) async {
    if (!p.isAbsolute(directory)) {
      throw const FileSystemException('请选择绝对路径');
    }
    final dir = await Directory(directory).create(recursive: true);
    final probe = await dir.createTemp('.pilipili-log-check-');
    final file = File(p.join(probe.path, 'write-check'));
    try {
      await file.writeAsBytes(const [], flush: true);
      final log = File(p.join(dir.path, filename));
      if (Directory(log.path).existsSync()) {
        throw const FileSystemException('日志文件位置被同名目录占用');
      }
      if (log.existsSync()) {
        final handle = await log.open(mode: FileMode.writeOnlyAppend);
        await handle.close();
      }
    } finally {
      if (file.existsSync()) await file.delete();
      await probe.delete();
    }
  }

  static Future<File> resolveFile({
    required String defaultDirectory,
    String? customDirectory,
  }) async {
    Future<File> openDirectory(String directory) async {
      if (!p.isAbsolute(directory)) {
        throw const FileSystemException('日志目录必须是绝对路径');
      }
      await Directory(directory).create(recursive: true);
      final file = File(p.join(directory, filename));
      final handle = await file.open(mode: FileMode.writeOnlyAppend);
      await handle.close();
      return file;
    }

    if (customDirectory != null && customDirectory.isNotEmpty) {
      try {
        return await openDirectory(customDirectory);
      } on FileSystemException {
        // An unplugged drive or an imported path must not disable error logging.
      }
    }
    return openDirectory(defaultDirectory);
  }
}
