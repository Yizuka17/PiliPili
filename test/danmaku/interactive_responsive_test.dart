import 'dart:io';
import 'dart:ui' as ui;

import 'package:Pilipili/models_new/danmaku/interactive.dart';
import 'package:Pilipili/pages/danmaku/interactive_card.dart';
import 'package:Pilipili/pages/danmaku/interactive_layout.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  setUpAll(() async {
    final font = Platform.environment['PILI_UI_FONT'];
    if (font != null) {
      final loader = FontLoader('Interactive UI QA')
        ..addFont(File(font).readAsBytes().then((b) => b.buffer.asByteData()));
      await loader.load();
    }
  });

  for (final width in [320.0, 360.0, 412.0, 960.0]) {
    for (final kind in InteractiveKind.values) {
      testWidgets(
        '$kind fits a $width player with accessible scrolling and pinned actions',
        (tester) async {
          final height = width * 9 / 16;
          tester.view.physicalSize = Size(width, width < 600 ? 800 : 600);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final card = InteractiveDanmaku(
            aid: 1,
            cid: 2,
            cardId: 3,
            progressMs: 0,
            id: 'responsive',
            kind: kind,
            extra: {
              'question': '看完这段视频，你觉得哪种方法更适合日常使用？',
              'msg': '看完这段视频，你觉得哪种方法更适合日常使用？',
              'cnt': 1234,
              'my_vote': 0,
              'mid_score': 0,
              'count': 1234,
              'avg_score': 8.6,
              'options': [
                for (var i = 1; i <= 6; i++)
                  {
                    'idx': i,
                    'desc': '选项 $i：保留完整说明文字，长内容换行后也能滚动查看',
                    'cnt': i * 10,
                  },
              ],
            },
          );
          var writes = 0;
          final boundary = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(
                useMaterial3: true,
                fontFamily: 'Interactive UI QA',
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xfffb7299),
                ),
              ),
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 800),
                    textScaler: TextScaler.linear(width == 320 ? 1.3 : 1),
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: RepaintBoundary(
                      key: boundary,
                      child: SizedBox(
                        key: const ValueKey('player'),
                        width: width,
                        height: height,
                        child: ColoredBox(
                          color: const Color(0xff20242c),
                          child: CustomSingleChildLayout(
                            delegate: InteractiveCardLayout(
                              const Offset(.9, .9),
                              Rect.fromLTWH(0, 0, width, height),
                            ),
                            child: InteractiveDanmakuCard(
                              initial: card,
                              visible: true,
                              progress: () => 1000,
                              canInteract: () => true,
                              read: () async => card,
                              submit: (_, _, _) async => writes++,
                              notify: (_) {},
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final player = tester.getRect(find.byKey(const ValueKey('player')));
          final surface = tester.getRect(
            find.byKey(const ValueKey('visible-card')),
          );
          expect(player.contains(surface.topLeft), isTrue);
          expect(player.contains(surface.bottomRight), isTrue);
          if (kind == InteractiveKind.vote) {
            await tester.scrollUntilVisible(
              find.byKey(const ValueKey('option-6')),
              60,
              scrollable: find.descendant(
                of: find.byKey(const ValueKey('card-content')),
                matching: find.byType(Scrollable),
              ),
            );
            await tester.tap(find.byKey(const ValueKey('option-6')));
          } else {
            await tester.ensureVisible(find.byKey(const ValueKey('star-5')));
            await tester.tap(find.byKey(const ValueKey('star-5')));
          }
          await tester.pumpAndSettle();
          expect(writes, 0);
          final submit = find.byKey(const ValueKey('submit'));
          expect(submit.hitTestable(), findsOneWidget);
          expect(
            find.byKey(const ValueKey('dismiss-card')).hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          if (Platform.environment['PILI_UI_CAPTURE'] == '1') {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory('build/ui-qa').create(recursive: true);
            await File('build/ui-qa/${kind.name}-${width.toInt()}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          }
          await tester.tap(submit);
          await tester.pumpAndSettle();
          expect(writes, 1);
          expect(submit, findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
