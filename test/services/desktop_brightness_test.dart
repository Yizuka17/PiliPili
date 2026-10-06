import 'dart:async';
import 'dart:io';

import 'package:Pilipili/services/desktop_brightness.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';

class FakeBrightness extends ScreenBrightnessPlatform {
  bool unavailable = false;
  bool failWrite = false;
  bool reset = false;
  final writes = <double>[];
  @override
  Future<double> get application async {
    if (unavailable) throw UnsupportedError('no monitor');
    return 0.6;
  }

  @override
  Future<void> setApplicationScreenBrightness(double value) async {
    if (failWrite) throw UnsupportedError('driver disconnected');
    writes.add(value);
  }

  @override
  Future<void> resetApplicationScreenBrightness() async {
    reset = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('pilipili/display');
  late FakeBrightness fake;
  late ScreenBrightnessPlatform original;
  setUp(() {
    original = ScreenBrightnessPlatform.instance;
    fake = FakeBrightness();
    ScreenBrightnessPlatform.instance = fake;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => throw PlatformException(code: 'unavailable'),
        );
  });
  tearDown(() {
    ScreenBrightnessPlatform.instance = original;
  });
  test('unsupported screens report fallback, and write failure disables brightness', () async {
    final controller = DesktopBrightness();
    fake.unavailable = true;
    expect(await controller.initialize(), isFalse);
    expect(await controller.setBrightness(0.5), isFalse);
    fake.unavailable = false;
    expect(await controller.initialize(), isTrue);
    fake.failWrite = true;
    expect(await controller.setBrightness(0.5), isFalse);
    expect(controller.supported, isFalse);
  });
  test(
    'DDC path adjusts brightness and resets application override on disposal',
    () async {
      final controller = DesktopBrightness();
      expect(await controller.initialize(), isTrue);
      expect(controller.value, 0.6);
      expect(await controller.setBrightness(0.8), isTrue);
      expect(fake.writes, [0.8]);
      await controller.dispose();
      expect(fake.reset, isTrue);
    },
  );
  test(
    'native panel path coalesces slow drag updates to the latest value',
    () async {
      final firstWrite = Completer<void>();
      final writes = <double>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getBrightness') return 0.5;
            writes.add(call.arguments as double);
            if (writes.length == 1) await firstWrite.future;
            return null;
          });
      final controller = DesktopBrightness();
      expect(await controller.initialize(), isTrue);
      final pending = controller.setBrightness(0.2);
      await Future<void>.delayed(Duration.zero);
      controller
        ..setBrightness(0.3)
        ..setBrightness(0.8);
      firstWrite.complete();
      expect(await pending, isTrue);
      expect(writes, [0.2, 0.8]);
      expect(fake.writes, isEmpty);
      await controller.dispose();
    },
    skip: !Platform.isWindows,
  );
}
