import 'dart:io';
import 'dart:ui' as ui;

import 'package:Pilipili/models_new/danmaku/interactive.dart';
import 'package:Pilipili/pages/danmaku/interactive_card.dart';
import 'package:Pilipili/pages/danmaku/interactive_layout.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final path = Platform.environment['PILI_UI_FONT'];
    if (path != null) {
      await (FontLoader('Portrait QA')..addFont(
            File(path).readAsBytes().then((b) => b.buffer.asByteData()),
          ))
          .load();
    }
  });
  for (final width in [320.0, 360.0, 412.0]) {
    for (final kind in InteractiveKind.values) {
      testWidgets(
        '$kind stays below one fifth of a $width portrait detail video',
        (tester) async {
          final size = Size(width, width * 9 / 16);
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final card = InteractiveDanmaku(
            aid: 1,
            cid: 2,
            cardId: 3,
            progressMs: 0,
            id: 'portrait-size',
            kind: kind,
            extra: {
              'question': '今天的大盘？',
              'msg': '这段视频怎么样？',
              'cnt': 1973,
              'count': 1973,
              'avg_score': 8.6,
              'options': [
                {'idx': 1, 'desc': '真香'},
                {'idx': 2, 'desc': '太臭啦'},
              ],
            },
          );
          var writes = 0;
          final capture = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(
                useMaterial3: true,
                fontFamily: 'Portrait QA',
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xfffb7299),
                ),
              ),
              home: Scaffold(
                body: MediaQuery(
                  data: const MediaQueryData(
                    size: Size(360, 800),
                    textScaler: TextScaler.linear(1.3),
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: RepaintBoundary(
                      key: capture,
                      child: SizedBox.fromSize(
                        size: size,
                        child: ColoredBox(
                          color: const Color(0xff34383e),
                          child: CustomSingleChildLayout(
                            delegate: InteractiveCardLayout(
                              const Offset(.8, .65),
                              Offset.zero & size,
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
          await tester.tap(find.byKey(const ValueKey('interactive-capsule')));
          await tester.pumpAndSettle();
          if (Platform.environment['PILI_UI_CAPTURE'] == '1') {
            await tester.runAsync(() async {
              final image =
                  await (capture.currentContext!.findRenderObject()!
                          as RenderRepaintBoundary)
                      .toImage(pixelRatio: 3);
              final data = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final directory =
                  Platform.environment['PILI_UI_OUTPUT'] ??
                  'build/ui-qa/portrait-after';
              await Directory(directory).create(recursive: true);
              await File('$directory/${kind.name}-${width.toInt()}.png')
                  .writeAsBytes(data!.buffer.asUint8List());
              image.dispose();
            });
          }
          void expectSmall() {
            final cardSize = tester
                .getRect(find.byKey(const ValueKey('visible-card')))
                .size;
            expect(cardSize.width, lessThanOrEqualTo(size.width * .4));
            expect(cardSize.height, lessThanOrEqualTo(size.height * .55));
            expect(
              cardSize.width * cardSize.height / (size.width * size.height),
              lessThanOrEqualTo(.20),
            );
          }

          expectSmall();
          expect(find.text('投票'), findsNothing);
          expect(find.text('评分'), findsNothing);
          expect(
            find.text(kind == InteractiveKind.vote ? '今天的大盘？' : '这段视频怎么样？'),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(
              ValueKey(kind == InteractiveKind.vote ? 'option-1' : 'star-5'),
            ),
          );
          await tester.pumpAndSettle();
          expectSmall();
          if (kind == InteractiveKind.vote) {
            final content = tester.getRect(
              find.byKey(const ValueKey('card-content')),
            );
            final second = tester.getRect(
              find.byKey(const ValueKey('option-2')),
            );
            expect(second.top, greaterThanOrEqualTo(content.top));
            expect(second.bottom, lessThanOrEqualTo(content.bottom + .1));
          }
          expect(
            find.byKey(const ValueKey('submit')).hitTestable(),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const ValueKey('submit')));
          await tester.pumpAndSettle();
          expect(writes, 1);
          expectSmall();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
