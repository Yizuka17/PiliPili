import 'package:Pilipili/models_new/danmaku/interactive.dart';
import 'package:material_ui/material_ui.dart';

/// A timed capsule retains its choice and acknowledgement through fullscreen.
class InteractiveDanmakuCard extends StatefulWidget {
  final InteractiveDanmaku initial;
  final bool visible;
  final int Function() progress;
  final Listenable? positionChanges;
  final ValueChanged<bool>? onExpandedChanged;
  final bool Function() canInteract;
  final Future<InteractiveDanmaku> Function() read;
  final Future<void> Function(InteractiveDanmaku, int, int) submit;
  final void Function(String) notify;
  const InteractiveDanmakuCard({
    super.key,
    required this.initial,
    required this.visible,
    required this.progress,
    this.positionChanges,
    this.onExpandedChanged,
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
  bool busy = false, uncertain = false, acknowledged = false, expanded = false;
  bool get canSubmit =>
      selected != 0 &&
      expanded &&
      card.participation == 0 &&
      widget.visible &&
      !busy &&
      !uncertain &&
      !acknowledged;

  @override
  void initState() {
    super.initState();
    widget.positionChanges?.addListener(positionChanged);
  }

  void positionChanged() {
    if (!mounted || !widget.visible) return;
    if (expanded && !card.visibleAt(widget.progress())) {
      setExpanded(false);
      return;
    }
    setState(() {});
  }

  void setExpanded(bool value) {
    if (expanded == value) return;
    setState(() {
      expanded = value;
    });
    widget.onExpandedChanged?.call(value);
  }

  @override
  void didUpdateWidget(InteractiveDanmakuCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positionChanges != widget.positionChanges) {
      oldWidget.positionChanges?.removeListener(positionChanged);
      widget.positionChanges?.addListener(positionChanged);
    }
    if (!widget.visible) expanded = false;
  }

  @override
  void dispose() {
    widget.positionChanges?.removeListener(positionChanged);
    _contentController.dispose();
    super.dispose();
  }

  void choose(int value) {
    if (!expanded ||
        busy ||
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
      if (!mounted ||
          !widget.visible ||
          !expanded ||
          !card.visibleAt(widget.progress()) ||
          !widget.canInteract()) {
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

  Widget detailCard(BuildContext context, {double designWidth = 130}) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // Small players use one scaled design. Larger players grow continuously
    // into the established desktop sizes, with a 310 logical-pixel upper bound.
    final large = designWidth > 180;
    final blend = ((designWidth - 180) / 130).clamp(0.0, 1.0);
    double size(double small, double desktop) =>
        large ? small * (180 / 130) * (1 - blend) + desktop * blend : small;
    final vote = card.kind == InteractiveKind.vote;
    final value = card.participation != 0 ? card.participation : selected;
    final editable =
        !busy && !acknowledged && !uncertain && card.participation == 0;
    final showSubmit =
        selected != 0 && card.participation == 0 && !acknowledged && !uncertain;
    final text = theme.textTheme.bodySmall!.copyWith(
      fontSize: size(9, 14),
      height: 1.15,
      letterSpacing: 0,
    );
    Widget action(
      String tooltip,
      IconData icon,
      VoidCallback? onPressed, {
      Key? key,
    }) => IconButton(
      key: key,
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: size(12, 18)),
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      constraints: BoxConstraints.tightFor(
        width: size(18, 32),
        height: size(18, 32),
      ),
      padding: EdgeInsets.zero,
    );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.1,
      child: Card.filled(
        key: const ValueKey('visible-card'),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: colors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(size(8, 16)),
        ),
        child: Padding(
          padding: EdgeInsets.all(size(8, 12)),
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
                      style: text.copyWith(
                        fontSize: size(9.5, 16),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(width: size(4, 8)),
                  action('刷新结果', Icons.refresh, busy ? null : refresh),
                  action(
                    '收起卡片',
                    Icons.close,
                    () => setExpanded(false),
                    key: const ValueKey('dismiss-card'),
                  ),
                ],
              ),
              SizedBox(height: size(3, 8)),
              Flexible(
                child: Scrollbar(
                  controller: _contentController,
                  child: SingleChildScrollView(
                    key: const ValueKey('card-content'),
                    controller: _contentController,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (vote)
                          for (final option in card.options)
                            Padding(
                              padding: EdgeInsets.only(bottom: size(4, 6)),
                              child: Semantics(
                                selected: value == option['idx'],
                                child: Material(
                                  color: value == option['idx']
                                      ? colors.secondaryContainer
                                      : colors.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(
                                    size(6, 12),
                                  ),
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
                                        minHeight: size(20, 44),
                                      ),
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: size(8, 12),
                                          vertical: size(4, 8),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '${option['desc']}',
                                                style: text,
                                              ),
                                            ),
                                            if (value == option['idx'])
                                              Padding(
                                                padding: EdgeInsets.only(
                                                  left: size(2, 6),
                                                ),
                                                child: Icon(
                                                  Icons.check,
                                                  size: size(10, 16),
                                                ),
                                              ),
                                            if (card.participation != 0)
                                              Padding(
                                                padding: EdgeInsets.only(
                                                  left: size(2, 6),
                                                ),
                                                child: Text(
                                                  '${option['cnt'] ?? '—'}',
                                                  key: ValueKey(
                                                    'option-count-${option['idx']}',
                                                  ),
                                                  style: text.copyWith(
                                                    fontSize: size(8, 11),
                                                  ),
                                                ),
                                              ),
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
                            builder: (context, constraints) {
                              final starWidth =
                                  ((constraints.maxWidth -
                                              (value != 0 ? size(22, 48) : 0)) /
                                          5)
                                      .clamp(0.0, size(20, 40));
                              return Row(
                                children: [
                                  for (var star = 1; star <= 5; star++)
                                    IconButton(
                                      key: ValueKey('star-$star'),
                                      tooltip: '$star 星',
                                      onPressed: editable
                                          ? () => choose(star * 2)
                                          : null,
                                      icon: Icon(
                                        value >= star * 2
                                            ? Icons.star_rounded
                                            : Icons.star_outline_rounded,
                                        size: (starWidth * .9).clamp(
                                          0.0,
                                          size(13, 30),
                                        ),
                                      ),
                                      color: colors.primary,
                                      disabledColor: colors.primary,
                                      style: IconButton.styleFrom(
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      constraints: BoxConstraints.tightFor(
                                        width: starWidth,
                                        height: size(20, 44),
                                      ),
                                      padding: EdgeInsets.zero,
                                    ),
                                  if (value != 0)
                                    Expanded(
                                      child: Text(
                                        '$value 分',
                                        key: const ValueKey('personal-score'),
                                        textAlign: TextAlign.end,
                                        style: text.copyWith(
                                          fontSize: size(8, 14),
                                        ),
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
              SizedBox(height: size(5, 8)),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      vote
                          ? '共 ${card.participantCount ?? '—'} 票'
                          : '${card.averageScore?.toStringAsFixed(1) ?? '—'}/10 · ${card.participantCount ?? '—'} 人',
                      style: text.copyWith(
                        fontSize: size(8, 12),
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (showSubmit) ...[
                    SizedBox(width: size(6, 8)),
                    FilledButton(
                      key: const ValueKey('submit'),
                      onPressed: canSubmit ? send : null,
                      style: FilledButton.styleFrom(
                        minimumSize: Size(size(36, 64), size(20, 40)),
                        padding: EdgeInsets.symmetric(horizontal: size(8, 16)),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: text.copyWith(
                          fontSize: size(9, 14),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: Text(busy ? '提交中' : '提交'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget interactiveCard() => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth.clamp(0.0, 310.0);
      if (width <= 0) return const SizedBox.shrink();
      if (width <= 180) {
        const designWidth = 130.0;
        final scale = width / designWidth;
        return SizedBox(
          width: width,
          child: FittedBox(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: designWidth,
                maxWidth: designWidth,
                maxHeight: constraints.maxHeight / scale,
              ),
              child: detailCard(context),
            ),
          ),
        );
      }
      return SizedBox(
        width: width,
        child: detailCard(context, designWidth: width),
      );
    },
  );

  Widget capsule(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = (constraints.maxWidth / 130).clamp(.6, 1.4);
      return SizedBox(
        height: 22 * scale,
        child: FittedBox(
          child: SizedBox(height: 22, child: capsuleContent(context)),
        ),
      );
    },
  );

  Widget capsuleContent(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = card.kind == InteractiveKind.vote ? '投票' : '打分';
    final remaining = card.progressMs + card.durationMs - widget.progress();
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.1,
      child: Semantics(
        label: '剩余 ${(remaining / 1000).ceil()} 秒',
        child: Tooltip(
          message: '展开$label',
          child: Material(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const ValueKey('interactive-capsule'),
              onTap: () => setExpanded(true),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        key: const ValueKey('capsule-countdown'),
                        value: (remaining / card.durationMs).clamp(0.0, 1.0),
                        strokeWidth: 1.5,
                        color: colors.primary,
                        backgroundColor: colors.outlineVariant,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 9,
                        height: 1.1,
                        color: colors.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      !widget.visible || !card.visibleAt(widget.progress())
      ? const SizedBox.shrink()
      : expanded
      ? interactiveCard()
      : capsule(context);
}
