import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Optional Windows media controls, independent of the background audio switch.
class WindowsSmtc {
  WindowsSmtc({MethodChannel? channel, bool? supported})
    : _channel = channel ?? const MethodChannel('pilipili/smtc'),
      supported = supported ?? Platform.isWindows;

  static final instance = WindowsSmtc();
  final MethodChannel _channel;
  final bool supported;
  bool enabled = false;
  MediaItem? _item;
  PlaybackState _state = PlaybackState();
  AudioHandler? _handler;
  Future<void> _pending = Future.value();

  void bind(AudioHandler handler) {
    _handler = handler;
    if (supported) _channel.setMethodCallHandler(_handleCommand);
  }

  Future<void> _handleCommand(MethodCall call) async {
    final handler = _handler;
    if (!enabled || _item == null || handler == null) return;
    switch (call.method) {
      case 'play':
        await handler.play();
      case 'pause':
        await handler.pause();
      case 'next':
        if (_item!.isLive != true) await handler.skipToNext();
      case 'previous':
        if (_item!.isLive != true) await handler.skipToPrevious();
      case 'seek':
        final position = call.arguments;
        final duration = _item!.duration;
        if (_item!.isLive != true && position is int && duration != null) {
          await handler.seek(
            Duration(
              milliseconds: position.clamp(0, duration.inMilliseconds),
            ),
          );
        }
    }
  }

  Future<void> _send(String method, Object? arguments) {
    if (!supported) return Future.value();
    return _pending = _pending.then((_) async {
      try {
        await _channel.invokeMethod<void>(method, arguments);
      } on PlatformException catch (error) {
        debugPrint('Windows media controls: ${error.code}');
      } on MissingPluginException {
        // Unsupported hosts should keep ordinary playback working.
      }
    });
  }

  Future<void> setEnabled(bool value) async {
    enabled = supported && value;
    if (enabled && _item != null) {
      await _sync();
    } else {
      await _send('setEnabled', false);
    }
  }

  void setMediaItem(MediaItem item) {
    if (_item?.id != item.id) _state = PlaybackState();
    _item = item;
    if (enabled) unawaited(_sync());
  }

  void updatePlayback(PlaybackState state) {
    _state = state;
    if (enabled) unawaited(_sync());
  }

  Future<void> _sync() {
    final item = _item;
    if (item == null ||
        _state.processingState == .idle ||
        _state.processingState == .completed) {
      return _send('setEnabled', false);
    }
    final artwork = item.artUri;
    return _send('update', {
      'title': item.title,
      'artist': item.artist ?? '',
      'artwork':
          artwork != null &&
              const {'http', 'https', 'file'}.contains(artwork.scheme)
          ? artwork.toString()
          : '',
      'playing': _state.playing,
      'canSkip': item.isLive != true,
      'positionMs': _state.updatePosition.inMilliseconds,
      'durationMs': item.duration?.inMilliseconds ?? 0,
    });
  }

  void clear() {
    _item = null;
    _state = PlaybackState();
    if (enabled) unawaited(_send('setEnabled', false));
  }
}
