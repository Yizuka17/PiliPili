import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:Pilipili/models_new/danmaku/interactive.dart';
import 'package:Pilipili/pages/danmaku/interactive_card.dart';
import 'package:Pilipili/pages/danmaku/interactive_layout.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

InteractiveDanmaku _card(InteractiveKind kind, {bool fourOptions = false}) =>
    InteractiveDanmaku(
      aid: 1,
      cid: 2,
      cardId: 3,
      progressMs: 1000,
      id: 'capsule',
      kind: kind,
      extra: {
        'duration': 10000,
        'question': '今天的大盘？',
        'msg': '这段视频怎么样？',
        'cnt': 1973,
        'count': 1973,
        'avg_score': 8.6,
        'options': [
          for (final (index, text)
              in (fourOptions
                      ? ['今天真的很香', '今天有点太臭', '继续等等再买', '价格再降一点']
                      : ['真香', '太臭啦'])
                  .indexed)
            {'idx': index + 1, 'desc': text},
        ],
      },
    );

class _Harness extends StatefulWidget {
  final InteractiveDanmaku card;
  final ValueNotifier<int> position;
  final double width;
  final double? height;
  final Future<InteractiveDanmaku> Function()? read;
  final Future<void> Function(InteractiveDanmaku, int, int)? submit;
  final GlobalKey? captureKey;
  const _Harness({
    required this.card,
    required this.position,
    this.width = 360,
    this.height,
    this.read,
    this.submit,
    this.captureKey,
  });
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  bool expanded = false;
  @override
  Widget build(BuildContext context) {
    final size = Size(widget.width, widget.height ?? widget.width * 9 / 16);
    return MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Capsule QA',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xfffb7299)),
      ),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: Size(widget.width, 800),
            textScaler: const TextScaler.linear(1.3),
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: widget.captureKey,
              child: SizedBox.fromSize(
                size: size,
                child: ColoredBox(
                  color: const Color(0xff34383e),
                  child: CustomSingleChildLayout(
                    delegate: InteractiveCardLayout(
                      const Offset(.8, .65),
                      Offset.zero & size,
                      capsule: !expanded,
                    ),
                    child: InteractiveDanmakuCard(
                      initial: widget.card,
                      visible: true,
                      progress: () => widget.position.value,
                      positionChanges: widget.position,
                      onExpandedChanged: (value) =>
                          setState(() => expanded = value),
                      canInteract: () => true,
                      read: widget.read ?? () async => widget.card,
                      submit: widget.submit ?? (_, _, _) async {},
                      notify: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  if (Platform.environment['PILI_UI_CAPTURE'] != '1') return;
  await tester.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('build/ui-qa/capsule').create(recursive: true);
    await File('build/ui-qa/capsule/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final font = Platform.environment['PILI_UI_FONT'];
    if (font != null) {
      await (FontLoader('Capsule QA')..addFont(
            File(font).readAsBytes().then((b) => b.buffer.asByteData()),
          ))
          .load();
    }
  });
  for (final kind in InteractiveKind.values) {
    testWidgets(
      '$kind starts as a capsule; countdown follows playback and seeking',
      (tester) async {
        final card = _card(kind), position = ValueNotifier(1000);
        addTearDown(position.dispose);
        final capture = GlobalKey();
        var writes = 0;
        await tester.pumpWidget(
          _Harness(
            card: card,
            position: position,
            captureKey: capture,
            submit: (_, _, _) async => writes++,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('visible-card')), findsNothing);
        expect(
          find.text(kind == InteractiveKind.vote ? '投票' : '打分'),
          findsOneWidget,
        );
        expect(
          tester
              .getRect(find.byKey(const ValueKey('interactive-capsule')))
              .left,
          8,
        );
        double remaining() => tester
            .widget<CircularProgressIndicator>(
              find.byKey(const ValueKey('capsule-countdown')),
            )
            .value!;
        expect(remaining(), 1);
        position.value = 3500;
        await tester.pump();
        expect(remaining(), .75);
        await tester.pump(const Duration(seconds: 2));
        expect(remaining(), .75);
        await _capture(tester, capture, '${kind.name}-hint');
        await tester.tap(find.byKey(const ValueKey('interactive-capsule')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('visible-card')), findsOneWidget);
        position.value = 11000;
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('visible-card')), findsNothing);
        expect(find.byKey(const ValueKey('interactive-capsule')), findsNothing);
        position.value = 1000;
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('interactive-capsule')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('visible-card')), findsNothing);
        expect(writes, 0);
      },
    );

    testWidgets(
      '$kind collapse preserves choice and cannot cause duplicate submission',
      (tester) async {
        final card = _card(kind), position = ValueNotifier(1000);
        addTearDown(position.dispose);
        var writes = 0;
        await tester.pumpWidget(
          _Harness(
            card: card,
            position: position,
            submit: (_, _, _) async => writes++,
          ),
        );
        await tester.tap(find.byKey(const ValueKey('interactive-capsule')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            ValueKey(kind == InteractiveKind.vote ? 'option-1' : 'star-5'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('dismiss-card')));
        await tester.pumpAndSettle();
        expect(writes, 0);
        await tester.tap(find.byKey(const ValueKey('interactive-capsule')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('submit')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('submit')));
        await tester.pumpAndSettle();
        expect(writes, 1);
        await tester.tap(find.byKey(const ValueKey('dismiss-card')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('interactive-capsule')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('submit')), findsNothing);
        expect(writes, 1);
      },
    );

    testWidgets(
      '$kind collapse while checking participation cancels the pending post',
      (tester) async {
        final card = _card(kind), position = ValueNotifier(1000);
        addTearDown(position.dispose);
        final pending = Completer<InteractiveDanmaku>();
        var writes = 0;
        await tester.pumpWidget(
          _Harness(
            card: card,
            position: position,
            read: () => pending.future,
            submit: (_, _, _) async => writes++,
          ),
        );
        await tester.tap(find.byKey(const ValueKey('interactive-capsule')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            ValueKey(kind == InteractiveKind.vote ? 'option-1' : 'star-5'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('submit')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('dismiss-card')));
        pending.complete(card);
        await tester.pumpAndSettle();
        expect(writes, 0);
        expect(
          find.byKey(const ValueKey('interactive-capsule')),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets(
    'four six-character options fit without scrolling and scale uniformly',
    (tester) async {
      final card = _card(InteractiveKind.vote, fourOptions: true),
          position = ValueNotifier(1000);
      addTearDown(position.dispose);
      double? textToCardRatio;
      for (final width in [240.0, 320.0, 360.0, 412.0]) {
        await tester.pumpWidget(const SizedBox.shrink());
        final capture = GlobalKey();
        await tester.pumpWidget(
          _Harness(
            card: card,
            position: position,
            width: width,
            captureKey: capture,
          ),
        );
        await tester.tap(find.byKey(const ValueKey('interactive-capsule')));
        await tester.pumpAndSettle();
        void expectAllVisible() {
          final viewport = tester.getRect(
            find.byKey(const ValueKey('card-content')),
          );
          for (var i = 1; i <= 4; i++) {
            final option = tester.getRect(find.byKey(ValueKey('option-$i')));
            expect(option.top, greaterThanOrEqualTo(viewport.top - .1));
            expect(option.bottom, lessThanOrEqualTo(viewport.bottom + .1));
            expect(
              find.byKey(ValueKey('option-$i')).hitTestable(),
              findsOneWidget,
            );
          }
        }

        expectAllVisible();
        expect(
          tester.widget<Text>(find.text('今天真的很香')).style!.fontSize,
          lessThanOrEqualTo(9),
        );
        final cardWidth = tester
            .getRect(find.byKey(const ValueKey('visible-card')))
            .width;
        final textHeight = tester.getRect(find.text(card.question)).height;
        textToCardRatio ??= textHeight / cardWidth;
        expect(textHeight / cardWidth, closeTo(textToCardRatio, .0001));
        await tester.tap(find.byKey(const ValueKey('option-4')));
        await tester.pumpAndSettle();
        expectAllVisible();
        expect(
          find.byKey(const ValueKey('submit')).hitTestable(),
          findsOneWidget,
        );
        await _capture(tester, capture, 'four-options-${width.toInt()}');
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'expansion and selected score survive fullscreen and portrait transitions',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final card = _card(InteractiveKind.grade), position = ValueNotifier(1000);
      addTearDown(position.dispose);
      await tester.pumpWidget(_Harness(card: card, position: position));
      await tester.tap(find.byKey(const ValueKey('interactive-capsule')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('star-5')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        _Harness(card: card, position: position, width: 960),
      );
      await tester.pumpAndSettle();
      expect(find.text('10 分'), findsOneWidget);
      expect(find.byKey(const ValueKey('submit')), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const ValueKey('visible-card'))).width,
        310,
      );
      await tester.pumpWidget(_Harness(card: card, position: position));
      await tester.pumpAndSettle();
      expect(find.text('10 分'), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const ValueKey('visible-card'))).width,
        closeTo(129.6, .01),
      );
      await tester.tap(find.byKey(const ValueKey('dismiss-card')));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('interactive-capsule'))).left,
        8,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('simultaneous capsules have separate slots above the controls', () {
    const viewport = Size(360, 202.5), capsule = Size(58, 22);
    final rect = Offset.zero & viewport;
    final first = InteractiveCardLayout(
      const Offset(.8, .8),
      rect,
      capsule: true,
    ).getPositionForChild(viewport, capsule);
    final second = InteractiveCardLayout(
      const Offset(.8, .8),
      rect,
      capsule: true,
      capsuleSlot: 1,
    ).getPositionForChild(viewport, capsule);
    expect(second.dy + capsule.height, lessThan(first.dy));
    expect(
      rect.contains(first + Offset(capsule.width, capsule.height)),
      isTrue,
    );
    expect(rect.contains(second), isTrue);
  });

  testWidgets(
    'card, typography and capsule grow with the video window up to desktop limits',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final card = _card(InteractiveKind.vote, fourOptions: true),
          position = ValueNotifier(1000);
      addTearDown(position.dispose);
      double previousWidth = 0, previousText = 0, previousCapsule = 0;
      for (final width in [
        240.0,
        360.0,
        480.0,
        500.0,
        501.0,
        640.0,
        860.0,
        1280.0,
        1920.0,
      ]) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          _Harness(card: card, position: position, width: width),
        );
        await tester.pumpAndSettle();
        final capsule = tester
            .getRect(find.byKey(const ValueKey('interactive-capsule')))
            .height;
        expect(capsule, greaterThanOrEqualTo(previousCapsule - .001));
        expect(capsule, lessThanOrEqualTo(30.81));
        previousCapsule = capsule;
        await tester.tap(find.byKey(const ValueKey('interactive-capsule')));
        await tester.pumpAndSettle();
        final surface = tester.getRect(
          find.byKey(const ValueKey('visible-card')),
        );
        final textHeight = tester.getRect(find.text('今天真的很香')).height;
        expect(surface.width, greaterThanOrEqualTo(previousWidth - .001));
        expect(surface.width, lessThanOrEqualTo(310.01));
        expect(textHeight, greaterThanOrEqualTo(previousText - .001));
        previousWidth = surface.width;
        previousText = textHeight;
        expect(tester.takeException(), isNull);
      }
      expect(previousWidth, 310);
      expect(tester.widget<Text>(find.text('今天真的很香')).style!.fontSize, 14);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        _Harness(card: card, position: position, width: 960, height: 180),
      );
      await tester.tap(find.byKey(const ValueKey('interactive-capsule')));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const ValueKey('visible-card'))).width,
        closeTo(115.2, .01),
      );
    },
  );

  testWidgets(
    'option counts are small bare numbers and refresh stays above full-width options',
    (tester) async {
      final card = _card(InteractiveKind.vote);
      card.extra['my_vote'] = 1;
      final options = card.extra['options'] as List;
      options[0]['cnt'] = 1234;
      options[1]['cnt'] = 567;
      final position = ValueNotifier(1000);
      addTearDown(position.dispose);
      await tester.pumpWidget(_Harness(card: card, position: position));
      await tester.tap(find.byKey(const ValueKey('interactive-capsule')));
      await tester.pumpAndSettle();
      final first = tester.widget<Text>(
        find.byKey(const ValueKey('option-count-1')),
      );
      final second = tester.widget<Text>(
        find.byKey(const ValueKey('option-count-2')),
      );
      expect(first.data, '1234');
      expect(second.data, '567');
      expect(
        first.style!.fontSize!,
        lessThan(tester.widget<Text>(find.text('真香')).style!.fontSize!),
      );
      final refresh = tester.getRect(find.byTooltip('刷新结果'));
      final close = tester.getRect(find.byKey(const ValueKey('dismiss-card')));
      final option = tester.getRect(find.byKey(const ValueKey('option-1')));
      expect(refresh.center.dy, close.center.dy);
      expect(refresh.bottom, lessThanOrEqualTo(option.top));
      expect(
        option.width,
        greaterThan(
          tester.getRect(find.byKey(const ValueKey('visible-card'))).width * .8,
        ),
      );
    },
  );
}
