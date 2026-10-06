import 'dart:io';

import 'package:Pilipili/services/playback_volume.dart';
import 'package:Pilipili/utils/storage.dart';
import 'package:Pilipili/utils/storage_key.dart';
import 'package:Pilipili/utils/storage_pref.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:hive_ce/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final controllers = <PlaybackVolumeController>[];
  final systemWrites = <double>[];
  PlaybackVolumeController controller(List<double> gains) {
    final result = PlaybackVolumeController((gain) async => gains.add(gain));
    controllers.add(result);
    return result;
  }

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('pili-volume-test-');
    Hive.init(directory.path);
    GStorage.setting = await Hive.openBox('setting');
    GStorage.video = await Hive.openBox('video');
    GStorage.localCache = await Hive.openBox('localCache');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger
      ..setMockMethodCallHandler(FlutterVolumeController.methodChannel, (
        call,
      ) async {
        if (call.method == 'getVolume') return '0.4';
        if (call.method == 'setVolume') {
          systemWrites.add((call.arguments as Map)['volume'] as double);
        }
        return null;
      })
      ..setMockMethodCallHandler(
        const MethodChannel('com.yosemiteyss.flutter_volume_controller/event'),
        (call) async => null,
      );
  });
  setUp(() async {
    systemWrites.clear();
    await GStorage.setting.clear();
  });
  tearDown(() {
    for (final item in controllers) {
      item.dispose();
    }
    controllers.clear();
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });
  test('app changes do not affect system volume; system changes do not overwrite app gain', () async {
    await GStorage.setting.put(SettingBoxKey.enableAppVolume, true);
    final gains = <double>[];
    final player = controller(gains);
    await PlaybackVolumeController.initializeSystem();
    await player.setVolume(0.65);
    player.saveAppVolume();
    expect(gains.last, 65);
    expect(systemWrites, isEmpty);
    expect(PlaybackVolumeController.systemVolume.value, 0.4);
    await GStorage.setting.put(SettingBoxKey.enableAppVolume, false);
    await PlaybackVolumeController.setAppVolumeEnabled(false);
    await player.setVolume(0.3);
    expect(systemWrites, [0.3]);
    await PlaybackVolumeController.setAppVolumeEnabled(true);
    expect(player.volume.value, 0.65);
    expect(gains.last, 65);
  });
  test(
    'ducking changes only transient player gain and preserves saved volume',
    () async {
      await GStorage.setting.put(SettingBoxKey.enableAppVolume, true);
      final gains = <double>[];
      final player = controller(gains);
      await player.setVolume(0.8);
      await player.setDucked(true);
      player.saveAppVolume();
      expect(gains.last, 40);
      expect(player.volume.value, 0.8);
      expect(systemWrites, isEmpty);
      await player.setDucked(false);
      expect(gains.last, 80);
    },
  );
  test('reducing app maximum clamps active gain and prevents an invalid slider value', () async {
    await GStorage.setting.put(SettingBoxKey.enableAppVolume, true);
    final gains = <double>[];
    final player = controller(gains);
    await player.setVolume(1.8);
    await GStorage.setting.put(SettingBoxKey.maxVolume, 1.0);
    await PlaybackVolumeController.refreshAppVolumeLimits();
    expect(player.volume.value, 1.0);
    expect(player.maxVolume, 1.0);
    expect(gains.last, 100);
  });
  test('both new switches and saved gain round-trip through existing settings backup', () async {
    await GStorage.setting.putAll({
      SettingBoxKey.enableHoverHighlight: false,
      SettingBoxKey.enableAppVolume: false,
      SettingBoxKey.appVolume: 0.7,
    });
    final backup = GStorage.exportAllSettings();
    await GStorage.setting.putAll({
      SettingBoxKey.enableHoverHighlight: true,
      SettingBoxKey.enableAppVolume: true,
      SettingBoxKey.appVolume: 1.0,
    });
    await GStorage.importAllSettings(backup);
    expect(Pref.enableHoverHighlight, isFalse);
    expect(Pref.enableAppVolume, isFalse);
    expect(Pref.appVolume, 0.7);
  });
}
