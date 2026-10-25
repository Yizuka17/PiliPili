import 'package:Pilipili/models_new/danmaku/interactive.dart';
import 'package:material_ui/material_ui.dart';

/// A card keeps its local dismissal and acknowledgement through seeks/fullscreen.
class InteractiveDanmakuCard extends StatefulWidget {
  final InteractiveDanmaku initial;
  final bool visible;
  final int Function() progress;
  final bool Function() canInteract;
  final Future<InteractiveDanmaku> Function() read;
  final Future<void> Function(InteractiveDanmaku, int, int) submit;
  final void Function(String) notify;
  const InteractiveDanmakuCard({
    super.key,
    required this.initial,
    required this.visible,
    required this.progress,
    required this.canInteract,
    required this.read,
    required this.submit,
    required this.notify,
  });
  @override
  State<InteractiveDanmakuCard> createState() => _InteractiveDanmakuCardState();
}

class _InteractiveDanmakuCardState extends State<InteractiveDanmakuCard> {
  final ScrollController _contentController = ScrollController();
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

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  void choose(int value) {
    if (busy ||
        uncertain ||
        acknowledged ||
        card.participation != 0 ||
        !widget.canInteract()) {
      return;
    }
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
      if (!mounted || !widget.visible || dismissed || !widget.canInteract()) {
        return;
      }
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

  Widget interactiveCard() => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      final compact = constraints.maxHeight < 260;
      final vote = card.kind == InteractiveKind.vote;
      final value = card.participation != 0 ? card.participation : selected;
      final editable =
          !busy && !acknowledged && !uncertain && card.participation == 0;
      final showSubmit =
          selected != 0 &&
          card.participation == 0 &&
          !acknowledged &&
          !uncertain;
      final summary = vote
          ? '共 ${card.participantCount ?? '—'} 票'
          : '平均 ${card.averageScore?.toStringAsFixed(1) ?? '—'}/10 · ${card.participantCount ?? '—'} 人';
      return SizedBox(
        width: 310,
        child: Card.filled(
          key: const ValueKey('visible-card'),
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          color: colors.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: EdgeInsets.all(compact ? 8 : 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      vote ? Icons.poll_outlined : Icons.star_outline_rounded,
                      size: 18,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        vote ? '投票' : '评分',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '刷新结果',
                      onPressed: busy ? null : refresh,
                      icon: const Icon(Icons.refresh, size: 18),
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      key: const ValueKey('dismiss-card'),
                      tooltip: '关闭卡片',
                      onPressed: () => setState(() => dismissed = true),
                      icon: const Icon(Icons.close, size: 18),
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                Flexible(
                  child: Scrollbar(
                    controller: _contentController,
                    thumbVisibility: compact,
                    child: SingleChildScrollView(
                      key: const ValueKey('card-content'),
                      controller: _contentController,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(
                              top: compact ? 2 : 8,
                              bottom: 8,
                            ),
                            child: Text(
                              card.question,
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          if (vote)
                            for (final option in card.options)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Semantics(
                                  selected: value == option['idx'],
                                  child: Material(
                                    color: value == option['idx']
                                        ? colors.secondaryContainer
                                        : colors.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(12),
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      key: ValueKey('option-${option['idx']}'),
                                      onTap:
                                          editable &&
                                              option['has_self_def'] != true
                                          ? () => choose(option['idx'] as int)
                                          : null,
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          minHeight: compact ? 36 : 44,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                value == option['idx']
                                                    ? Icons.radio_button_checked
                                                    : Icons.radio_button_off,
                                                size: 18,
                                                color: value == option['idx']
                                                    ? colors.primary
                                                    : colors.onSurfaceVariant,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  '${option['desc']}',
                                                  style: theme
                                                      .textTheme
                                                      .bodyMedium,
                                                ),
                                              ),
                                              if (card.participation != 0) ...[
                                                const SizedBox(width: 8),
                                                Text(
                                                  '${option['cnt'] ?? '—'} 票',
                                                  style: theme
                                                      .textTheme
                                                      .labelMedium,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              )
                          else
                            LayoutBuilder(
                              builder: (context, starConstraints) {
                                final starWidth =
                                    ((starConstraints.maxWidth -
                                                (value != 0 ? 48 : 0)) /
                                            5)
                                        .clamp(24.0, 40.0);
                                return Row(
                                  children: [
                                    for (var star = 1; star <= 5; star++)
                                      IconButton(
                                        key: ValueKey('star-$star'),
                                        tooltip: '$star 星',
                                        iconSize: compact ? 26 : 30,
                                        constraints: BoxConstraints.tightFor(
                                          width: starWidth,
                                          height: compact ? 36 : 44,
                                        ),
                                        padding: EdgeInsets.zero,
                                        visualDensity: VisualDensity.compact,
                                        color: colors.primary,
                                        disabledColor: colors.primary,
                                        onPressed: editable
                                            ? () => choose(star * 2)
                                            : null,
                                        icon: Icon(
                                          value >= star * 2
                                              ? Icons.star_rounded
                                              : Icons.star_outline_rounded,
                                        ),
                                      ),
                                    if (value != 0)
                                      Expanded(
                                        child: Text(
                                          '$value 分',
                                          key: const ValueKey('personal-score'),
                                          textAlign: TextAlign.end,
                                          style: theme.textTheme.labelLarge,
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(top: compact ? 4 : 8),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: compact ? 32 : 40),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            summary,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (showSubmit) ...[
                          const SizedBox(width: 8),
                          FilledButton(
                            key: const ValueKey('submit'),
                            style: FilledButton.styleFrom(
                              minimumSize: Size(64, compact ? 32 : 40),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: canSubmit ? send : null,
                            child: Text(busy ? '提交中…' : '提交'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) => !widget.visible || dismissed
      ? const SizedBox.shrink()
      : interactiveCard();
}
