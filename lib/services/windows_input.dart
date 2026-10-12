import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

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
      if (_step == 5 && control && up) {
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
  TextInputClient? _client;
  Timer? _showTimer;
  Timer? _hideTimer;
  int _generation = 0;

  bool get _editing {
    if (!_attached) return false;
    final client = _client;
    return client is! EditableTextState || client.widget.focusNode.hasFocus;
  }

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
    ++_generation;
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _client = client;
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
    _client = null;
    hide();
  }

  @override
  void show() {
    final generation = ++_generation;
    _hideTimer?.cancel();
    _showTimer?.cancel();
    // Focus updates and route disposal are deferred. Never show for a client
    // that was detached or unfocused while this request was pending.
    _showTimer = Timer(const Duration(milliseconds: 60), () {
      if (generation == _generation && _editing) {
        unawaited(_invoke('showKeyboard'));
      }
    });
  }

  @override
  void hide() {
    final generation = ++_generation;
    _showTimer?.cancel();
    _hideTimer?.cancel();
    // A field switch detaches then attaches; avoid closing between the two.
    _hideTimer = Timer(const Duration(milliseconds: 50), () {
      if (generation == _generation) unawaited(_invoke('hideKeyboard'));
    });
  }

  void dispose() {
    ++_generation;
    _showTimer?.cancel();
    _hideTimer?.cancel();
  }
}

abstract final class WindowsInput {
  static bool _initialized = false;
  static Future<void> initialize() async {
    if (!Platform.isWindows || _initialized) return;
    // ServicesBinding installs onKeyData after its initial native keyboard
    // state sync. Await that initialization before wrapping the dispatcher.
    await ServicesBinding.instance.keyboard.syncKeyboardState();
    final dispatcher = PlatformDispatcher.instance;
    final original =
        dispatcher.onKeyData ??
        ServicesBinding.instance.keyEventManager.handleKeyData;
    _initialized = true;
    TextInput.addInputControl(WindowsTouchKeyboard());
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
