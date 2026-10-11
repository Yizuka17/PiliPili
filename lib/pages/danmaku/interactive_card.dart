import 'dart:async';

import 'package:Pilipili/models_new/danmaku/interactive.dart';
import 'package:material_ui/material_ui.dart';

/// A card keeps its local dismissal and acknowledgement through seeks/fullscreen.
class InteractiveDanmakuCard extends StatefulWidget {
  final InteractiveDanmaku initial;
  final bool visible;
  final int Function() progress;
  final Future<void> Function() pause;
  final bool Function() canInteract;
  final Future<InteractiveDanmaku> Function() read;
  final Future<void> Function(InteractiveDanmaku, int, int) submit;
  final void Function(String) notify;
  const InteractiveDanmakuCard({
    super.key,
    required this.initial,
    required this.visible,
    required this.progress,
    required this.pause,
    required this.canInteract,
    required this.read,
    required this.submit,
    required this.notify,
  });
  @override
  State<InteractiveDanmakuCard> createState() => _InteractiveDanmakuCardState();
}

class _InteractiveDanmakuCardState extends State<InteractiveDanmakuCard> {
  late InteractiveDanmaku card = widget.initial;
  int selected = 0;
  bool busy = false, uncertain = false, acknowledged = false, dismissed = false;
  bool get canSubmit =>
      selected != 0 &&
      card.participation == 0 &&
      widget.visible &&
      !dismissed &&
      !busy &&
      !uncertain &&
      !acknowledged;

  void choose(int value) {
    if (busy ||
        uncertain ||
        acknowledged ||
        card.participation != 0 ||
        !widget.canInteract()) {
      return;
    }
    unawaited(widget.pause());
    setState(() => selected = value);
  }

  Future<void> refresh() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final fresh = await widget.read();
      if (mounted) {
        setState(() {
          card = fresh;
          uncertain = false;
        });
      }
    } catch (_) {
      if (mounted) widget.notify('无法读取结果，请稍后刷新');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> send() async {
    if (!canSubmit || !widget.canInteract()) return;
    final progress = widget.progress();
    setState(() => busy = true);
    var attempted = false;
    try {
      final fresh = await widget.read();
      if (!mounted) return;
      setState(() => card = fresh);
      if (fresh.participation != 0) return;
      attempted = true;
      await widget.submit(fresh, selected, progress);
      if (!mounted) return;
      setState(() {
        acknowledged = true;
        uncertain = true;
      });
      final after = await widget.read();
      if (!mounted) return;
      setState(() {
        card = after;
        uncertain = after.participation == 0;
      });
      if (uncertain) widget.notify('提交结果待确认，稍后刷新卡片');
    } catch (_) {
      if (mounted) {
        setState(() => uncertain = attempted);
        widget.notify(attempted ? '提交结果未确认，请刷新卡片；不会自动重试' : '无法读取卡片，请稍后再试');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget interactiveCard() {
    final vote = card.kind == InteractiveKind.vote;
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
                  tooltip: '刷新结果',
                  onPressed: busy ? null : refresh,
                  icon: const Icon(Icons.refresh, size: 18),
                  color: colors.onSurfaceVariant,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  visualDensity: VisualDensity.compact,
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
                      '${option['desc']}${value == option['idx'] ? ' ✓' : ''}'
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
  Widget build(BuildContext context) => !widget.visible || dismissed
      ? const SizedBox.shrink()
      : interactiveCard();
}
