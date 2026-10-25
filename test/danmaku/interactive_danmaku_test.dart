import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:Pilipili/grpc/bilibili/community/service/dm/v1.pb.dart';
import 'package:Pilipili/models_new/danmaku/interactive.dart';
import 'package:Pilipili/pages/danmaku/interactive_card.dart';
import 'package:Pilipili/pages/danmaku/interactive_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

InteractiveDanmaku fixture(int index) {
  final records = jsonDecode(
    File('tool/danmaku_probe/checks/fixtures.json').readAsStringSync(),
  ) as List;
  return InteractiveDanmaku.parse(
    DmWebViewReply.fromBuffer(
      base64Decode(records[index]['rawProtobufBase64']),
    ),
    aid: index == 0 ? 1501546744 : 302830088,
    cid: index == 0 ? 1468652820 : 1610052434,
  ).single;
}

InteractiveDanmaku participation(InteractiveDanmaku card, int value) =>
    InteractiveDanmaku(
      aid: card.aid,
      cid: card.cid,
      cardId: card.cardId,
      progressMs: card.progressMs,
      id: card.id,
      kind: card.kind,
      extra: {
        ...card.extra,
        card.kind == InteractiveKind.vote ? 'my_vote' : 'mid_score': value,
      },
    );

Widget harness(
  InteractiveDanmaku card, {
  bool visible = true,
  Brightness brightness = Brightness.dark,
  required Future<InteractiveDanmaku> Function() read,
  required Future<void> Function(InteractiveDanmaku, int, int) submit,
}) => MaterialApp(
  theme: ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xfffb7299),
      brightness: brightness,
    ),
  ),
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 350,
        height: 450,
        child: Center(
          child: InteractiveDanmakuCard(
            key: ValueKey(card.id),
            initial: card,
            visible: visible,
            progress: () => card.progressMs,
            canInteract: () => true,
            read: read,
            submit: submit,
            notify: (_) {},
          ),
        ),
      ),
    ),
  ),
);

void main() {
  test('uses generated protobuf and official percentage/legacy coordinate fallback', () {
    final vote = fixture(0), grade = fixture(1);
    expect(vote.cardId, 17977117);
    expect(vote.progressMs, 0);
    expect(vote.position, const Offset(1, 1));
    expect(grade.cardId, 397256);
    expect(grade.position.dx, 0.75);
    expect(grade.position.dy, 1);
    expect(grade.visibleAt(68000), isTrue);
    expect(grade.visibleAt(80000), isFalse);
  });

  test('malformed commands do not remove other supported cards', () {
    final records = jsonDecode(
      File('tool/danmaku_probe/checks/fixtures.json').readAsStringSync(),
    ) as List;
    final reply = DmWebViewReply.fromBuffer(
      base64Decode(records[1]['rawProtobufBase64']),
    );
    reply.commandDms.insert(0, CommandDm(command: '#VOTE#', extra: '{invalid'));
    expect(
      InteractiveDanmaku.parse(reply, aid: 1, cid: 2).single.kind,
      InteractiveKind.grade,
    );
  });

  test('positions map to video content with letterboxing and cropping', () {
    final contained = interactiveVideoFrame(
      const Size(1000, 1000),
      const Size(1920, 1080),
      BoxFit.contain,
      Alignment.center,
    );
    expect(contained.left, closeTo(0, .001));
    expect(contained.top, closeTo(218.75, .001));
    expect(contained.width, closeTo(1000, .001));
    expect(contained.height, closeTo(562.5, .001));
    final cropped = interactiveVideoFrame(
      const Size(1000, 1000),
      const Size(1920, 1080),
      BoxFit.cover,
      Alignment.center,
    );
    expect(cropped.left, closeTo(-388.8889, 0.001));
    expect(cropped.height, 1000);
    final layout = InteractiveCardLayout(const Offset(1, 1), contained);
    final offset = layout.getPositionForChild(
      const Size(1000, 1000),
      const Size(310, 140),
    );
    expect(offset.dx, closeTo(682, .001));
    expect(offset.dy, closeTo(633.25, .001));
    final centered = InteractiveCardLayout(const Offset(.5, .5), cropped);
    final center = centered.getPositionForChild(
      const Size(1000, 1000),
      const Size(310, 140),
    );
    expect(center.dx, closeTo(345, .001));
    expect(center.dy, closeTo(430, .001));
    final zoomed = interactiveVideoFrame(
      const Size(1000, 1000),
      const Size(1920, 1080),
      BoxFit.contain,
      Alignment.center,
      transform: Matrix4.diagonal3Values(2, 2, 1),
    );
    expect(zoomed.width, closeTo(2000, .001));
    expect(zoomed.top, closeTo(437.5, .001));
    const outside = InteractiveCardLayout(
      Offset(.5, .5),
      Rect.fromLTWH(2000, 2000, 500, 500),
    );
    expect(
      outside.getPositionForChild(const Size(1000, 1000), Size.zero),
      Offset.zero,
    );
  });

  for (final index in [0, 1]) {
    testWidgets(
      'switching video before participation read completes prevents a stale submission ($index)',
      (tester) async {
        final card = fixture(index);
        final beforePost = Completer<InteractiveDanmaku>();
        var writes = 0;
        await tester.pumpWidget(
          harness(
            card,
            read: () => beforePost.future,
            submit: (_, _, _) async {
              writes++;
            },
          ),
        );
        await tester.tap(
          find.byKey(ValueKey(index == 0 ? 'option-1' : 'star-5')),
        );
        await tester.pumpAndSettle();
        final submit = find.byKey(const ValueKey('submit'));
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pump();
        await tester.pumpWidget(const SizedBox.shrink());
        beforePost.complete(card);
        await tester.pumpAndSettle();
        expect(writes, 0);
      },
    );

    testWidgets(
      '${index == 0 ? 'vote' : 'grade'} selection does not submit; acknowledge hides submit even with stale refresh',
      (tester) async {
        final card = fixture(index);
        final pending = Completer<InteractiveDanmaku>();
        var reads = 0, writes = 0;
        await tester.pumpWidget(
          harness(
            card,
            read: () {
              reads++;
              return reads == 2 ? pending.future : Future.value(card);
            },
            submit: (fresh, choice, progress) async {
              expect(fresh.aid, card.aid);
              expect(fresh.cid, card.cid);
              expect(choice, index == 0 ? 1 : 10);
              expect(progress, card.progressMs);
              writes++;
            },
          ),
        );
        expect(find.byKey(const ValueKey('submit')), findsNothing);
        await tester.tap(
          find.byKey(ValueKey(index == 0 ? 'option-1' : 'star-5')),
        );
        await tester.pumpAndSettle();
        expect(writes, 0);
        expect(find.textContaining('请选择'), findsNothing);
        expect(find.textContaining('已选择'), findsNothing);
        final submit = find.byKey(const ValueKey('submit'));
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pump();
        expect(writes, 1);
        expect(reads, 2);
        expect(submit, findsNothing);
        pending.complete(card);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('刷新结果'));
        await tester.pumpAndSettle();
        expect(writes, 1);
        expect(submit, findsNothing);
        if (index == 1) expect(find.text('10 分'), findsOneWidget);
      },
    );

    testWidgets(
      '${index == 0 ? 'vote' : 'grade'} participation and dismissal survive resize/visibility/theme changes',
      (tester) async {
        final card = participation(fixture(index), index == 0 ? 1 : 8);
        var writes = 0;
        Widget page({
          bool visible = true,
          Brightness brightness = Brightness.dark,
        }) => harness(
          card,
          visible: visible,
          brightness: brightness,
          read: () async => card,
          submit: (_, _, _) async {
            writes++;
          },
        );
        await tester.pumpWidget(page());
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('submit')), findsNothing);
        if (index == 0) {
          expect(find.text('有'), findsOneWidget);
        } else {
          expect(find.text('8 分'), findsOneWidget);
          final y = tester.getCenter(find.byKey(const ValueKey('star-1'))).dy;
          expect(tester.getCenter(find.byKey(const ValueKey('star-5'))).dy, y);
          expect(
            tester
                .widget<IconButton>(find.byKey(const ValueKey('star-4')))
                .onPressed,
            isNull,
          );
        }
        await tester.tap(find.byKey(const ValueKey('dismiss-card')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('visible-card')), findsNothing);
        await tester.pumpWidget(page(visible: false));
        await tester.pumpAndSettle();
        await tester.pumpWidget(page(brightness: Brightness.light));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('visible-card')), findsNothing);
        expect(writes, 0);
      },
    );
  }
}
