import 'dart:async';

import 'package:Pilipili/utils/platform_utils.dart';
import 'package:Pilipili/utils/storage.dart';
import 'package:Pilipili/utils/storage_key.dart';
import 'package:Pilipili/utils/storage_pref.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:get/get.dart';

/// Keep system volume separate from each player's gain, including while ducked.
class PlaybackVolumeController {
  PlaybackVolumeController(this._setPlayerVolume)
    : _appMode = Pref.enableAppVolume.obs,
      _appVolume =
          (PlatformUtils.isDesktop ? Pref.desktopVolume : Pref.appVolume)
              .clamp(0.0, PlatformUtils.isDesktop ? Pref.maxVolume : 3.0)
              .obs {
    _instances.add(this);
  }

  final Future<void> Function(double) _setPlayerVolume;
  final RxBool _appMode;
  final RxDouble _appVolume;
  bool _ducked = false;
  Timer? _saveTimer;
  static final _instances = <PlaybackVolumeController>{};
  static final RxDouble systemVolume = 1.0.obs;
  static Future<void>? _initializing;
  static StreamSubscription<double>? _listener;

  bool get appMode => _appMode.value;
  RxDouble get volume => appMode ? _appVolume : systemVolume;
  double get maxVolume =>
      appMode ? (PlatformUtils.isDesktop ? Pref.maxVolume : 3.0) : 1.0;
  double get playerVolume => appMode
      ? _appVolume.value * 100
      : (PlatformUtils.isDesktop ? 100.0 : Pref.playerVolume);

  static Future<void> initializeSystem() => _initializing ??= _initialize();

  static Future<void> _initialize() async {
    try {
      final current = await FlutterVolumeController.getVolume();
      if (current != null) systemVolume.value = current;
      await FlutterVolumeController.updateShowSystemUI(true);
      _listener = FlutterVolumeController.addListener(
        (value) => systemVolume.value = value,
        category: AudioSessionCategory.playback,
        emitOnStart: false,
      );
      _listener!.onError((Object error) {
        if (kDebugMode) debugPrint('System volume listener: $error');
      });
    } catch (error) {
      _initializing = null;
      if (kDebugMode) debugPrint('System volume initialization: $error');
    }
  }

  static Future<void> setAppVolumeEnabled(bool enabled) async {
    if (_instances.isEmpty) return;
    await initializeSystem();
    for (final controller in _instances.toList()) {
      controller._appVolume.value = controller._appVolume.value.clamp(
        0.0,
        PlatformUtils.isDesktop ? Pref.maxVolume : 3.0,
      );
      controller._appMode.value = enabled;
      await controller._applyPlayerVolume();
    }
    await FlutterVolumeController.updateShowSystemUI(true);
  }

  Future<void> _applyPlayerVolume() =>
      _setPlayerVolume(playerVolume * (_ducked ? 0.5 : 1.0));

  static Future<void> refreshAppVolumeLimits() async {
    for (final controller in _instances.toList()) {
      final limit = PlatformUtils.isDesktop ? Pref.maxVolume : 3.0;
      if (controller._appVolume.value > limit) {
        controller._appVolume.value = limit;
        controller.saveAppVolume();
        if (controller.appMode) await controller._applyPlayerVolume();
      }
    }
  }

  Future<void> setVolume(double value) async {
    value = value.clamp(0.0, maxVolume);
    if (appMode) {
      _appVolume.value = value;
      await _applyPlayerVolume();
      _saveTimer?.cancel();
      _saveTimer = Timer(const Duration(milliseconds: 200), saveAppVolume);
    } else {
      await initializeSystem();
      await FlutterVolumeController.updateShowSystemUI(false);
      await FlutterVolumeController.setVolume(value);
      systemVolume.value = value;
    }
  }

  /// Audio-page changes must not overwrite system volume on a video player.
  Future<void> syncAppVolume(double value) async {
    _appVolume.value = value;
    if (appMode) await _applyPlayerVolume();
  }

  void saveAppVolume() {
    GStorage.setting.put(
      PlatformUtils.isDesktop
          ? SettingBoxKey.desktopVolume
          : SettingBoxKey.appVolume,
      _appVolume.value,
    );
  }

  Future<void> setDucked(bool value) async {
    _ducked = value;
    await _applyPlayerVolume();
  }

  void dispose() {
    if (_saveTimer != null) saveAppVolume();
    _saveTimer?.cancel();
    _instances.remove(this);
    if (_instances.isEmpty) {
      unawaited(_listener?.cancel());
      FlutterVolumeController.removeListener();
      _listener = null;
      _initializing = null;
    }
  }
}
