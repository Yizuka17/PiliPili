import 'package:Pilipili/grpc/bilibili/community/service/dm/v1.pb.dart';
import 'package:Pilipili/http/api.dart';
import 'package:Pilipili/http/init.dart';
import 'package:Pilipili/models_new/danmaku/interactive.dart';
import 'package:Pilipili/utils/accounts/account.dart';
import 'package:dio/dio.dart';

abstract final class InteractiveDanmakuHttp {
  static Future<List<InteractiveDanmaku>> read({
    required int aid,
    required int cid,
    required Account account,
    CancelToken? cancelToken,
  }) async {
    final response = await Request().get(
      Api.interactiveDanmakuView,
      queryParameters: {
        'type': 1,
        'pid': aid,
        'oid': cid,
        '_': DateTime.now().millisecondsSinceEpoch,
      },
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: false,
        extra: {'account': account},
      ),
      cancelToken: cancelToken,
    );
    if (response.data case final List<int> bytes
        when response.statusCode == 200) {
      return InteractiveDanmaku.parse(
        DmWebViewReply.fromBuffer(bytes),
        aid: aid,
        cid: cid,
      );
    }
    throw const InteractiveRequestFailure('无法读取互动卡片，请稍后再试');
  }

  static Future<void> submit(
    InteractiveDanmaku card,
    int choice,
    int progress, {
    required Account account,
  }) async {
    if (!account.isLogin) throw const InteractiveRequestFailure('请先登录');
    if (card.participation != 0) {
      throw const InteractiveRequestFailure('请刷新卡片查看结果');
    }
    if (!card.visibleAt(progress)) {
      throw const InteractiveRequestFailure('请回到卡片出现的位置');
    }
    final vote = card.kind == InteractiveKind.vote;
    if (vote
        ? !card.options.any(
            (o) => o['idx'] == choice && o['has_self_def'] != true,
          )
        : choice < 2 || choice > 10 || choice.isOdd) {
      throw const InteractiveRequestFailure('选择无效');
    }
    final response = await Request().post(
      vote ? Api.interactiveDanmakuVote : Api.interactiveDanmakuGrade,
      data: {
        'aid': card.aid,
        'cid': card.cid,
        'progress': progress,
        'polaris_app_id': 100,
        'polaris_platform': 5,
        'spmid': '333.788.0.0',
        'from_spmid': '333.788.0.0',
        'csrf': account.csrf,
        if (vote) ...{
          'vote_id': card.cardId,
          'vote_type': card.extra['vote_type'] ?? 0,
          'cmd_id_str': card.id,
          'option_id': choice,
          'has_self_def': 0,
        } else ...{
          'grade_id': card.cardId,
          'grade_score': choice,
        },
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        followRedirects: false,
        extra: {'account': account, 'disableRetry': true},
      ),
    );
    if (response.data is! Map || response.data['code'] != 0) {
      throw const InteractiveRequestFailure('提交结果未确认，请刷新卡片后再试');
    }
  }
}

class InteractiveRequestFailure implements Exception {
  final String message;
  const InteractiveRequestFailure(this.message);
  @override
  String toString() => message;
}
