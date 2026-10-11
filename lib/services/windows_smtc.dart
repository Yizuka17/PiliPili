import 'dart:async';
import 'dart:io';

import 'package:Pilipili/services/windows_smtc_artwork.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Optional Windows media controls, independent of the background audio switch.
class WindowsSmtc {
  WindowsSmtc({
    MethodChannel? channel,
    bool? supported,
    Future<Uint8List?> Function(Uri)? artworkLoader,
  }) : _channel = channel ?? const MethodChannel('pilipili/smtc'),
       _artworkLoader = artworkLoader ?? loadSmtcArtwork,
       supported = supported ?? Platform.isWindows;

  static final instance = WindowsSmtc();
  final MethodChannel _channel;
  final bool supported;
  bool enabled = false;
  MediaItem? _item;
  PlaybackState _state = PlaybackState();
  AudioHandler? _handler;
  Future<void> _pending = Future.value();
  final Future<Uint8List?> Function(Uri) _artworkLoader;
  Uri? _artworkUri;
  Uint8List? _artworkBytes;
  bool _artworkRequested = false;
  int _artworkGeneration = 0;

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
    if (!enabled) {
      ++_artworkGeneration;
      _artworkRequested = _artworkBytes != null;
    }
    if (enabled && _item != null) {
      await _sync();
    } else {
      await _send('setEnabled', false);
    }
  }

  void setMediaItem(MediaItem item) {
    // Playback may start before the video's asynchronous metadata arrives.
    if (_item != null && _item!.id != item.id) _state = PlaybackState();
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
    if (_artworkUri != artwork) {
      _artworkUri = artwork;
      _artworkBytes = null;
      _artworkRequested = false;
      ++_artworkGeneration;
    }
    if (artwork != null && !_artworkRequested) {
      _artworkRequested = true;
      unawaited(_loadArtwork(artwork, _artworkGeneration));
    }
    return _send('update', {
      'title': item.title,
      'artist': item.artist ?? '',
      'artworkBytes': _artworkBytes,
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

  Future<void> _loadArtwork(Uri uri, int generation) async {
    try {
      final png = await _artworkLoader(uri)
          .timeout(const Duration(seconds: 15));
      if (!enabled || generation != _artworkGeneration || png == null) return;
      _artworkBytes = png;
      await _sync();
    } catch (_) {
      // A missing cover must not hide metadata or interrupt playback.
    }
  }

  void clear() {
    _item = null;
    _state = PlaybackState();
    _artworkUri = null;
    _artworkBytes = null;
    _artworkRequested = false;
    ++_artworkGeneration;
    if (enabled) unawaited(_send('setEnabled', false));
  }
}
