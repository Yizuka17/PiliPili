import 'dart:io';

import 'package:flutter/services.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';

/// Probe the actual display, rather than assuming all desktops support it.
class DesktopBrightness {
  static const _channel = MethodChannel('pilipili/display');
  bool supported = false;
  bool _wmi = false;
  bool _changed = false;
  double value = 1.0;
  double? _pending;
  Future<bool>? _writing;

  Future<bool> initialize() async {
    supported = false;
    if (Platform.isWindows) {
      try {
        final current = await _channel.invokeMethod<double>('getBrightness');
        if (current != null &&
            current.isFinite &&
            current >= 0 &&
            current <= 1) {
          value = current;
          _wmi = supported = true;
          return true;
        }
      } catch (_) {}
    }
    _wmi = false;
    try {
      final current = await ScreenBrightnessPlatform.instance.application;
      if (!current.isFinite || current < 0 || current > 1) return false;
      value = current;
      supported = true;
    } catch (_) {}
    return supported;
  }

  /// Coalesce drag updates so slow monitor drivers cannot queue stale values.
  Future<bool> setBrightness(double next) {
    if (!supported) return Future.value(false);
    _pending = next.clamp(0.0, 1.0);
    return _writing ??= _write().whenComplete(() => _writing = null);
  }

  Future<bool> _write() async {
    try {
      while (_pending != null) {
        final next = _pending!;
        _pending = null;
        if (_wmi) {
          await _channel.invokeMethod<void>('setBrightness', next);
        } else {
          await ScreenBrightnessPlatform.instance
              .setApplicationScreenBrightness(next);
        }
        value = next;
        _changed = true;
      }
      return true;
    } catch (_) {
      supported = false;
      _pending = null;
      return false;
    }
  }

  Future<void> dispose() async {
    _pending = null;
    await _writing;
    if (_changed && !_wmi) {
      try {
        await ScreenBrightnessPlatform.instance
            .resetApplicationScreenBrightness();
      } catch (_) {}
    }
  }
}
