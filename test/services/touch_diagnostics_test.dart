import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:Pilipili/services/touch_diagnostics.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const nativeChannel = MethodChannel('pilipili/windows_touch');
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pili-touch-test-');
    await TouchDiagnostics.initialize(directory: directory);
  });
  tearDown(() async {
    await TouchDiagnostics.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, null);
    await directory.delete(recursive: true);
  });

  Future<List<Map<String, dynamic>>> entries() async {
    await TouchDiagnostics.close();
    return (await File(TouchDiagnostics.logPath!).readAsLines())
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();
  }

  test('receives native configuration and raw right-click evidence', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeChannel, (call) async {
          expect(call.method, 'startDiagnostics');
          return {
            'view': {'propertySet': true, 'gesturesBlocked': true},
          };
        });
    await TouchDiagnostics.initializeNative();
    final delivered = Completer<void>();
    ServicesBinding.instance.channelBuffers.push(
      nativeChannel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('nativeInput', {
          'message': 'WM_RBUTTONDOWN',
          'extraInfo': 0,
          'sourceDevice': 2,
        }),
      ),
      (_) => delivered.complete(),
    );
    await delivered.future;
    final records = await entries();
    expect(records[1]['category'], 'nativeTouchConfiguration');
    expect(records[1]['view']['gesturesBlocked'], true);
    expect(records[2]['category'], 'nativeInput');
    expect(records[2]['message'], 'WM_RBUTTONDOWN');
    expect(records[2]['extraInfo'], 0);
  }, skip: !Platform.isWindows);

  test('missing native handler does not disable pointer diagnostics', () async {
    await TouchDiagnostics.initializeNative();
    TouchDiagnostics.pointer(
      const PointerDownEvent(pointer: 10, kind: PointerDeviceKind.touch),
    );
    final records = await entries();
    expect(records[1]['category'], 'nativeTouchUnavailable');
    expect(records[2]['kind'], 'touch');
  }, skip: !Platform.isWindows);

  test(
    'records invisible cursor evidence and widget input correlation',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeChannel, (_) async => {});
      await TouchDiagnostics.initializeNative();
      final delivered = Completer<void>();
      ServicesBinding.instance.channelBuffers.push(
        nativeChannel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('nativeCursor', {
            'screenX': 100,
            'screenY': 200,
            'showing': false,
            'suppressed': true,
          }),
        ),
        (_) => delivered.complete(),
      );
      await delivered.future;
      TouchDiagnostics.pointer(
        const PointerUpEvent(
          pointer: 3,
          kind: PointerDeviceKind.touch,
          position: Offset(50, 100),
        ),
      );
      TouchDiagnostics.widgetState({'hovered': true, 'pressed': false});
      final records = await entries();
      final cursor = records.singleWhere(
        (e) => e['category'] == 'nativeCursor',
      );
      expect(cursor['showing'], false);
      expect(cursor['suppressed'], true);
      final state = records.singleWhere((e) => e['category'] == 'widgetState');
      expect(state['lastInput']['kind'], 'touch');
      expect(state['lastInput']['position'], [50, 100]);
      expect(state['pressed'], false);
    },
    skip: !Platform.isWindows,
  );

  test(
    'records hover without flooding or losing mouse button transitions',
    () async {
      for (var i = 0; i < 50; i++) {
        TouchDiagnostics.pointer(const PointerHoverEvent());
      }
      TouchDiagnostics.pointer(
        const PointerDownEvent(
          pointer: 11,
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryButton,
        ),
      );
      TouchDiagnostics.pointer(
        const PointerUpEvent(pointer: 11, kind: PointerDeviceKind.mouse),
      );
      final records = (await entries())
          .where((e) => e['category'] == 'pointer')
          .toList();
      expect(records.where((e) => e['event'] == 'hover'), hasLength(1));
      expect(records[1]['buttons'], kSecondaryButton);
      expect(records[2]['event'], 'up');
    },
    skip: !Platform.isWindows,
  );

  test('captures ghost mouse overlap and clears up/cancel pointers', () async {
    TouchDiagnostics.pointer(
      const PointerDownEvent(
        pointer: 1,
        kind: PointerDeviceKind.touch,
        buttons: kPrimaryButton,
      ),
    );
    TouchDiagnostics.pointer(
      const PointerDownEvent(
        pointer: 2,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryButton,
      ),
    );
    TouchDiagnostics.pointer(
      const PointerUpEvent(pointer: 1, kind: PointerDeviceKind.touch),
    );
    TouchDiagnostics.pointer(const PointerCancelEvent(pointer: 2));
    final records = (await entries())
        .where((e) => e['category'] == 'pointer')
        .toList();
    expect(records[0]['mixedMouseTouch'], false);
    expect(records[1]['mixedMouseTouch'], true);
    expect(records[1]['active'], hasLength(2));
    expect(records[2]['active'], [
      {'pointer': 2, 'kind': 'mouse'},
    ]);
    expect(records[3]['active'], isEmpty);
    expect(records[3]['cancelledKind'], 'mouse');
  }, skip: !Platform.isWindows);

  test('single finger remains single through repeated gestures', () async {
    for (var i = 1; i <= 25; i++) {
      TouchDiagnostics.pointer(
        PointerDownEvent(pointer: i, kind: PointerDeviceKind.touch),
      );
      TouchDiagnostics.pointer(
        PointerMoveEvent(pointer: i, kind: PointerDeviceKind.touch),
      );
      TouchDiagnostics.pointer(
        PointerUpEvent(pointer: i, kind: PointerDeviceKind.touch),
      );
    }
    final records = (await entries()).where((e) => e['category'] == 'pointer');
    expect(records, hasLength(75));
    expect(records.every((e) => !(e['mixedMouseTouch'] as bool)), true);
    expect(records.every((e) => (e['active'] as List).length <= 1), true);
  }, skip: !Platform.isWindows);

  test('preserves player state and valid ordered JSONL', () async {
    TouchDiagnostics.record('playerScaleUpdate', {
      'pointerCount': 2,
      'scale': 0.5,
    });
    TouchDiagnostics.record('playerFullscreenRequest', {
      'requested': true,
      'longPress': true,
    });
    final records = await entries();
    expect(records.first['category'], 'session');
    expect(records[1]['pointerCount'], 2);
    expect(records[1]['scale'], 0.5);
    expect(records[2]['longPress'], true);
    expect(records.last['category'], 'sessionEnd');
    expect(records.map((e) => e['sequence']), [1, 2, 3, 4]);
  }, skip: !Platform.isWindows);

  test('keeps recording after a non-finite scale', () async {
    TouchDiagnostics.record('playerScaleUpdate', {'scale': double.nan});
    TouchDiagnostics.record('playerScaleUpdate', {'scale': double.infinity});
    TouchDiagnostics.record('playerFullscreenComplete', {'status': true});
    final records = await entries();
    expect(records[1]['scale'], 'NaN');
    expect(records[2]['scale'], 'Infinity');
    expect(records[3]['status'], true);
    expect(records.last['category'], 'sessionEnd');
  }, skip: !Platform.isWindows);
}
