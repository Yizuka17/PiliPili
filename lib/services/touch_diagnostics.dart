import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:Pilipili/build_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

/// Input-only diagnostics for investigating Windows touchscreen regressions.
/// Separate from error logs; no account or video data is recorded.
abstract final class TouchDiagnostics {
  static const _compiled = bool.fromEnvironment(
    'pili.touchLog',
    defaultValue: kDebugMode,
  );
  static const _maxBytes = 64 * 1024 * 1024;
  static bool get enabled => _compiled && Platform.isWindows;

  static IOSink? _sink;
  static Timer? _flushTimer;
  static bool _flushing = false;
  static bool _limited = false;
  static int _bytes = 0;
  static int _sequence = 0;
  static final _clock = Stopwatch();
  static final Map<int, PointerDeviceKind> _activePointers = {};
  static const _nativeChannel = MethodChannel('pilipili/windows_touch');
  static bool _nativeStarted = false;
  static bool _nativeHandlerInstalled = false;
  static int _lastHoverUs = -100000;
  static Map<String, Object?> _lastInput = {};
  static String? logPath;

  static Future<void> initialize({Directory? directory}) async {
    if (!enabled || _sink != null) return;
    try {
      final dir =
          directory ??
          Directory(
            path.join(Directory.systemTemp.path, 'Pilipili-touch-logs'),
          );
      await dir.create(recursive: true);
      final session = DateTime.now().toUtc().microsecondsSinceEpoch;
      logPath = path.join(dir.path, 'touch-$session-$pid.jsonl');
      _bytes = 0;
      _sequence = 0;
      _limited = false;
      _lastHoverUs = -100000;
      _activePointers.clear();
      _lastInput = {};
      _clock
        ..reset()
        ..start();
      final sink = File(logPath!).openWrite();
      _sink = sink;
      unawaited(sink.done.catchError(_disable));
      record('session', {
        'schema': 2,
        'diagnosticRevision': 'v4',
        'pid': pid,
        'os': Platform.operatingSystemVersion,
        'debug': kDebugMode,
        'appVersion': BuildConfig.versionName,
        'appCommit': BuildConfig.commitHash,
        'flutter': const String.fromEnvironment('pili.flutter'),
        'engine': const String.fromEnvironment('pili.engine'),
        'maxBytes': _maxBytes,
      });
      await _flush();
      if (_sink == null) return;
      _flushTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(_flush()),
      );
      debugPrint('Touch diagnostics: $logPath');
    } catch (error) {
      _disable(error);
    }
  }

  static Future<void> initializeNative() async {
    if (!enabled || _sink == null || _nativeStarted) return;
    _nativeChannel.setMethodCallHandler((call) async {
      if ((call.method == 'nativeInput' || call.method == 'nativeCursor') &&
          call.arguments is Map) {
        record(call.method, Map<String, Object?>.from(call.arguments as Map));
      }
    });
    _nativeHandlerInstalled = true;
    try {
      final state = await _nativeChannel.invokeMapMethod<String, Object?>(
        'startDiagnostics',
      );
      _nativeStarted = true;
      record('nativeTouchConfiguration', state ?? {});
    } catch (error) {
      // Tests and older runners can still use Dart input diagnostics.
      record('nativeTouchUnavailable', {'error': error.toString()});
    }
  }

  static void pointer(PointerEvent event) {
    if (_sink == null || _limited) return;
    _lastInput = {
      'kind': event.kind.name,
      'pointer': event.pointer,
      'position': [event.position.dx, event.position.dy],
      'buttons': event.buttons,
      'elapsedUs': _clock.elapsedMicroseconds,
    };
    if (event is PointerHoverEvent) {
      final now = _clock.elapsedMicroseconds;
      if (now - _lastHoverUs < 100000) return;
      _lastHoverUs = now;
    }
    final type = switch (event) {
      PointerDownEvent() => 'down',
      PointerMoveEvent() => 'move',
      PointerUpEvent() => 'up',
      PointerCancelEvent() => 'cancel',
      PointerAddedEvent() => 'added',
      PointerRemovedEvent() => 'removed',
      PointerHoverEvent() => 'hover',
      PointerPanZoomStartEvent() => 'panZoomStart',
      PointerPanZoomUpdateEvent() => 'panZoomUpdate',
      PointerPanZoomEndEvent() => 'panZoomEnd',
      PointerScrollEvent() => 'scroll',
      PointerScaleEvent() => 'scaleSignal',
      _ => 'other',
    };
    final previousKind = _activePointers[event.pointer];
    if (event is PointerDownEvent || event is PointerPanZoomStartEvent) {
      _activePointers[event.pointer] = event.kind;
    } else if (event is PointerUpEvent ||
        event is PointerCancelEvent ||
        event is PointerRemovedEvent ||
        event is PointerPanZoomEndEvent) {
      _activePointers.remove(event.pointer);
    }
    record('pointer', {
      'event': type,
      'pointer': event.pointer,
      'device': event.device,
      'kind': event.kind.name,
      'buttons': event.buttons,
      'down': event.down,
      'synthesized': event.synthesized,
      'eventUs': event.timeStamp.inMicroseconds,
      'position': [event.position.dx, event.position.dy],
      'delta': [event.delta.dx, event.delta.dy],
      'active': [
        for (final entry in _activePointers.entries)
          {'pointer': entry.key, 'kind': entry.value.name},
      ],
      'mixedMouseTouch':
          _activePointers.containsValue(PointerDeviceKind.mouse) &&
          _activePointers.containsValue(PointerDeviceKind.touch),
      if (event is PointerDownEvent && previousKind != null)
        'duplicateDown': true,
      if (event is PointerMoveEvent && event.down && previousKind == null)
        'missingDown': true,
      if (event is PointerCancelEvent && previousKind != null)
        'cancelledKind': previousKind.name,
      if (event is PointerPanZoomUpdateEvent) ...{
        'pan': [event.pan.dx, event.pan.dy],
        'scale': event.scale,
        'rotation': event.rotation,
      },
      if (event is PointerScrollEvent)
        'scrollDelta': [event.scrollDelta.dx, event.scrollDelta.dy],
    });
  }

  static void widgetState(Map<String, Object?> data) {
    record('widgetState', {...data, 'lastInput': _lastInput});
  }

  static void record(String category, Map<String, Object?> data) {
    final sink = _sink;
    if (sink == null || _limited) return;
    try {
      final line = jsonEncode(
        {
          'ts': DateTime.now().toUtc().toIso8601String(),
          'elapsedUs': _clock.elapsedMicroseconds,
          'sequence': ++_sequence,
          'category': category,
          ...data,
        },
        toEncodable: (Object? value) {
          // Keep diagnostics alive even if a broken scale produces NaN/Infinity.
          return value.toString();
        },
      );
      _bytes += utf8.encode(line).length + 1;
      if (_bytes > _maxBytes) {
        sink.writeln(
          jsonEncode({'category': 'logLimit', 'maxBytes': _maxBytes}),
        );
        _limited = true;
        _activePointers.clear();
        unawaited(_flush());
        return;
      }
      sink.writeln(line);
    } catch (error) {
      _disable(error);
    }
  }

  static Future<void> _flush() async {
    if (_flushing || _sink == null) return;
    _flushing = true;
    try {
      await _sink!.flush();
    } catch (error) {
      _disable(error);
    } finally {
      _flushing = false;
    }
  }

  static void _disable(Object error) {
    _flushTimer?.cancel();
    _flushTimer = null;
    final sink = _sink;
    _sink = null;
    _activePointers.clear();
    if (sink != null) unawaited(sink.close().catchError((Object _) {}));
    debugPrint('Touch diagnostics disabled: $error');
  }

  static Future<void> close() async {
    if (_nativeHandlerInstalled) {
      _nativeChannel.setMethodCallHandler(null);
      _nativeHandlerInstalled = false;
      _nativeStarted = false;
    }
    _flushTimer?.cancel();
    _flushTimer = null;
    record('sessionEnd', {});
    final sink = _sink;
    _sink = null;
    _activePointers.clear();
    _clock.stop();
    if (sink != null) {
      try {
        await sink.close();
      } catch (error) {
        debugPrint('Touch diagnostics close failed: $error');
      }
    }
  }
}
