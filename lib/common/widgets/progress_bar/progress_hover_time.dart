import 'dart:math' as math;

import 'package:Pilipili/utils/duration_utils.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

/// A desktop time hint; pointer input continues to the seek bar underneath.
class ProgressHoverTime extends StatefulWidget {
  const ProgressHoverTime({
    super.key,
    required this.total,
    required this.enabled,
    required this.child,
    this.barHeight = 3.5,
  });

  final int total;
  final bool enabled;
  final double barHeight;
  final Widget child;

  @override
  State<ProgressHoverTime> createState() => _ProgressHoverTimeState();
}

class _ProgressHoverTimeState extends State<ProgressHoverTime> {
  double? pointerX;

  void hide() {
    if (pointerX != null) setState(() => pointerX = null);
  }

  void hover(PointerEvent event) {
    if (widget.enabled &&
        widget.total > 0 &&
        event.kind == PointerDeviceKind.mouse &&
        event.buttons == 0) {
      setState(() => pointerX = event.localPosition.dx);
    } else {
      hide();
    }
  }

  @override
  void didUpdateWidget(ProgressHoverTime oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled || widget.total <= 0) pointerX = null;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final x = pointerX;
      final usableWidth = width - widget.barHeight;
      final show =
          widget.enabled &&
          widget.total > 0 &&
          x != null &&
          width.isFinite &&
          usableWidth > 0;
      final hintWidth = math.min(88.0, width);
      // Match RenderProgressBar's rounded-cap seek geometry.
      final fraction = show
          ? ((x - widget.barHeight / 2) / usableWidth).clamp(0.0, 1.0)
          : 0.0;
      return MouseRegion(
        onEnter: hover,
        onHover: hover,
        onExit: (_) => hide(),
        child: Listener(
          onPointerDown: (_) => hide(),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              widget.child,
              if (show)
                Positioned(
                  bottom: 24,
                  left: (x - hintWidth / 2).clamp(0.0, width - hintWidth),
                  width: hintWidth,
                  child: IgnorePointer(
                    child: Center(
                      child: DecoratedBox(
                        key: const ValueKey('progress-hover-time'),
                        decoration: BoxDecoration(
                          color: const Color(0xE6222222),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              DurationUtils.formatDuration(
                                (fraction * widget.total).round(),
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
