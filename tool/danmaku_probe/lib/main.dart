import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'client.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(
    ProbeApp(
      accountPath: args.isNotEmpty
          ? args.first
          : Platform.environment['PILIPILI_TEST_ACCOUNT_FILE'] ?? '',
    ),
  );
}

ThemeData probeTheme(Brightness brightness) => ThemeData(
  brightness: brightness,
  useMaterial3: true,
  fontFamily: 'Microsoft YaHei',
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xfffb7299),
    brightness: brightness,
  ),
);

class ProbeApp extends StatelessWidget {
  final String accountPath;
  const ProbeApp({super.key, required this.accountPath});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Pilipili 真实视频互动测试',
    theme: probeTheme(Brightness.dark),
    home: ProbePage(accountPath: accountPath),
  );
}

class ProbePage extends StatefulWidget {
  final String accountPath;
  const ProbePage({super.key, required this.accountPath});
  @override
  State<ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<ProbePage> {
  late final path = TextEditingController(text: widget.accountPath);
  final videoInput = TextEditingController(text: 'BV11d6rB4Evy');
  ProbeApi? api;
  List<CommandCard>? cards;
  List<VideoSource>? videos;
  bool loading = false;
  final activeRequests = <String>{};
  String status = '未加载账号';
  int generation = 0;
  @override
  void initState() {
    super.initState();
    if (widget.accountPath.isNotEmpty) unawaited(load());
  }

  Future<void> load() async {
    if (loading || activeRequests.isNotEmpty || path.text.trim().isEmpty)
      return;
    setState(() {
      loading = true;
      cards = null;
      videos = null;
      status = '读取登录态、卡片和真实视频流…';
    });
    api?.close();
    api = null;
    ProbeApi? next;
    try {
      final lines = videoInput.text
          .split(RegExp(r'[\r\n]+'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (lines.isEmpty || lines.length > 4)
        throw const ProbeFailure('请输入一至四个视频，每行一个');
      final targets = lines.map(VideoTarget.parse).toList();
      next = await ProbeApi.fromFile(path.text.trim());
      final auth = await next.validateLogin();
      final data = <CommandCard>[];
      final missing = <String>[];
      final seen = <String>{};
      for (final target in targets) {
        if (!seen.add('${target.bvid}:${target.page}')) continue;
        final found = await next.discover(target);
        data.addAll(found);
        if (found.isEmpty) missing.add('${target.bvid} P${target.page}');
      }
      final streamByVideo = <int, VideoSource>{};
      final streams = <VideoSource>[];
      for (final card in data) {
        streamByVideo[card.sample.cid] ??= await next.video(card.sample);
        streams.add(streamByVideo[card.sample.cid]!);
      }
      if (!mounted) {
        next.close();
        return;
      }
      setState(() {
        api = next;
        cards = data;
        videos = streams;
        status =
            '$auth，发现 ${data.length} 张卡片${missing.isEmpty ? '' : '；${missing.join('、')} 没有投票或评分卡片'}';
        generation++;
      });
    } catch (e) {
      next?.close();
      if (mounted) setState(() => status = safeError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    api?.close();
    path.dispose();
    videoInput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pilipili 真实视频投票／打星测试')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Flutter 3.49.0-0.2.pre，项目锁定的 media_kit 分支，真实 B站视频与接口'),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: path,
                  enabled: !loading && activeRequests.isEmpty,
                  decoration: const InputDecoration(
                    labelText: '本项目导出的账号 JSON 路径',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: loading || activeRequests.isNotEmpty ? null : load,
                icon: const Icon(Icons.refresh),
                label: const Text('加载真实视频'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('video-input'),
            controller: videoInput,
            enabled: !loading && activeRequests.isEmpty,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '视频 BV 号或完整链接（每行一个，支持 ?p= 分 P）',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: loading || activeRequests.isNotEmpty
                    ? null
                    : () {
                        videoInput.text = 'BV11d6rB4Evy';
                        unawaited(load());
                      },
                child: const Text('新视频样例'),
              ),
              TextButton(
                onPressed: loading || activeRequests.isNotEmpty
                    ? null
                    : () {
                        videoInput.text = samples.map((s) => s.bvid).join('\n');
                        unawaited(load());
                      },
                child: const Text('之前的样例'),
              ),
            ],
          ),
          Text(status),
          const SizedBox(height: 8),
          const Text(
            '点击播放，或跳到卡片出现位置；选择选项／星级会暂停视频，再点卡片内的“提交”。'
            '提交结果会重新读取，并显示投票数和平均评分。',
            style: TextStyle(fontSize: 13),
          ),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: LinearProgressIndicator(),
            ),
          if (cards != null && videos != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final panels = [
                    for (var i = 0; i < cards!.length; i++)
                      CardPanel(
                        key: ValueKey(
                          '$generation-${cards![i].sample.bvid}-${cards![i].sample.cid}-${cards![i].id}',
                        ),
                        initial: cards![i],
                        video: videos![i],
                        read: () => api!.read(cards![i].sample),
                        submit: (card, chosen, ms) =>
                            api!.submit(card, chosen, ms),
                        onBusy: (busy) {
                          if (mounted)
                            setState(() {
                              if (busy)
                                activeRequests.add(cards![i].id);
                              else
                                activeRequests.remove(cards![i].id);
                            });
                        },
                      ),
                  ];
                  final width = constraints.maxWidth < 900
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 16) / 2;
                  return Wrap(
                    spacing: 16,
                    children: [
                      for (final panel in panels)
                        SizedBox(width: width, child: panel),
                    ],
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
          const Text(
            '独立原生测试程序；尚未修改正式播放器。卡片时间来自实际解码播放进度，没有模拟时钟。',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    ),
  );
}

String safeError(Object error) {
  if (error is ProbeFailure) return error.message;
  if (error is FileSystemException) return '账号文件无法读取，请检查路径';
  if (error is FormatException) return '文件或接口数据格式不正确';
  if (error is TimeoutException) return '请求超时，请重新读取状态';
  if (error is SocketException || error is HttpException)
    return '网络连接失败，请重新读取状态';
  return '请求失败，请重新读取状态';
}

class CardPanel extends StatefulWidget {
  final CommandCard initial;
  final VideoSource? video;
  final Future<CommandCard> Function() read;
  final Future<Map<String, dynamic>> Function(CommandCard, int, int) submit;
  final ValueChanged<bool>? onBusy;
  const CardPanel({
    super.key,
    required this.initial,
    this.video,
    required this.read,
    required this.submit,
    this.onBusy,
  });
  @override
  State<CardPanel> createState() => _CardPanelState();
}

class _CardPanelState extends State<CardPanel> {
  late CommandCard card = widget.initial;
  late int currentMs = widget.video == null ? card.progressMs : 0;
  int selected = 0;
  bool busy = false, uncertain = false, playing = false, ready = false;
  bool acknowledged = false;
  bool dismissed = false;
  String message = '', videoMessage = '准备解码视频…';
  Player? player;
  VideoController? controller;
  final subscriptions = <StreamSubscription<dynamic>>[];
  bool get visible => !dismissed && card.visibleAt(currentMs);
  bool get canSubmit =>
      selected != 0 &&
      card.participation == 0 &&
      visible &&
      !busy &&
      !acknowledged &&
      !uncertain &&
      (widget.video == null || ready);
  @override
  void initState() {
    super.initState();
    if (widget.video != null) unawaited(openVideo());
  }

  Future<void> openVideo() async {
    Player? next;
    try {
      next = await Player.create(
        configuration: const PlayerConfiguration(
          logLevel: .error,
          options: {'volume': '25'},
        ),
      );
      final view = await VideoController.create(next);
      if (!mounted) {
        await next.dispose();
        return;
      }
      next.setMediaHeader(
        userAgent: 'Mozilla/5.0',
        referer: 'https://www.bilibili.com/',
      );
      player = next;
      subscriptions.add(
        next.stream.position.listen((pos) {
          if (mounted) setState(() => currentMs = pos.inMilliseconds);
        }),
      );
      subscriptions.add(
        next.stream.playing.listen((value) {
          if (mounted) setState(() => playing = value);
        }),
      );
      subscriptions.add(
        next.stream.error.listen((_) {
          if (mounted) setState(() => videoMessage = '视频解码或网络错误，请重新加载真实视频');
        }),
      );
      setState(() => controller = view);
      final start = (card.progressMs - 2000).clamp(0, card.progressMs);
      await next.open(
        Media(widget.video!.url, start: Duration(milliseconds: start)),
        play: false,
      );
      if (mounted)
        setState(() {
          ready = true;
          videoMessage = '点击播放真实视频';
        });
    } catch (_) {
      if (next != null && player == null) await next.dispose();
      if (mounted) setState(() => videoMessage = '播放器加载失败，请重新加载真实视频');
    }
  }

  @override
  void dispose() {
    for (final sub in subscriptions) {
      unawaited(sub.cancel());
    }
    if (player != null) unawaited(player!.dispose());
    super.dispose();
  }

  void activity(bool value) {
    setState(() => busy = value);
    widget.onBusy?.call(value);
  }

  Future<void> refresh() async {
    if (busy) return;
    activity(true);
    try {
      final next = await widget.read();
      if (mounted)
        setState(() {
          card = next;
          uncertain = false;
          message = '';
        });
    } catch (e) {
      if (mounted) setState(() => message = safeError(e));
    } finally {
      if (mounted) activity(false);
    }
  }

  void choose(int value) {
    if (player != null) unawaited(player!.pause());
    setState(() {
      selected = value;
      message = '';
    });
  }

  Future<void> send() async {
    if (!canSubmit) return;
    final clickMs = currentMs;
    activity(true);
    bool attempted = false;
    try {
      final fresh = await widget.read();
      if (!mounted) return;
      setState(() => card = fresh);
      if (fresh.participation != 0) {
        setState(() => message = '');
        return;
      }
      attempted = true;
      await widget.submit(fresh, selected, clickMs);
      if (!mounted) return;
      setState(() {
        acknowledged = true;
        uncertain = true;
        message = '正在确认提交结果…';
      });
      final after = await widget.read();
      if (!mounted) return;
      setState(() {
        card = after;
        uncertain = after.participation == 0;
        message = after.participation == selected
            ? '${card.sample.kind == CardKind.vote ? '投票' : '评分'}成功'
            : '提交结果待确认，请刷新后查看';
      });
    } catch (e) {
      if (mounted)
        setState(() {
          uncertain = attempted;
          message = attempted
              ? '${safeError(e)}。请先刷新服务器状态；不会自动重试。'
              : safeError(e);
        });
    } finally {
      if (mounted) activity(false);
    }
  }

  Future<void> seek(int ms) async {
    final value = ms.clamp(
      0,
      widget.video?.durationMs ?? card.progressMs + card.durationMs + 2000,
    );
    if (player == null) {
      setState(() => currentMs = value);
      return;
    }
    await player!.pause();
    await player!.seek(Duration(milliseconds: value));
  }

  double coordinate(String relative, String absolute, double scale) =>
      ((card.extra[relative] as num?)?.toDouble() ??
                  ((card.extra[absolute] as num?)?.toDouble() ?? scale / 2) /
                      scale *
                      100)
              .clamp(0, 100) /
          50 -
      1;
  Widget interactiveCard() {
    final vote = card.sample.kind == CardKind.vote;
    final value = card.participation != 0 ? card.participation : selected;
    final colors = Theme.of(context).colorScheme;
    final starColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xffffd166)
        : const Color(0xff956c00);
    return Container(
      key: const ValueKey('visible-card'),
      width: 310,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    card.question,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('dismiss-card'),
                  tooltip: '关闭卡片',
                  onPressed: () => setState(() => dismissed = true),
                  icon: const Icon(Icons.close, size: 18),
                  color: colors.onSurfaceVariant,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (vote) ...[
              for (final option in card.options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: OutlinedButton(
                    key: ValueKey('option-${option['idx']}'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: value == option['idx']
                          ? colors.onPrimaryContainer
                          : colors.onSurface,
                      disabledForegroundColor: value == option['idx']
                          ? colors.onPrimaryContainer
                          : colors.onSurface,
                      backgroundColor: value == option['idx']
                          ? colors.primaryContainer
                          : colors.surfaceContainerHighest,
                      side: BorderSide(
                        color: value == option['idx']
                            ? colors.primary
                            : colors.outlineVariant,
                      ),
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.centerLeft,
                    ),
                    onPressed:
                        busy ||
                            acknowledged ||
                            uncertain ||
                            card.participation != 0 ||
                            option['has_self_def'] == true
                        ? null
                        : () => choose(option['idx'] as int),
                    child: Text(
                      '${option['desc']}${option['has_self_def'] == true ? '（未接入）' : ''}${value == option['idx'] ? ' ✓' : ''}'
                      '${card.participation != 0 ? '  ${option['cnt'] ?? '—'} 票' : ''}',
                    ),
                  ),
                ),
            ] else
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        for (var star = 1; star <= 5; star++)
                          IconButton(
                            key: ValueKey('star-$star'),
                            tooltip: '$star 星',
                            iconSize: 32,
                            style: IconButton.styleFrom(
                              fixedSize: const Size(40, 40),
                              padding: EdgeInsets.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            visualDensity: VisualDensity.compact,
                            color: starColor,
                            disabledColor: starColor,
                            onPressed:
                                busy ||
                                    acknowledged ||
                                    uncertain ||
                                    card.participation != 0
                                ? null
                                : () => choose(star * 2),
                            icon: Icon(
                              value >= star * 2
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (value != 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      '$value 分',
                      key: const ValueKey('personal-score'),
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            const SizedBox(height: 4),
            Text(
              vote
                  ? '共 ${card.participantCount ?? '—'} 票'
                  : '平均 ${card.averageScore?.toStringAsFixed(1) ?? '—'}/10，${card.participantCount ?? '—'} 人评分',
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
            ),
            if (selected != 0 &&
                card.participation == 0 &&
                !acknowledged &&
                !uncertain) ...[
              const SizedBox(height: 8),
              FilledButton(
                key: const ValueKey('submit'),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
                onPressed: canSubmit ? send : null,
                child: Text(busy ? '提交中…' : '提交'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final duration =
        widget.video?.durationMs ?? card.progressMs + card.durationMs + 2000;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${card.sample.label} ${card.sample.bvid}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Colors.black),
                    if (controller != null)
                      SimpleVideo(controller: controller!),
                    if (visible)
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Align(
                          alignment: Alignment(
                            coordinate('posX_2', 'posX', 667),
                            coordinate('posY_2', 'posY', 375),
                          ),
                          child: interactiveCard(),
                        ),
                      )
                    else
                      const SizedBox(key: ValueKey('hidden-card')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.video == null ? '组件测试' : videoMessage,
              style: const TextStyle(fontSize: 12),
            ),
            Row(
              children: [
                IconButton(
                  tooltip: playing ? '暂停真实视频' : '播放真实视频',
                  onPressed: ready ? () => player!.playOrPause() : null,
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                ),
                Expanded(
                  child: Text(
                    '实际进度 ${(currentMs / 1000).toStringAsFixed(2)} / ${(duration / 1000).toStringAsFixed(2)} 秒',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            Slider(
              min: 0,
              max: duration.toDouble(),
              value: currentMs.clamp(0, duration).toDouble(),
              onChanged: busy ? null : (v) => unawaited(seek(v.round())),
            ),
            Wrap(
              spacing: 4,
              children: [
                TextButton(
                  onPressed: busy || card.progressMs == 0
                      ? null
                      : () => seek(card.progressMs - 2000),
                  child: const Text('卡片前'),
                ),
                TextButton(
                  onPressed: busy ? null : () => seek(card.progressMs),
                  child: const Text('出现时'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => seek(card.progressMs + card.durationMs),
                  child: const Text('结束时'),
                ),
              ],
            ),
            Text(
              '卡片显示区间 ${(card.progressMs / 1000).toStringAsFixed(2)}–${((card.progressMs + card.durationMs) / 1000).toStringAsFixed(2)} 秒',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Spacer(),
                IconButton(
                  tooltip: '重新读取服务器状态',
                  onPressed: busy ? null : refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              card.sample.kind == CardKind.vote
                  ? '共 ${card.participantCount ?? '—'} 票\n'
                        '${card.options.map((o) => '${o['desc']}：${o['cnt'] ?? '—'} 票').join('；')}'
                  : '${card.participantCount ?? '—'} 人评分，'
                        '平均 ${card.averageScore?.toStringAsFixed(1) ?? '—'}/10'
                        '${card.averageScore == null ? '' : '（${(card.averageScore! / 2).toStringAsFixed(2)}/5 星）'}',
              key: const ValueKey('server-statistics'),
              style: const TextStyle(fontSize: 12),
            ),
            if (selected != 0 &&
                card.participation == 0 &&
                !acknowledged &&
                !uncertain)
              TextButton(
                onPressed: busy ? null : () => setState(() => selected = 0),
                child: const Text('取消选择'),
              ),
            if (message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(message, style: const TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }
}
