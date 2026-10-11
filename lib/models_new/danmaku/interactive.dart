import 'dart:convert';
import 'dart:ui' show Offset;

import 'package:Pilipili/grpc/bilibili/community/service/dm/v1.pb.dart';

enum InteractiveKind { vote, grade }

class InteractiveDanmaku {
  final int aid, cid, cardId, progressMs;
  final String id;
  final InteractiveKind kind;
  final Map<String, dynamic> extra;
  const InteractiveDanmaku({
    required this.aid,
    required this.cid,
    required this.cardId,
    required this.progressMs,
    required this.id,
    required this.kind,
    required this.extra,
  });

  String get question =>
      (extra[kind == InteractiveKind.vote ? 'question' : 'msg'] ?? '')
          .toString();
  String get label => kind == InteractiveKind.vote ? '投票' : '评分';
  int get durationMs =>
      ((extra['duration'] as num?)?.toInt() ?? 5000).clamp(1, 600000);
  int get participation =>
      (extra[kind == InteractiveKind.vote ? 'my_vote' : 'mid_score'] as num?)
          ?.toInt() ??
      0;
  int? get participantCount =>
      (extra[kind == InteractiveKind.vote ? 'cnt' : 'count'] as num?)?.toInt();
  double? get averageScore => (extra['avg_score'] as num?)?.toDouble();
  List<Map<String, dynamic>> get options =>
      ((extra['options'] as List?) ?? const [])
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .where(
            (o) =>
                o['idx'] is int && (o['idx'] as int) > 0 && o['desc'] is String,
          )
          .toList();
  bool visibleAt(int milliseconds) =>
      milliseconds >= progressMs && milliseconds < progressMs + durationMs;

  // Same fallback and center anchor as Bilibili's command-card renderer.
  Offset get position {
    double axis(String relative, String legacy, double scale) {
      final percentage = (extra[relative] as num?)?.toDouble();
      final absolute = (extra[legacy] as num?)?.toDouble();
      final value = percentage != null && percentage != 0
          ? percentage
          : absolute == null
          ? 50.0
          : (absolute / scale * 100).roundToDouble();
      return !value.isFinite || value == 0
          ? 0.5
          : (value / 100).clamp(0.0, 1.0);
    }

    return Offset(axis('posX_2', 'posX', 667), axis('posY_2', 'posY', 375));
  }

  static List<InteractiveDanmaku> parse(
    DmWebViewReply reply, {
    required int aid,
    required int cid,
  }) {
    final result = <InteractiveDanmaku>[];
    for (final command in reply.commandDms) {
      try {
        final kind = switch (command.command) {
          '#VOTE#' => InteractiveKind.vote,
          '#GRADE#' => InteractiveKind.grade,
          _ => null,
        };
        if (kind == null) continue;
        final extra = Map<String, dynamic>.from(
          jsonDecode(command.extra) as Map,
        );
        final cardId =
            (extra[kind == InteractiveKind.vote ? 'vote_id' : 'grade_id']
                    as num?)
                ?.toInt();
        if (cardId == null || cardId <= 0) continue;
        final card = InteractiveDanmaku(
          aid: aid,
          cid: cid,
          cardId: cardId,
          progressMs: command.progress,
          id: command.id.toString(),
          kind: kind,
          extra: extra,
        );
        // Validate fields used by rendering independently of unrelated commands.
        if (card.durationMs <= 0 ||
            card.participation < 0 ||
            (card.participantCount ?? 0) < 0 ||
            card.averageScore?.isFinite == false ||
            !card.position.dx.isFinite ||
            !card.position.dy.isFinite) {
          continue;
        }
        if (card.kind == InteractiveKind.vote && card.options.isEmpty) continue;
        result.add(card);
      } catch (_) {
        /* Malformed or unsupported cards must not break playback. */
      }
    }
    return result;
  }
}
