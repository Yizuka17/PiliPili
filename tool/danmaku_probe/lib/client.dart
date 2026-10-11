import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

enum CardKind { vote, grade }

class Sample {
  final CardKind kind;
  final String bvid;
  final int aid, cid, cardId;
  const Sample(this.kind, this.bvid, this.aid, this.cid, this.cardId);
  String get command => kind == CardKind.vote ? '#VOTE#' : '#GRADE#';
  String get label => kind == CardKind.vote ? '投票' : '打星';
}

const samples = [
  Sample(CardKind.vote, 'BV1dS421w7Bf', 1501546744, 1468652820, 17977117),
  Sample(CardKind.grade, 'BV1rP41137E6', 302830088, 1610052434, 397256),
];

class CommandCard {
  final Sample sample;
  final String id;
  final int progressMs;
  final Map<String, dynamic> extra;
  const CommandCard(this.sample, this.id, this.progressMs, this.extra);
  String get question => (extra['question'] ?? extra['msg'] ?? '').toString();
  int get durationMs => (extra['duration'] as num?)?.toInt() ?? 5000;
  int get participation =>
      ((extra[sample.kind == CardKind.vote ? 'my_vote' : 'mid_score']) as num?)
          ?.toInt() ??
      0;
  List<Map<String, dynamic>> get options =>
      ((extra['options'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  int? get participantCount =>
      (extra[sample.kind == CardKind.vote ? 'cnt' : 'count'] as num?)?.toInt();
  double? get averageScore => (extra['avg_score'] as num?)?.toDouble();
  bool visibleAt(int ms) => ms >= progressMs && ms < progressMs + durationMs;
}

class ProbeFailure implements Exception {
  final String message;
  const ProbeFailure(this.message);
  @override
  String toString() => message;
}

class VideoSource {
  final String url;
  final int durationMs;
  const VideoSource(this.url, this.durationMs);
}

class VideoTarget {
  final String bvid;
  final int page;
  const VideoTarget(this.bvid, this.page);

  static VideoTarget parse(String input) {
    final value = input.trim();
    final direct = RegExp(r'^BV[0-9A-Za-z]{10}$');
    if (direct.hasMatch(value)) return VideoTarget(value, 1);
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        ![
          'www.bilibili.com',
          'bilibili.com',
          'm.bilibili.com',
        ].contains(uri.host)) {
      throw const ProbeFailure('请输入 BV 号或 B站视频完整链接');
    }
    final segments = uri.pathSegments;
    final bvid = segments.length >= 2 && segments[0] == 'video'
        ? segments[1]
        : '';
    final page = int.tryParse(uri.queryParameters['p'] ?? '1');
    if (!direct.hasMatch(bvid) || page == null || page < 1) {
      throw const ProbeFailure('视频链接或分 P 编号不正确');
    }
    return VideoTarget(bvid, page);
  }
}

// Only the fields needed by the project's CommandDm/DmWebViewReply schema.
Map<int, List<Object>> decodeFields(Uint8List bytes) {
  var offset = 0;
  int varint() {
    var value = 0, shift = 0;
    while (offset < bytes.length && shift < 70) {
      final byte = bytes[offset++];
      value |= (byte & 127) << shift;
      if (byte & 128 == 0) return value;
      shift += 7;
    }
    throw const ProbeFailure('弹幕数据损坏：无效整数');
  }

  final fields = <int, List<Object>>{};
  while (offset < bytes.length) {
    final tag = varint();
    final wire = tag & 7;
    final number = tag >> 3;
    if (number == 0) throw const ProbeFailure('弹幕数据不是有效 Protobuf');
    Object value;
    if (wire == 0) {
      value = varint();
    } else if (wire == 2 || wire == 1 || wire == 5) {
      final length = wire == 2 ? varint() : (wire == 1 ? 8 : 4);
      if (length < 0 || offset + length > bytes.length) {
        throw const ProbeFailure('弹幕数据损坏：字段截断');
      }
      value = Uint8List.sublistView(bytes, offset, offset + length);
      offset += length;
    } else {
      throw const ProbeFailure('弹幕数据包含不支持的字段');
    }
    (fields[number] ??= []).add(value);
  }
  return fields;
}

List<CommandCard> parseCards(Uint8List bytes, String bvid, int aid, int cid) {
  final fields = decodeFields(bytes);
  final cards = <CommandCard>[];
  for (final raw in fields[9] ?? const []) {
    final command = decodeFields(raw as Uint8List);
    String string(int n) => command[n]?.first is Uint8List
        ? utf8.decode(command[n]!.first as Uint8List)
        : '';
    final kind = switch (string(4)) {
      '#VOTE#' => CardKind.vote,
      '#GRADE#' => CardKind.grade,
      _ => null,
    };
    if (kind == null) continue;
    final extra = Map<String, dynamic>.from(jsonDecode(string(9)) as Map);
    final cardId =
        (extra[kind == CardKind.vote ? 'vote_id' : 'grade_id'] as num?)
            ?.toInt();
    if (cardId == null || cardId <= 0) continue;
    cards.add(
      CommandCard(
        Sample(kind, bvid, aid, cid, cardId),
        command[1]!.first.toString(),
        command[6]?.first as int? ?? 0,
        extra,
      ),
    );
  }
  return cards;
}

CommandCard parseCard(Uint8List bytes, Sample sample) {
  for (final card in parseCards(bytes, sample.bvid, sample.aid, sample.cid)) {
    if (card.sample.kind == sample.kind && card.sample.cardId == sample.cardId)
      return card;
  }
  throw ProbeFailure('${sample.bvid} 没有返回预期的${sample.label}卡片');
}

class ProbeApi {
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);
  final Map<String, String> _cookies;
  final String _mid;
  ProbeApi._(this._cookies, this._mid);

  static Future<ProbeApi> fromFile(String path) async {
    final decoded = jsonDecode(await File(path).readAsString());
    if (decoded is! Map || decoded.isEmpty) {
      throw const ProbeFailure('账号文件格式不正确');
    }
    final account = decoded.values.first;
    if (account is! Map || account['cookies'] is! Map) {
      throw const ProbeFailure('需要本项目导出的账号 JSON 文件');
    }
    final cookies = Map<String, String>.from(account['cookies'] as Map);
    for (final key in ['SESSDATA', 'bili_jct', 'DedeUserID']) {
      if (cookies[key]?.isNotEmpty != true) {
        throw const ProbeFailure('账号文件缺少必要的登录字段');
      }
    }
    return ProbeApi._(cookies, cookies['DedeUserID']!);
  }

  Future<Uint8List> _request(
    String path, {
    Map<String, String>? query,
    Map<String, String>? form,
  }) async {
    // Fixed official API host; never follow a redirect with account cookies.
    final uri = Uri.https('api.bilibili.com', path, query);
    final request = await _http
        .openUrl(form == null ? 'GET' : 'POST', uri)
        .timeout(const Duration(seconds: 15));
    request.followRedirects = false;
    request.headers
      ..set(HttpHeaders.userAgentHeader, 'Mozilla/5.0')
      ..set(HttpHeaders.refererHeader, 'https://www.bilibili.com/')
      ..set(
        HttpHeaders.cookieHeader,
        _cookies.entries.map((e) => '${e.key}=${e.value}').join('; '),
      );
    if (form != null) {
      request.headers
        ..set('Origin', 'https://www.bilibili.com')
        ..set(
          HttpHeaders.contentTypeHeader,
          'application/x-www-form-urlencoded',
        );
      request.write(Uri(queryParameters: form).query);
    }
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw ProbeFailure('接口 HTTP ${response.statusCode}');
    }
    final data = await response
        .fold<List<int>>([], (a, b) => a..addAll(b))
        .timeout(const Duration(seconds: 15));
    return Uint8List.fromList(data);
  }

  Map<String, dynamic> _json(Uint8List bytes) {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map) throw const ProbeFailure('接口未返回有效 JSON');
    final json = Map<String, dynamic>.from(value);
    if (json['code'] != 0) {
      throw ProbeFailure('接口返回 ${json['code']}：${json['message'] ?? '失败'}');
    }
    return json;
  }

  Future<String> validateLogin() async {
    final json = _json(await _request('/x/web-interface/nav'));
    final data = json['data'] as Map;
    if (data['isLogin'] != true || data['mid'].toString() != _mid) {
      throw const ProbeFailure('账号登录已失效或不匹配');
    }
    final tail = _mid.length > 4 ? _mid.substring(_mid.length - 4) : _mid;
    return '登录有效，UID 尾号 $tail';
  }

  Future<CommandCard> read(Sample sample) async =>
      parseCard(await _danmaku(sample.aid, sample.cid), sample);

  Future<Uint8List> _danmaku(int aid, int cid) => _request(
    '/x/v2/dm/web/view',
    query: {
      'type': '1',
      'pid': '$aid',
      'oid': '$cid',
      '_probe': '${DateTime.now().millisecondsSinceEpoch}',
    },
  );

  Future<List<CommandCard>> discover(VideoTarget target) async {
    final json = _json(
      await _request('/x/web-interface/view', query: {'bvid': target.bvid}),
    );
    final data = json['data'] as Map;
    final pages = data['pages'] as List;
    if (target.page > pages.length) throw const ProbeFailure('视频没有这个分 P');
    final aid = (data['aid'] as num).toInt();
    final cid = ((pages[target.page - 1] as Map)['cid'] as num).toInt();
    return parseCards(await _danmaku(aid, cid), target.bvid, aid, cid);
  }

  Future<VideoSource> video(Sample sample) async {
    final json = _json(
      await _request(
        '/x/player/playurl',
        query: {
          'bvid': sample.bvid,
          'cid': '${sample.cid}',
          'qn': '16',
          'fnval': '0',
          'fnver': '0',
          'fourk': '0',
          'platform': 'html5',
          'high_quality': '0',
        },
      ),
    );
    final data = json['data'] as Map;
    final segments = data['durl'] as List?;
    if (segments == null || segments.length != 1) {
      throw const ProbeFailure('这个最小测试需要单段 MP4 视频流');
    }
    final uri = Uri.parse((segments.first as Map)['url'] as String);
    if (!uri.host.endsWith('.bilivideo.com') &&
        !uri.host.endsWith('.bilivideo.cn')) {
      throw const ProbeFailure('视频流不是预期的 B站 CDN 地址');
    }
    return VideoSource(
      uri.replace(scheme: 'https').toString(),
      (data['timelength'] as num).toInt(),
    );
  }

  Future<Map<String, dynamic>> submit(
    CommandCard card,
    int chosen,
    int progressMs,
  ) async {
    final sample = card.sample;
    if (card.participation != 0) {
      throw const ProbeFailure('这个账号已参与，不重复提交；请刷新服务器状态');
    }
    if (!card.visibleAt(progressMs)) {
      throw const ProbeFailure('视频进度不在卡片显示区间，请跳回卡片开始位置');
    }
    if (sample.kind == CardKind.vote) {
      if (!card.options.any(
        (o) => o['idx'] == chosen && o['has_self_def'] != true,
      )) {
        throw const ProbeFailure('无效的投票选项');
      }
    } else if (chosen < 2 || chosen > 10 || chosen.isOdd) {
      throw const ProbeFailure('评分必须为一至五星');
    }
    final form = <String, String>{
      'aid': '${sample.aid}',
      'cid': '${sample.cid}',
      'progress': '$progressMs',
      'polaris_app_id': '100',
      'polaris_platform': '5',
      'spmid': '333.788.0.0',
      'from_spmid': '333.788.0.0',
      'csrf': _cookies['bili_jct']!,
      if (sample.kind == CardKind.vote) ...{
        'vote_id': '${sample.cardId}',
        'vote_type': '${card.extra['vote_type'] ?? 0}',
        'cmd_id_str': card.id,
        'option_id': '$chosen',
        'has_self_def': '0',
      } else ...{
        'grade_id': '${sample.cardId}',
        'grade_score': '$chosen',
      },
    };
    final endpoint = sample.kind == CardKind.vote ? 'vote' : 'grade';
    return _json(await _request('/x/v2/dm/command/$endpoint/post', form: form));
  }

  void close() {
    _http.close(force: true);
    _cookies.clear();
  }
}
