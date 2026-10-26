import 'package:Pilipili/common/widgets/progress_bar/audio_video_progress_bar.dart';
import 'package:Pilipili/common/widgets/progress_bar/progress_hover_time.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const hint = ValueKey('progress-hover-time');
  int seeks = 0;
  int? seekMilliseconds;
  Widget player({int total = 7200, bool enabled = true, double width = 400}) =>
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: ProgressHoverTime(
                total: total,
                enabled: enabled,
                child: ProgressBar(
                  progress: 30,
                  total: total,
                  baseBarColor: Colors.grey,
                  progressBarColor: Colors.red,
                  bufferedBarColor: Colors.white,
                  thumbColor: Colors.red,
                  thumbGlowColor: Colors.red,
                  barHeight: 3.5,
                  thumbRadius: 7,
                  onDragStart: (_) {},
                  onSeek: (value) {
                    seeks++;
                    seekMilliseconds = value;
                  },
                ),
              ),
            ),
          ),
        ),
      );

  setUp(() {
    seeks = 0;
    seekMilliseconds = null;
  });

  testWidgets(
    'mouse tracks time, clamps at both ends and never seeks on hover',
    (tester) async {
      await tester.pumpWidget(player());
      final bar = tester.getRect(find.byType(ProgressBar));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(bar.center);
      await tester.pump();
      expect(find.text('01:00:00'), findsOneWidget);
      await mouse.moveTo(Offset(bar.left + .1, bar.center.dy));
      await tester.pump();
      expect(find.text('00:00'), findsOneWidget);
      expect(
        tester.getRect(find.byKey(hint)).left,
        greaterThanOrEqualTo(bar.left),
      );
      await mouse.moveTo(Offset(bar.right - .1, bar.center.dy));
      await tester.pump();
      expect(find.text('02:00:00'), findsOneWidget);
      expect(
        tester.getRect(find.byKey(hint)).right,
        lessThanOrEqualTo(bar.right),
      );
      expect(seeks, 0);
      await mouse.moveTo(bar.bottomRight + const Offset(20, 20));
      await tester.pump();
      expect(find.byKey(hint), findsNothing);
      await mouse.removePointer();
    },
  );

  testWidgets('click and drag keep seeking and dismiss the hover hint', (
    tester,
  ) async {
    await tester.pumpWidget(player());
    final bar = tester.getRect(find.byType(ProgressBar));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: bar.center);
    await tester.pump();
    expect(find.byKey(hint), findsOneWidget);
    await mouse.down(bar.center);
    await tester.pump();
    expect(find.byKey(hint), findsNothing);
    await mouse.up();
    await tester.pump();
    expect(seeks, 1);
    expect(seekMilliseconds, 3600000);
    await mouse.down(bar.center);
    await mouse.moveTo(Offset(bar.right - 1.75, bar.center.dy));
    await mouse.up();
    await tester.pump();
    expect(seeks, 2);
    expect(seekMilliseconds, 7200000);
    await mouse.removePointer();
  });

  testWidgets('disabled, unknown duration and touch do not display a hint', (
    tester,
  ) async {
    await tester.pumpWidget(player(enabled: false));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(ProgressBar)));
    await tester.pump();
    expect(find.byKey(hint), findsNothing);
    await tester.pumpWidget(player());
    await mouse.moveBy(const Offset(1, 0));
    await tester.pump();
    expect(find.byKey(hint), findsOneWidget);
    await tester.pumpWidget(player(total: 0));
    expect(find.byKey(hint), findsNothing);
    await mouse.removePointer();
    await tester.pumpWidget(player());
    final touch = await tester.startGesture(
      tester.getCenter(find.byType(ProgressBar)),
    );
    await tester.pump();
    expect(find.byKey(hint), findsNothing);
    await touch.up();
  });

  testWidgets('resizing recalculates time and keeps the hint in the new bar', (
    tester,
  ) async {
    await tester.pumpWidget(player());
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(ProgressBar)));
    await tester.pump();
    await tester.pumpWidget(player(width: 200, total: 120));
    await mouse.moveTo(tester.getCenter(find.byType(ProgressBar)));
    await tester.pump();
    expect(find.text('01:00'), findsOneWidget);
    final bar = tester.getRect(find.byType(ProgressBar));
    expect(bar.contains(tester.getCenter(find.byKey(hint))), isFalse);
    expect(
      tester.getRect(find.byKey(hint)).left,
      greaterThanOrEqualTo(bar.left),
    );
    expect(
      tester.getRect(find.byKey(hint)).right,
      lessThanOrEqualTo(bar.right),
    );
    await tester.pumpWidget(const SizedBox());
    await mouse.removePointer();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
