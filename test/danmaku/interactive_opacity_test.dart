import 'dart:io';

import 'package:Pilipili/models_new/danmaku/interactive.dart';
import 'package:Pilipili/pages/danmaku/interactive_card.dart';
import 'package:Pilipili/pages/danmaku/interactive_opacity.dart';
import 'package:Pilipili/pages/setting/widgets/interactive_card_opacity.dart';
import 'package:Pilipili/utils/storage.dart';
import 'package:Pilipili/utils/storage_key.dart';
import 'package:Pilipili/utils/storage_pref.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp(
      'pili-card-opacity-test-',
    );
    Hive.init(directory.path);
    GStorage.setting = await Hive.openBox('setting');
  });
  setUp(() => GStorage.setting.clear());
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  testWidgets('both controls update the playing card and preserve its choice', (
    tester,
  ) async {
    const card = InteractiveDanmaku(
      aid: 1,
      cid: 2,
      cardId: 3,
      progressMs: 0,
      id: 'opacity-test',
      kind: InteractiveKind.grade,
      extra: {'msg': '实用吗？', 'mid_score': 0, 'count': 803, 'avg_score': 9.5},
    );
    var posts = 0, videoTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              const Expanded(
                child: Column(
                  children: [
                    InteractiveCardOpacityControl(
                      key: ValueKey('player-setting'),
                    ),
                    InteractiveCardOpacityControl(
                      key: ValueKey('video-setting'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    GestureDetector(
                      onTap: () => videoTaps++,
                      child: const ColoredBox(color: Colors.black),
                    ),
                    Center(
                      child: InteractiveCardOpacity(
                        child: InteractiveDanmakuCard(
                          initial: card,
                          visible: true,
                          progress: () => 0,
                          canInteract: () => true,
                          read: () async => card,
                          submit: (_, _, _) async {
                            posts++;
                          },
                          notify: (_) {},
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('star-4')));
    await tester.pumpAndSettle();
    expect(find.text('8 分'), findsOneWidget);
    final controls = find.byType(InteractiveCardOpacityControl);
    final firstSlider = find.descendant(
      of: controls.first,
      matching: find.byType(Slider),
    );
    final secondSlider = find.descendant(
      of: controls.last,
      matching: find.byType(Slider),
    );
    final rect = tester.getRect(firstSlider);
    await tester.runAsync(() async {
      await tester.tapAt(Offset(rect.left + rect.width * .3, rect.center.dy));
      await GStorage.setting.flush();
    });
    await tester.pumpAndSettle();
    final value = Pref.interactiveCardOpacity;
    expect(value, greaterThan(0));
    expect(value, lessThan(.9));
    expect(tester.widget<Slider>(secondSlider).value, value);
    expect(
      tester
          .widget<Opacity>(
            find.descendant(
              of: find.byType(InteractiveCardOpacity),
              matching: find.byType(Opacity),
            ),
          )
          .opacity,
      value,
    );
    expect(find.text('8 分'), findsOneWidget);
    expect(find.byKey(const ValueKey('submit')), findsOneWidget);
    expect(posts, 0);

    final secondRect = tester.getRect(secondSlider);
    await tester.runAsync(() async {
      await tester.tapAt(Offset(secondRect.left + 1, secondRect.center.dy));
      await GStorage.setting.flush();
    });
    await tester.pumpAndSettle();
    expect(Pref.interactiveCardOpacity, 0);
    await tester.tapAt(tester.getCenter(find.byKey(const ValueKey('star-4'))));
    await tester.pumpAndSettle();
    expect(videoTaps, 1);
    expect(posts, 0);

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('默认值: 90.0%').first);
      await GStorage.setting.flush();
    });
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(firstSlider).value, .9);
    expect(tester.widget<Slider>(secondSlider).value, .9);
    expect(find.text('8 分'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await GStorage.setting.flush();
      await GStorage.setting.close();
      final reopened = await Hive.openBox('setting');
      expect(reopened.get(SettingBoxKey.interactiveCardOpacity), .9);
    });
  });
}
