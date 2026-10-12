import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:Pilipili/common/widgets/flutter/text_field/editable_text.dart'
    as rich;

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
    : _channel = channel ?? const MethodChannel('pilipili/windows_input') {
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
  }
  final MethodChannel _channel;
  bool _attached = false;
  bool _hadInputConnection = false;
  TextInputClient? _client;
  Timer? _showTimer;
  Timer? _hideTimer;
  int _generation = 0;
  final _clock = Stopwatch()..start();
  Duration? _touchTime;

  void _onPointer(PointerEvent event) {
    if (event is! PointerDownEvent) return;
    // Cancel before a dismissing tap's route/focus changes are processed.
    ++_generation;
    _showTimer?.cancel();
    _touchTime = switch (event.kind) {
      PointerDeviceKind.touch || PointerDeviceKind.stylus => _clock.elapsed,
      _ => null,
    };
    if (_hadInputConnection && !_editing) hide();
  }

  bool get _editing {
    if (!_attached) return false;
    final client = _client;
    final (State, FocusNode, bool)? editing = switch (client) {
      EditableTextState() => (
        client,
        client.widget.focusNode,
        client.widget.readOnly,
      ),
      rich.EditableTextState() => (
        client,
        client.widget.focusNode,
        client.widget.readOnly,
      ),
      _ => null,
    };
    if (editing == null) return false;
    final (state, focus, readOnly) = editing;
    if (!state.mounted || !focus.hasFocus || readOnly) return false;
    final route = ModalRoute.of(state.context);
    return route == null ||
        (route.isCurrent &&
            route.isActive &&
            route.animation?.status != AnimationStatus.reverse);
  }

  Future<bool?> _invoke(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method);
    } on PlatformException {
      // Windows may decline a request under its keyboard/foreground policy.
    } on MissingPluginException {
      // Native integrations are absent in widget tests.
    }
    return null;
  }

  @override
  void attach(TextInputClient client, TextInputConfiguration configuration) {
    ++_generation;
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _client = client;
    _attached = configuration.inputType != TextInputType.none;
    _hadInputConnection = _hadInputConnection || _attached;
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
    final touchTime = _touchTime;
    if (touchTime == null ||
        _clock.elapsed - touchTime > const Duration(seconds: 2)) {
      return;
    }
    // Let Windows perform its normal automatic activation first. Only repair
    // a missed touch request; mouse/hardware input never forces a keyboard.
    _showTimer = Timer(const Duration(milliseconds: 600), () async {
      if (generation != _generation || !_editing) return;
      final visible = await _invoke('isKeyboardVisible');
      if (generation != _generation || !_editing || visible != false) return;
      final opened = await _invoke('showKeyboardIfHidden');
      if (opened == true && !_editing) hide();
    });
  }

  @override
  void hide() {
    final generation = ++_generation;
    _showTimer?.cancel();
    _hideTimer?.cancel();
    // Windows TextInput.hide is a no-op in this SDK. Keep explicit dismissal,
    // but never hide between field switches or while the user is still editing.
    if (!_hadInputConnection) return;
    _hideTimer = Timer(const Duration(milliseconds: 50), () {
      if (generation == _generation && !_editing) {
        _hadInputConnection = false;
        unawaited(_invoke('hideKeyboard'));
      }
    });
  }

  void dispose() {
    ++_generation;
    _showTimer?.cancel();
    _hideTimer?.cancel();
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
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
