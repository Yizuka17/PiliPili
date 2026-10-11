import 'dart:ui';

import 'package:Pilipili/services/windows_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

KeyData key(
  int logical,
  KeyEventType type, {
  bool synthesized = false,
  int physical = 0x1600000000,
}) => KeyData(
  timeStamp: Duration.zero,
  type: type,
  physical: physical,
  logical: logical,
  character: null,
  synthesized: synthesized,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Win+V becomes Ctrl down, V down/up, Ctrl up', () {
    final repair = WindowsPasteKeyNormalizer();
    final ctrl = LogicalKeyboardKey.controlLeft.keyId;
    final v = LogicalKeyboardKey.keyV.keyId;
    final output = [
      key(ctrl, .down),
      key(ctrl, .up, synthesized: true),
      key(v, .down),
      key(v, .up),
      key(ctrl, .down, synthesized: true),
      key(ctrl, .up, synthesized: true),
    ].expand(repair.normalize).toList();
    expect(output.map((e) => e.type), <KeyEventType>[.down, .down, .up, .up]);
    expect(output.map((e) => e.physical), [0x700e0, 0x70019, 0x70019, 0x700e0]);
    expect(output.map((e) => e.logical), [ctrl, v, v, ctrl]);
    expect(repair.pending, isFalse);
  });

  test('hardware keys and focus probes remain unchanged', () {
    final repair = WindowsPasteKeyNormalizer();
    final hardware = key(
      LogicalKeyboardKey.keyV.keyId,
      .down,
      physical: 0x70019,
    );
    expect(repair.normalize(hardware).single, same(hardware));
    repair.normalize(key(LogicalKeyboardKey.controlLeft.keyId, .down));
    final probe = key(0, .down, physical: 0);
    expect(repair.normalize(probe).single, same(probe));
    expect(repair.pending, isTrue);
    final resumed = repair.normalize(hardware);
    expect(resumed.first.type, KeyEventType.up);
    expect(resumed.first.logical, LogicalKeyboardKey.controlLeft.keyId);
    expect(resumed.last, same(hardware));
    expect(repair.pending, isFalse);
  });

  test('incomplete paste releases any injected keys', () {
    final repair = WindowsPasteKeyNormalizer();
    repair.normalize(key(LogicalKeyboardKey.controlLeft.keyId, .down));
    repair.normalize(
      key(LogicalKeyboardKey.controlLeft.keyId, .up, synthesized: true),
    );
    repair.normalize(key(LogicalKeyboardKey.keyV.keyId, .down));
    final releases = repair.reset(Duration.zero);
    expect(releases.map((e) => e.logical), [
      LogicalKeyboardKey.keyV.keyId,
      LogicalKeyboardKey.controlLeft.keyId,
    ]);
    expect(releases.every((e) => e.type == .up && e.synthesized), isTrue);
    expect(repair.reset(Duration.zero), isEmpty);
  });

  testWidgets('clipboard history pastes through the normal selection action', (
    tester,
  ) async {
    final clipboard = <String, Object?>{};
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard['text'] = (call.arguments as Map)['text'];
        } else if (call.method == 'Clipboard.getData') {
          return clipboard;
        } else if (call.method == 'Clipboard.hasStrings') {
          return {'value': clipboard.isNotEmpty};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final controller = TextEditingController(text: 'abXYcd');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextField(controller: controller)),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    controller.selection = const TextSelection(baseOffset: 2, extentOffset: 4);
    await Clipboard.setData(const ClipboardData(text: '粘贴文本'));
    final repair = WindowsPasteKeyNormalizer();
    final ctrl = LogicalKeyboardKey.controlLeft.keyId;
    final v = LogicalKeyboardKey.keyV.keyId;
    for (final source in [
      key(ctrl, .down),
      key(ctrl, .up, synthesized: true),
      key(v, .down),
      key(v, .up),
      key(ctrl, .down, synthesized: true),
      key(ctrl, .up, synthesized: true),
    ]) {
      for (final event in repair.normalize(source)) {
        tester.binding.keyEventManager.handleKeyData(event);
      }
      // Windows sends the legacy key message after key-data. The framework
      // dispatches queued key-data on this message, as it does in the real app.
      if (!source.synthesized) {
        await tester.binding.keyEventManager.handleRawKeyMessage({
          'keymap': 'windows',
          'type': source.type == KeyEventType.down ? 'keydown' : 'keyup',
          'keyCode': source.logical == ctrl ? 0x11 : 0x56,
          'scanCode': source.logical == ctrl ? 0x1d : 0x2f,
          'characterCodePoint': 0,
          'modifiers': 0x30,
        });
      }
    }
    await tester.pump();
    expect(controller.text, 'ab粘贴文本cd');
    expect(HardwareKeyboard.instance.isControlPressed, isFalse);
  });

  testWidgets(
    'native keyboard requests preserve platform input and field switches',
    (tester) async {
      const channel = MethodChannel('pilipili/windows_input_test');
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        return true;
      });
      final observer = WindowsTouchKeyboard(channel: channel);
      TextInput.addInputControl(observer);
      final first = FocusNode();
      final second = FocusNode();
      addTearDown(() {
        TextInput.removeInputControl(observer);
        observer.dispose();
        first.dispose();
        second.dispose();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextField(focusNode: first),
                TextField(focusNode: second),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      expect(calls, contains('showKeyboard'));
      expect(tester.testTextInput.hasAnyClients, isTrue);
      calls.clear();
      second.requestFocus();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(calls, isNot(contains('hideKeyboard')));
      second.unfocus();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(calls, contains('hideKeyboard'));
      calls.clear();
      first.requestFocus();
      await tester.pump();
      expect(calls, contains('showKeyboard'));
      TextInput.removeInputControl(observer);
      observer.dispose();
    },
  );
}
