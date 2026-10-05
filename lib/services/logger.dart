import 'dart:io';

import 'package:Pilipili/services/error_log_storage.dart';
import 'package:Pilipili/utils/json_file_handler.dart';
import 'package:Pilipili/utils/storage_pref.dart';
import 'package:catcher_2/utils/log_printer.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

final logger = Logger(
  filter: ProductionFilter(),
  printer: PrettyLogPrinter(
    dateTimeFormat: PrettyLogPrinter.toEncodableFallback,
  ),
  level: kDebugMode ? .trace : .warning,
);

abstract final class LoggerUtils {
  static File? _logFile;

  static Future<File> getLogsPath() async {
    if (_logFile != null) return _logFile!;

    return _logFile = await ErrorLogStorage.resolveFile(
      defaultDirectory: (await getApplicationDocumentsDirectory()).path,
      customDirectory: Pref.errorLogDirectory,
    );
  }

  static Future<bool> clearLogs() async {
    try {
      if (Pref.enableLog) {
        await JsonFileHandler.add(
          (raf) => raf.setPosition(0).then((raf) => raf.truncate(0)),
        );
      } else {
        final file = await getLogsPath();
        await file.writeAsBytes(const [], flush: true);
      }
    } catch (e) {
      // if (kDebugMode) debugPrint('Error clearing file: $e');
      return false;
    }
    return true;
  }
}
