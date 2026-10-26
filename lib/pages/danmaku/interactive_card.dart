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

  Widget compactCard(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final vote = card.kind == InteractiveKind.vote;
    final value = card.participation != 0 ? card.participation : selected;
    final editable =
        !busy && !acknowledged && !uncertain && card.participation == 0;
    final showSubmit =
        selected != 0 && card.participation == 0 && !acknowledged && !uncertain;
    final text = theme.textTheme.bodySmall!.copyWith(
      fontSize: 9,
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
      icon: Icon(icon, size: 12),
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      constraints: const BoxConstraints.tightFor(width: 18, height: 18),
      padding: EdgeInsets.zero,
    );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.1,
      child: Card.filled(
        key: const ValueKey('visible-card'),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: colors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Scrollbar(
                        controller: _contentController,
                        child: SingleChildScrollView(
                          key: const ValueKey('card-content'),
                          controller: _contentController,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 5),
                                child: Text(
                                  card.question,
                                  style: text.copyWith(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w600,
                                  ),
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
                                        borderRadius: BorderRadius.circular(6),
                                        clipBehavior: Clip.antiAlias,
                                        child: InkWell(
                                          key: ValueKey(
                                            'option-${option['idx']}',
                                          ),
                                          onTap:
                                              editable &&
                                                  option['has_self_def'] != true
                                              ? () =>
                                                    choose(option['idx'] as int)
                                              : null,
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              minHeight: 20,
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
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
                                                    const Padding(
                                                      padding: EdgeInsets.only(
                                                        left: 2,
                                                      ),
                                                      child: Icon(
                                                        Icons.check,
                                                        size: 10,
                                                      ),
                                                    ),
                                                  if (card.participation != 0)
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            left: 2,
                                                          ),
                                                      child: Text(
                                                        '${option['cnt'] ?? '—'}',
                                                        style: text.copyWith(
                                                          fontSize: 8,
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
                                                    (value != 0 ? 22 : 0)) /
                                                5)
                                            .clamp(0.0, 20.0);
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
                                                15.0,
                                              ),
                                            ),
                                            color: colors.primary,
                                            disabledColor: colors.primary,
                                            style: IconButton.styleFrom(
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                            constraints:
                                                BoxConstraints.tightFor(
                                                  width: starWidth,
                                                  height: 20,
                                                ),
                                            padding: EdgeInsets.zero,
                                          ),
                                        if (value != 0)
                                          Expanded(
                                            child: Text(
                                              '$value 分',
                                              key: const ValueKey(
                                                'personal-score',
                                              ),
                                              textAlign: TextAlign.end,
                                              style: text.copyWith(fontSize: 8),
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
                    const SizedBox(width: 6),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        action(
                          '收起卡片',
                          Icons.close,
                          () => setExpanded(false),
                          key: const ValueKey('dismiss-card'),
                        ),
                        action('刷新结果', Icons.refresh, busy ? null : refresh),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      vote
                          ? '共 ${card.participantCount ?? '—'} 票'
                          : '${card.averageScore?.toStringAsFixed(1) ?? '—'}/10 · ${card.participantCount ?? '—'} 人',
                      style: text.copyWith(
                        fontSize: 8,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (showSubmit) ...[
                    const SizedBox(width: 6),
                    FilledButton(
                      key: const ValueKey('submit'),
                      onPressed: canSubmit ? send : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(36, 20),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: text.copyWith(
                          fontSize: 9,
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
      if (constraints.maxWidth <= 180) {
        // A single scale applies to text, icons, spacing and hit testing alike.
        const designWidth = 130.0;
        final scale = constraints.maxWidth / designWidth;
        if (scale <= 0) return const SizedBox.shrink();
        return SizedBox(
          width: constraints.maxWidth,
          child: FittedBox(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: designWidth,
                maxWidth: designWidth,
                maxHeight: constraints.maxHeight / scale,
              ),
              child: compactCard(context),
            ),
          ),
        );
      }
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
                      tooltip: '收起卡片',
                      onPressed: () => setExpanded(false),
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

  Widget capsule(BuildContext context) {
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
