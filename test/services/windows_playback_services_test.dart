import 'dart:async';
import 'dart:io';

import 'package:Pilipili/models_new/video/video_detail/page.dart';
import 'package:Pilipili/plugin/pl_player/models/play_status.dart';
import 'package:Pilipili/services/service_locator.dart';
import 'package:Pilipili/services/windows_smtc.dart';
import 'package:Pilipili/utils/storage.dart';
import 'package:Pilipili/utils/storage_key.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pilipili/smtc');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('pili-smtc-startup-');
    Hive.init(directory.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.localCache = await Hive.openBox('localCache');
    GStorage.video = await Hive.openBox('video');
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });
  setUp(() async {
    await GStorage.setting.clear();
    await WindowsSmtc.instance.setEnabled(false);
    videoPlayerServiceHandler?.clear();
    await Future<void>.delayed(Duration.zero);
    calls.clear();
  });
  tearDownAll(() async {
    await WindowsSmtc.instance.setEnabled(false);
    videoPlayerServiceHandler?.clear();
    channel.setMethodCallHandler(null);
    messenger.setMockMethodCallHandler(channel, null);
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('Windows startup restores SMTC and publishes playback without background audio', () async {
    await GStorage.setting.putAll({
      SettingBoxKey.enableSmtc: true,
      SettingBoxKey.enableBackgroundPlay: false,
    });
    await setupServiceLocator();
    final handler = videoPlayerServiceHandler!;
    expect(audioSessionHandler, isNull);
    expect(handler.enableBackgroundPlay, isFalse);
    expect(WindowsSmtc.instance.enabled, isTrue);

    // The player starts while the introduction request is still in flight.
    handler
      ..onUpdateState(
        PlayerStatus.playing,
        false,
        false,
        position: const Duration(seconds: 12),
        speed: 1,
      )
      ..onVideoDetailChange(
        Part(cid: 42, part: '视频标题', duration: 120),
        42,
        'test-video',
        artist: '视频作者',
        cover: 'https://example.com/cover.jpg',
      );
    await Future<void>.delayed(Duration.zero);
    final metadata = calls.last.arguments as Map;
    expect(calls.last.method, 'update');
    expect(metadata['title'], '视频标题');
    expect(metadata['artist'], '视频作者');
    expect(metadata['playing'], isTrue);
    expect(metadata['positionMs'], 12000);
    expect(metadata['durationMs'], 120000);

    var paused = false;
    handler.onPause = () async => paused = true;
    final done = Completer<void>();
    messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(const MethodCall('pause')),
      (_) => done.complete(),
    );
    await done.future;
    expect(paused, isTrue);
    await WindowsSmtc.instance.setEnabled(false);
    expect(calls.last.method, 'setEnabled');
    expect(calls.last.arguments, isFalse);
  }, skip: !Platform.isWindows);

  test(
    'Windows startup keeps SMTC disabled until enabled during playback',
    () async {
      await GStorage.setting.put(SettingBoxKey.enableBackgroundPlay, false);
      await setupServiceLocator();
      final handler = videoPlayerServiceHandler!;
      expect(WindowsSmtc.instance.enabled, isFalse);
      handler
        ..onVideoDetailChange(
          Part(cid: 43, part: '正在播放', duration: 60),
          43,
          'test-video',
        )
        ..onUpdateState(
          PlayerStatus.playing,
          false,
          false,
          position: const Duration(seconds: 15),
          speed: 1,
        );
      await Future<void>.delayed(Duration.zero);
      expect(calls.where((call) => call.method == 'update'), isEmpty);
      await WindowsSmtc.instance.setEnabled(true);
      expect(calls.last.method, 'update');
      expect((calls.last.arguments as Map)['playing'], isTrue);
      expect((calls.last.arguments as Map)['positionMs'], 15000);
    },
    skip: !Platform.isWindows,
  );
}
