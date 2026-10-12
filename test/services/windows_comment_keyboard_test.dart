import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:Pilipili/pages/common/publish/publish_route.dart';
import 'package:Pilipili/pages/video/reply_new/view.dart';
import 'package:Pilipili/common/widgets/flutter/text_field/text_field.dart';
import 'package:Pilipili/services/windows_input.dart';
import 'package:Pilipili/utils/storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart' hide TextField;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('pili-comment-keyboard-');
    Hive.init(directory.path);
    GStorage.setting = await Hive.openBox('setting');
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  const channel = MethodChannel('pilipili/comment_keyboard_test');
  final calls = <String>[];
  late WindowsTouchKeyboard observer;
  bool? visible;
  Completer<bool>? query;
  setUp(() {
    visible = false;
    query = null;
    calls.clear();
    observer = WindowsTouchKeyboard(channel: channel);
    TextInput.addInputControl(observer);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return call.method == 'isKeyboardVisible'
              ? (query == null ? visible : await query!.future)
              : true;
        });
  });
  tearDown(() {
    TextInput.removeInputControl(observer);
    observer.dispose();
    Get.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> openComment(
    WidgetTester tester, {
    PointerDeviceKind kind = PointerDeviceKind.touch,
    bool waitForFocus = true,
  }) async {
    await tester.pumpWidget(
      GetMaterialApp(
        builder: (_, child) => Material(child: child),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  PublishRoute(
                    pageBuilder: (_, _, _) => const ReplyPage(
                      oid: 1,
                      root: 0,
                      parent: 0,
                      replyType: 1,
                    ),
                  ),
                ),
                child: const Text('评论'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('评论'), kind: kind);
    await tester.pump();
    if (!waitForFocus) return;
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.byType(RichTextField), findsOneWidget);
    expect(tester.testTextInput.hasAnyClients, isTrue);
  }

  Future<void> dismiss(WidgetTester tester) async {
    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets(
    'normal visible comment keyboard is only hidden after dismissal',
    (
      tester,
    ) async {
      visible = true;
      await openComment(tester);
      await tester.pump(const Duration(milliseconds: 700));
      expect(calls, ['isKeyboardVisible']);
      calls.clear();
      await dismiss(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ReplyPage), findsNothing);
      expect(calls, ['hideKeyboard']);
    },
  );

  testWidgets('only missing keyboard for a touch comment gets one fallback', (
    tester,
  ) async {
    await openComment(tester);
    expect(calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 700));
    expect(calls, ['isKeyboardVisible', 'showKeyboardIfHidden']);
    await tester.pump(const Duration(seconds: 2));
    expect(calls.where((e) => e == 'showKeyboardIfHidden'), hasLength(1));
    calls.clear();
    await dismiss(tester);
    await tester.pumpAndSettle();
    expect(calls, ['hideKeyboard']);
  });

  testWidgets('dismissing real comment route before fallback cancels it', (
    tester,
  ) async {
    await openComment(tester);
    await dismiss(tester);
    // The rich text client can still be mounted during the exit animation.
    observer.show();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, ['hideKeyboard']);
  });

  testWidgets('quickly dismissing comment cancels its delayed autofocus', (
    tester,
  ) async {
    await openComment(tester, waitForFocus: false);
    await tester.pump(const Duration(milliseconds: 100));
    await dismiss(tester);
    await tester.pump(const Duration(milliseconds: 100));
    // The 300 ms autofocus timer fires while the 400 ms exit is still mounted.
    expect(tester.testTextInput.hasAnyClients, isFalse);
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
  });

  testWidgets('a second outside tap cannot cancel keyboard dismissal', (
    tester,
  ) async {
    visible = true;
    await openComment(tester);
    await tester.pump(const Duration(milliseconds: 700));
    calls.clear();
    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(calls, ['hideKeyboard']);
  });

  testWidgets('dismissal cancels an in-flight visibility response', (
    tester,
  ) async {
    query = Completer<bool>();
    await openComment(tester);
    await tester.pump(const Duration(milliseconds: 700));
    expect(calls, ['isKeyboardVisible']);
    await dismiss(tester);
    query!.complete(false);
    await tester.pumpAndSettle();
    expect(calls, ['isKeyboardVisible', 'hideKeyboard']);
  });

  testWidgets('mouse comment and unknown visibility do not force keyboard', (
    tester,
  ) async {
    await openComment(tester, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, isEmpty);
    await dismiss(tester);
    await tester.pumpAndSettle();
    expect(calls, ['hideKeyboard']);
    calls.clear();
    visible = null;
    await openComment(tester);
    await tester.pump(const Duration(milliseconds: 700));
    expect(calls, ['isKeyboardVisible']);
    await dismiss(tester);
    await tester.pumpAndSettle();
  });
}
