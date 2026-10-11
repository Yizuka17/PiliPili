import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/services.dart';

/// Repairs only the malformed key sequence emitted by Windows clipboard history.
/// Normal keyboard events and the engine's zero-valued focus probes pass through.
class WindowsPasteKeyNormalizer {
  static const _unmappedPhysical = 0x1600000000;
  static const _controlPhysical = 0x000700e0;
  static const _vPhysical = 0x00070019;
  static final _controlLogical = LogicalKeyboardKey.controlLeft.keyId;
  static final _vLogical = LogicalKeyboardKey.keyV.keyId;
  int _step = 0;
  bool _controlDown = false;
  bool _vDown = false;

  bool get pending => _step != 0;

  KeyData _key(KeyData source, int physical, int logical, KeyEventType type) =>
      KeyData(
        timeStamp: source.timeStamp,
        type: type,
        physical: physical,
        logical: logical,
        synthesized: source.synthesized,
        character: null,
      );

  List<KeyData> reset(Duration timeStamp) {
    final releases = <KeyData>[
      if (_vDown)
        KeyData(
          timeStamp: timeStamp,
          type: .up,
          physical: _vPhysical,
          logical: _vLogical,
          character: null,
          synthesized: true,
        ),
      if (_controlDown)
        KeyData(
          timeStamp: timeStamp,
          type: .up,
          physical: _controlPhysical,
          logical: _controlLogical,
          character: null,
          synthesized: true,
        ),
    ];
    _step = 0;
    _controlDown = _vDown = false;
    return releases;
  }

  List<KeyData> normalize(KeyData data) {
    if (data.physical == 0 && data.logical == 0) return [data];
    if (data.physical == _unmappedPhysical) {
      final control = data.logical == _controlLogical;
      final v = data.logical == _vLogical;
      final down = data.type == .down;
      final up = data.type == .up;
      if (_step == 0 && control && down && !data.synthesized) {
        _step = 1;
        _controlDown = true;
        return [_key(data, _controlPhysical, _controlLogical, .down)];
      }
      if (_step == 1 && control && up && data.synthesized) {
        _step = 2;
        return [];
      }
      if (_step == 2 && v && down) {
        _step = 3;
        _vDown = true;
        return [_key(data, _vPhysical, _vLogical, .down)];
      }
      if (_step == 3 && v && up) {
        _step = 4;
        _vDown = false;
        return [_key(data, _vPhysical, _vLogical, .up)];
      }
      if (_step == 4 && control && down && data.synthesized) {
        _step = 5;
        return [];
      }
      if (_step == 5 && control && up && data.synthesized) {
        _step = 0;
        _controlDown = false;
        return [_key(data, _controlPhysical, _controlLogical, .up)];
      }
    }
    return [...reset(data.timeStamp), data];
  }
}

/// Observes input requests alongside Flutter's existing IME connection.
/// Keeping the platform control installed preserves Chinese IME and editing.
class WindowsTouchKeyboard with TextInputControl {
  WindowsTouchKeyboard({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('pilipili/windows_input');
  final MethodChannel _channel;
  bool _attached = false;
  Timer? _hideTimer;

  Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<bool>(method);
    } on PlatformException {
      // Windows may decline a request under its keyboard/foreground policy.
    } on MissingPluginException {
      // Native integrations are absent in widget tests.
    }
  }

  @override
  void attach(TextInputClient client, TextInputConfiguration configuration) {
    _hideTimer?.cancel();
    _attached = configuration.inputType != TextInputType.none;
  }

  @override
  void updateConfig(TextInputConfiguration configuration) {
    _attached = configuration.inputType != TextInputType.none;
    if (!_attached) hide();
  }

  @override
  void detach(TextInputClient client) {
    _attached = false;
    hide();
  }

  @override
  void show() {
    _hideTimer?.cancel();
    if (_attached) unawaited(_invoke('showKeyboard'));
  }

  @override
  void hide() {
    _hideTimer?.cancel();
    // A field switch detaches then attaches; avoid closing between the two.
    _hideTimer = Timer(const Duration(milliseconds: 50), () {
      if (!_attached) unawaited(_invoke('hideKeyboard'));
    });
  }

  void dispose() => _hideTimer?.cancel();
}

abstract final class WindowsInput {
  static bool _initialized = false;
  static void initialize() {
    if (!Platform.isWindows || _initialized) return;
    _initialized = true;
    TextInput.addInputControl(WindowsTouchKeyboard());
    final dispatcher = PlatformDispatcher.instance;
    final original = dispatcher.onKeyData;
    if (original == null) return;
    final normalizer = WindowsPasteKeyNormalizer();
    Timer? timeout;
    dispatcher.onKeyData = (data) {
      timeout?.cancel();
      bool handled = false;
      final events = normalizer.normalize(data);
      for (final event in events) {
        handled = original(event) || handled;
      }
      if (normalizer.pending) {
        timeout = Timer(const Duration(milliseconds: 500), () {
          for (final release in normalizer.reset(data.timeStamp)) {
            original(release);
          }
        });
      }
      return events.isEmpty || handled;
    };
  }
}
