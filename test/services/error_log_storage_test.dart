import 'dart:io';

import 'package:Pilipili/services/error_log_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  setUp(
    () async =>
        root = await Directory.systemTemp.createTemp('pilipili-log-test-'),
  );
  tearDown(() => root.delete(recursive: true));

  test('changing directory keeps old and existing destination logs', () async {
    final defaultDir = p.join(root.path, 'documents');
    final customDir = p.join(root.path, 'custom');
    final old = await ErrorLogStorage.resolveFile(defaultDirectory: defaultDir);
    await old.writeAsString('old report\n');
    final destination = File(p.join(customDir, ErrorLogStorage.filename));
    await destination.create(recursive: true);
    await destination.writeAsString('destination report\n');
    await ErrorLogStorage.validateDirectory(customDir);
    final current = await ErrorLogStorage.resolveFile(
      defaultDirectory: defaultDir,
      customDirectory: customDir,
    );
    expect(current.path, destination.path);
    expect(await current.readAsString(), 'destination report\n');
    expect(await old.readAsString(), 'old report\n');
    expect(await Directory(customDir).list().length, 1);
  });

  test(
    'unavailable or relative custom directory falls back to documents',
    () async {
      final defaultDir = p.join(root.path, 'documents');
      final blocked = File(p.join(root.path, 'not-a-directory'));
      await blocked.writeAsString('preserve');
      for (final custom in [blocked.path, 'relative-path']) {
        final file = await ErrorLogStorage.resolveFile(
          defaultDirectory: defaultDir,
          customDirectory: custom,
        );
        expect(file.parent.path, defaultDir);
      }
      expect(await blocked.readAsString(), 'preserve');
    },
  );

  test(
    'invalid destination rejects saving and cleans the write probe',
    () async {
      final dir = await Directory(p.join(root.path, 'custom')).create();
      await Directory(p.join(dir.path, ErrorLogStorage.filename)).create();
      await expectLater(
        ErrorLogStorage.validateDirectory(dir.path),
        throwsA(isA<FileSystemException>()),
      );
      expect(await dir.list().length, 1);
      await expectLater(
        ErrorLogStorage.validateDirectory('relative-path'),
        throwsA(isA<FileSystemException>()),
      );
    },
  );
}
