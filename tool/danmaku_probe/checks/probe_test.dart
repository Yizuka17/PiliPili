import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pilipili_danmaku_probe/client.dart';
import 'package:pilipili_danmaku_probe/main.dart';

CommandCard fixture(int index) {
  final records =
      jsonDecode(File('checks/fixtures.json').readAsStringSync()) as List;
  return parseCard(
    base64Decode(records[index]['rawProtobufBase64'] as String),
    samples[index],
  );
}

CommandCard participated(CommandCard card, int value) =>
    CommandCard(card.sample, card.id, card.progressMs, {
      ...card.extra,
      card.sample.kind == CardKind.vote ? 'my_vote' : 'mid_score': value,
    });

List<CommandCard> otherVideoCards() {
  final record =
      jsonDecode(File('checks/other_video.json').readAsStringSync()) as Map;
  return parseCards(
    base64Decode(record['rawProtobufBase64'] as String),
    record['bvid'] as String,
    record['aid'] as int,
    record['cid'] as int,
  );
}

Widget harness(
  CommandCard card, {
  Brightness brightness = Brightness.light,
  required Future<CommandCard> Function() read,
  required Future<Map<String, dynamic>> Function(CommandCard, int, int) submit,
}) => MaterialApp(
  theme: probeTheme(brightness),
  home: Scaffold(
    body: SingleChildScrollView(
      child: SizedBox(
        width: 480,
        child: CardPanel(initial: card, read: read, submit: submit),
      ),
    ),
  ),
);

void main() {
  for (final initial in otherVideoCards()) {
    testWidgets(
      '${initial.sample.label} inherits application colors without resetting selection or posting',
      (tester) async {
        var writes = 0;
        double contrast(Color a, Color b) {
          final x = a.computeLuminance(), y = b.computeLuminance();
          return ((x > y ? x : y) + 0.05) / ((x > y ? y : x) + 0.05);
        }

        Widget themed(Brightness brightness) => harness(
          initial,
          brightness: brightness,
          read: () async => initial,
          submit: (_, __, ___) async {
            writes++;
            return {'code': 0};
          },
        );
        await tester.pumpWidget(themed(Brightness.light));
        await tester.tap(
          find.byKey(
            ValueKey(
              initial.sample.kind == CardKind.vote ? 'option-1' : 'star-4',
            ),
          ),
        );
        await tester.pumpAndSettle();
        Color? previousBackground;
        for (final brightness in [
          Brightness.light,
          Brightness.dark,
          Brightness.light,
        ]) {
          await tester.pumpWidget(themed(brightness));
          await tester.pumpAndSettle();
          final card = tester.widget<Container>(
            find.byKey(const ValueKey('visible-card')),
          );
          final background = (card.decoration as BoxDecoration).color!;
          final title = tester.widget<Text>(find.text(initial.question));
          expect(
            contrast(title.style!.color!, background),
            greaterThanOrEqualTo(4.5),
          );
          if (previousBackground != null)
            expect(background, isNot(previousBackground));
          previousBackground = background;
          expect(find.textContaining('请选择'), findsNothing);
          expect(find.byKey(const ValueKey('submit')), findsOneWidget);
          final submit = tester.widget<FilledButton>(
            find.byKey(const ValueKey('submit')),
          );
          expect(
            contrast(
              submit.style!.foregroundColor!.resolve({})!,
              submit.style!.backgroundColor!.resolve({})!,
            ),
            greaterThanOrEqualTo(4.5),
          );
          if (initial.sample.kind == CardKind.vote) {
            expect(find.textContaining('内容很小众 ✓'), findsOneWidget);
          } else {
            expect(
              (tester
                          .widget<IconButton>(
                            find.byKey(const ValueKey('star-4')),
                          )
                          .icon
                      as Icon)
                  .icon,
              Icons.star_rounded,
            );
            expect(
              (tester
                          .widget<IconButton>(
                            find.byKey(const ValueKey('star-5')),
                          )
                          .icon
                      as Icon)
                  .icon,
              Icons.star_outline_rounded,
            );
          }
          expect(writes, 0);
        }
      },
    );
  }

  test('video input accepts BV and full links with a specific part', () {
    expect(VideoTarget.parse('BV11d6rB4Evy').page, 1);
    final target = VideoTarget.parse(
      'https://www.bilibili.com/video/BV11d6rB4Evy/?p=2&share_source=copy',
    );
    expect(target.bvid, 'BV11d6rB4Evy');
    expect(target.page, 2);
    for (final invalid in [
      'https://example.com/video/BV11d6rB4Evy',
      'https://www.bilibili.com/video/BV11d6rB4Evy?p=0',
      'BVinvalid',
      'https://b23.tv/short',
    ]) {
      expect(() => VideoTarget.parse(invalid), throwsA(isA<ProbeFailure>()));
    }
  });

  test(
    'discovers both card types from another real video without fixed IDs',
    () {
      final cards = otherVideoCards();
      expect(cards.length, 2);
      expect(cards[0].sample.kind, CardKind.vote);
      expect(cards[0].sample.cardId, 18272738);
      expect(cards[0].progressMs, 8700);
      expect(cards[1].sample.kind, CardKind.grade);
      expect(cards[1].sample.cardId, 6432772);
      expect(cards[1].progressMs, 158200);
      expect(cards.every((c) => c.participation == 0), isTrue);
      expect(cards[0].sample.cid, cards[1].sample.cid);
      expect(parseCards(Uint8List(0), 'BV11d6rB4Evy', 1, 1), isEmpty);
    },
  );

  for (final initial in otherVideoCards()) {
    testWidgets(
      '${initial.sample.label} shows an accent submit only after selection; changing choice does not submit',
      (tester) async {
        var writes = 0;
        final chosen = initial.sample.kind == CardKind.vote ? 2 : 8;
        await tester.pumpWidget(
          harness(
            initial,
            read: () async =>
                writes == 0 ? initial : participated(initial, chosen),
            submit: (card, value, progress) async {
              expect(card.sample.cardId, initial.sample.cardId);
              expect(value, chosen);
              expect(progress, initial.progressMs);
              writes++;
              return {'code': 0};
            },
          ),
        );
        expect(find.byKey(const ValueKey('submit')), findsNothing);
        for (final selection
            in initial.sample.kind == CardKind.vote
                ? ['option-1', 'option-2']
                : ['star-5', 'star-4']) {
          final option = find.byKey(ValueKey(selection));
          await tester.ensureVisible(option);
          await tester.tap(option);
          await tester.pumpAndSettle();
          expect(writes, 0);
          expect(find.textContaining('已'), findsNothing);
        }
        final submit = find.byKey(const ValueKey('submit'));
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('visible-card')),
            matching: submit,
          ),
          findsOneWidget,
        );
        expect(find.text('提交'), findsOneWidget);
        final button = tester.widget<FilledButton>(submit);
        expect(
          button.style!.backgroundColor!.resolve({}),
          Theme.of(tester.element(submit)).colorScheme.primary,
        );
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(writes, 1);
        expect(submit, findsNothing);
      },
    );
  }

  test('decodes real vote response including omitted zero progress', () {
    final card = fixture(0);
    expect(card.question, '测试用，看看有没有效果');
    expect(card.progressMs, 0);
    expect(card.participation, 0);
    expect(card.options.length, 3);
    expect(card.visibleAt(0), isTrue);
    expect(card.visibleAt(card.durationMs), isFalse);
  });

  test('decodes real grade response and timing boundaries', () {
    final card = fixture(1);
    expect(card.question, '给课程打个分吧');
    expect(card.progressMs, 68000);
    expect(card.durationMs, 12000);
    expect(card.participation, 0);
    expect(card.visibleAt(67999), isFalse);
    expect(card.visibleAt(68000), isTrue);
    expect(card.visibleAt(79999), isTrue);
    expect(card.visibleAt(80000), isFalse);
  });

  test('rejects truncated network response', () {
    expect(
      () => decodeFields(Uint8List.fromList([0x4a, 10, 1])),
      throwsA(isA<ProbeFailure>()),
    );
  });

  testWidgets('selecting and cancelling a vote never calls submission API', (
    tester,
  ) async {
    final card = fixture(0);
    var writes = 0;
    await tester.pumpWidget(
      harness(
        card,
        read: () async => card,
        submit: (_, __, ___) async {
          writes++;
          return {'code': 0};
        },
      ),
    );
    expect(find.byKey(const ValueKey('submit')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('option-1')));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.textContaining('已选择'), findsNothing);
    expect(find.byKey(const ValueKey('submit')), findsOneWidget);
    await tester.ensureVisible(find.text('取消选择'));
    await tester.tap(find.text('取消选择'));
    await tester.pumpAndSettle();
    expect(find.textContaining('请选择'), findsNothing);
    expect(card.participation, 0);
    expect(find.byKey(const ValueKey('submit')), findsNothing);
  });

  testWidgets(
    'real grade waits for server readback and disables duplicate submit',
    (tester) async {
      final card = fixture(1);
      var writes = 0, reads = 0;
      await tester.pumpWidget(
        harness(
          card,
          read: () async {
            reads++;
            return writes == 0 ? card : participated(card, 10);
          },
          submit: (fresh, value, progressMs) async {
            expect(fresh.participation, 0);
            expect(value, 10);
            expect(progressMs, card.progressMs);
            writes++;
            return {'code': 0};
          },
        ),
      );
      await tester.tap(find.byKey(const ValueKey('star-5')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('submit')));
      await tester.tap(find.byKey(const ValueKey('submit')));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(reads, 2);
      expect(find.text('评分成功'), findsOneWidget);
      expect(find.text('10 分'), findsOneWidget);
      final starY = tester.getCenter(find.byKey(const ValueKey('star-1'))).dy;
      for (var star = 2; star <= 5; star++) {
        expect(tester.getCenter(find.byKey(ValueKey('star-$star'))).dy, starY);
      }
      expect(
        tester.getCenter(find.byKey(const ValueKey('personal-score'))).dy,
        closeTo(starY, 1),
      );
      expect(find.byKey(const ValueKey('submit')), findsNothing);
    },
  );

  for (final index in [0, 1]) {
    testWidgets(
      '${samples[index].label} removes submit on acknowledgement before delayed readback and stays hidden after stale refresh',
      (tester) async {
        final card = fixture(index);
        final delayed = Completer<CommandCard>();
        var writes = 0, reads = 0;
        await tester.pumpWidget(
          harness(
            card,
            read: () {
              reads++;
              return reads == 2 ? delayed.future : Future.value(card);
            },
            submit: (_, __, ___) async {
              writes++;
              return {'code': 0};
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
        expect(writes, 1);
        expect(reads, 2);
        expect(submit, findsNothing);
        delayed.complete(card);
        await tester.pumpAndSettle();
        expect(submit, findsNothing);
        final refresh = find.byTooltip('重新读取服务器状态');
        await tester.ensureVisible(refresh);
        await tester.tap(refresh);
        await tester.pumpAndSettle();
        expect(submit, findsNothing);
        expect(find.text('取消选择'), findsNothing);
        expect(writes, 1);
        if (index == 0) {
          expect(find.textContaining('有 ✓'), findsOneWidget);
          expect(
            tester
                .widget<OutlinedButton>(find.byKey(const ValueKey('option-1')))
                .onPressed,
            isNull,
          );
        } else {
          expect(
            (tester
                        .widget<IconButton>(
                          find.byKey(const ValueKey('star-5')),
                        )
                        .icon
                    as Icon)
                .icon,
            Icons.star_rounded,
          );
          expect(
            tester
                .widget<IconButton>(find.byKey(const ValueKey('star-5')))
                .onPressed,
            isNull,
          );
        }
      },
    );
  }

  testWidgets('participation discovered before submission prevents mutation', (
    tester,
  ) async {
    final card = fixture(0);
    var writes = 0;
    await tester.pumpWidget(
      harness(
        card,
        read: () async => participated(card, 1),
        submit: (_, __, ___) async {
          writes++;
          return {'code': 0};
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('option-1')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('submit')));
    await tester.tap(find.byKey(const ValueKey('submit')));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('option-1')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('native timeline hides at end and restores at start', (
    tester,
  ) async {
    final card = fixture(1);
    await tester.pumpWidget(
      harness(
        card,
        read: () async => card,
        submit: (_, __, ___) async => {'code': 0},
      ),
    );
    await tester.ensureVisible(find.text('结束时'));
    await tester.tap(find.text('结束时'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('hidden-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('visible-card')), findsNothing);
    await tester.tap(find.text('出现时'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('visible-card')), findsOneWidget);
  });

  for (final index in [0, 1]) {
    testWidgets(
      'refresh shows server statistics for ${samples[index].label} without submitting',
      (tester) async {
        final initial = fixture(index);
        final updated = CommandCard(
          initial.sample,
          initial.id,
          initial.progressMs,
          {
            ...initial.extra,
            if (index == 0) ...{
              'my_vote': 1,
              'cnt': 156,
              'options': [
                {...initial.options[0], 'cnt': 46},
                {...initial.options[1], 'cnt': 74},
                {...initial.options[2], 'cnt': 36},
              ],
            } else ...{
              'mid_score': 8,
              'count': 2677,
              'avg_score': 9.1,
            },
          },
        );
        var writes = 0;
        await tester.pumpWidget(
          harness(
            initial,
            read: () async => updated,
            submit: (_, __, ___) async {
              writes++;
              return {'code': 0};
            },
          ),
        );
        final refresh = find.byTooltip('重新读取服务器状态');
        await tester.ensureVisible(refresh);
        await tester.tap(refresh);
        await tester.pumpAndSettle();
        final statistics = tester
            .widget<Text>(find.byKey(const ValueKey('server-statistics')))
            .data!;
        if (index == 0) {
          expect(statistics, contains('共 156 票'));
          expect(statistics, contains('有：46 票'));
          expect(statistics, contains('没有：74 票'));
          expect(statistics, contains('其他,请补充：36 票'));
        } else {
          expect(statistics, contains('2677 人评分'));
          expect(statistics, contains('平均 9.1/10（4.55/5 星）'));
          expect(find.text('8 分'), findsOneWidget);
          for (var star = 1; star <= 5; star++) {
            final button = tester.widget<IconButton>(
              find.byKey(ValueKey('star-$star')),
            );
            expect(button.onPressed, isNull);
            expect(
              (button.icon as Icon).icon,
              star <= 4 ? Icons.star_rounded : Icons.star_outline_rounded,
            );
          }
        }
        expect(writes, 0);
        expect(find.byKey(const ValueKey('submit')), findsNothing);
        await tester.ensureVisible(find.text('结束时'));
        await tester.tap(find.text('结束时'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('hidden-card')), findsOneWidget);
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('server-statistics')))
              .data,
          statistics,
        );
      },
    );

    for (final hasParticipated in [false, true]) {
      testWidgets(
        'dismiss ${samples[index].label} persists across seek and refresh, participated=$hasParticipated',
        (tester) async {
          final card = hasParticipated
              ? participated(fixture(index), index == 0 ? 1 : 8)
              : fixture(index);
          var writes = 0;
          await tester.pumpWidget(
            harness(
              card,
              read: () async => card,
              submit: (_, __, ___) async {
                writes++;
                return {'code': 0};
              },
            ),
          );
          if (hasParticipated) {
            expect(find.byKey(const ValueKey('submit')), findsNothing);
            if (index == 0) {
              expect(find.textContaining('有 ✓'), findsOneWidget);
              for (final option in card.options) {
                expect(
                  tester
                      .widget<OutlinedButton>(
                        find.byKey(ValueKey('option-${option['idx']}')),
                      )
                      .onPressed,
                  isNull,
                );
              }
            } else {
              for (var star = 1; star <= 5; star++) {
                final button = tester.widget<IconButton>(
                  find.byKey(ValueKey('star-$star')),
                );
                expect(button.onPressed, isNull);
                expect(
                  (button.icon as Icon).icon,
                  star <= 4 ? Icons.star_rounded : Icons.star_outline_rounded,
                );
              }
            }
          }
          final labels = tester
              .widgetList<Text>(find.byType(Text))
              .map((t) => t.data ?? '')
              .join('\n');
          expect(labels, isNot(contains('已')));
          expect(labels, isNot(contains('·')));
          await tester.tap(find.byKey(const ValueKey('dismiss-card')));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('visible-card')), findsNothing);
          expect(find.byKey(const ValueKey('hidden-card')), findsOneWidget);
          await tester.ensureVisible(find.text('出现时'));
          await tester.tap(find.text('出现时'));
          await tester.pumpAndSettle();
          final refresh = find.byTooltip('重新读取服务器状态');
          await tester.ensureVisible(refresh);
          await tester.tap(refresh);
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('visible-card')), findsNothing);
          expect(writes, 0);
          expect(find.byKey(const ValueKey('submit')), findsNothing);
        },
      );
    }
  }
}
