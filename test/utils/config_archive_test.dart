import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:Pilipili/common/constants.dart';
import 'package:Pilipili/utils/accounts.dart';
import 'package:Pilipili/utils/accounts/account.dart';
import 'package:Pilipili/utils/config_archive.dart';
import 'package:Pilipili/utils/path_utils.dart';
import 'package:Pilipili/utils/storage.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('pili-config-archive-');
    appSupportDirPath = directory.path;
    Hive.init(directory.path);
    GStorage.regAdapter();
    GStorage.setting = await Hive.openBox('setting');
    GStorage.video = await Hive.openBox('video');
    GStorage.localCache = await Hive.openBox('localCache');
    GStorage.historyWord = await Hive.openBox('history');
    GStorage.reply = null;
    Accounts.account = await Hive.openBox<LoginAccount>('account');
  });
  setUp(() async {
    await GStorage.setting.clear();
    await GStorage.video.clear();
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Uint8List archive(Map<String, Object> files) {
    final archive = Archive();
    for (final entry in files.entries) {
      archive.add(ArchiveFile.string(entry.key, jsonEncode(entry.value)));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  Map<String, Object> meta({int format = 0x10000}) => {
    'type': 'data_archive',
    'formatVersion': format,
    'appName': Constants.appName,
  };

  test('exports a readable zip with settings, accounts, blacklist, search and metadata', () async {
    await GStorage.setting.put('customSetting', '保留值');
    final stream = OutputMemoryStream();
    ConfigArchive.export(stream);
    final zip = ZipDecoder().decodeBytes(stream.getBytes());
    for (final name in [
      'meta.json',
      'setting.json',
      'account.json',
      'blacklist.json',
      'search.json',
    ]) {
      expect(zip.find(name), isNotNull);
    }
    final settings = jsonDecode(utf8.decode(zip.find('setting.json')!.content));
    expect(settings['setting']['customSetting'], '保留值');
    stream.closeSync();
  });

  test(
    'restores settings and video preferences from a supported archive',
    () async {
      await GStorage.setting.put('old', true);
      final result = await ConfigArchive.import(
        archive({
          'meta.json': meta(),
          'setting.json': {
            'setting': {'volume': 0.5},
            'video': {'quality': 80},
          },
        }),
        onWarning: (_) async => true,
      );
      expect(result, isEmpty);
      expect(GStorage.setting.get('old'), isNull);
      expect(GStorage.setting.get('volume'), 0.5);
      expect(GStorage.video.get('quality'), 80);
    },
  );

  test(
    'rejects missing metadata and newer formats without overwriting settings',
    () async {
      await GStorage.setting.put('keep', true);
      for (final files in [
        <String, Object>{},
        {'meta.json': meta(format: 0x20000)},
      ]) {
        await expectLater(
          ConfigArchive.import(archive(files), onWarning: (_) async => true),
          throwsUnsupportedError,
        );
        expect(GStorage.setting.get('keep'), isTrue);
      }
    },
  );
}
