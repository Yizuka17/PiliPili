import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// The complete painted video canvas, including cropped regions for BoxFit.cover.
Rect interactiveVideoFrame(
  Size viewport,
  Size video,
  BoxFit fit,
  Alignment alignment, {
  Matrix4? transform,
}) {
  if (video.isEmpty || viewport.isEmpty) return Offset.zero & viewport;
  final fitted = applyBoxFit(fit, video, viewport);
  final destination = alignment.inscribe(
    fitted.destination,
    Offset.zero & viewport,
  );
  final source = alignment.inscribe(fitted.source, Offset.zero & video);
  final sx = destination.width / source.width,
      sy = destination.height / source.height;
  final frame = Rect.fromLTWH(
    destination.left - source.left * sx,
    destination.top - source.top * sy,
    video.width * sx,
    video.height * sy,
  );
  return transform == null
      ? frame
      : MatrixUtils.transformRect(transform, frame);
}

class InteractiveCardLayout extends SingleChildLayoutDelegate {
  final Offset position;
  final Rect videoFrame;
  const InteractiveCardLayout(this.position, this.videoFrame);

  Rect bounds(Size size) => videoFrame.intersect(Offset.zero & size);
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final visible = bounds(constraints.biggest);
    return BoxConstraints(
      maxWidth: math.min(310, math.max(0, visible.width - 16)),
      maxHeight: math.max(0, visible.height - 16),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final visible = bounds(size);
    if (visible.width <= 16 || visible.height <= 16) return Offset.zero;
    final center = Offset(
      videoFrame.left + videoFrame.width * position.dx,
      videoFrame.top + videoFrame.height * position.dy,
    );
    return Offset(
      (center.dx - childSize.width / 2).clamp(
        visible.left + 8,
        visible.right - childSize.width - 8,
      ),
      (center.dy - childSize.height / 2).clamp(
        visible.top + 8,
        visible.bottom - childSize.height - 8,
      ),
    );
  }

  @override
  bool shouldRelayout(InteractiveCardLayout oldDelegate) =>
      oldDelegate.position != position || oldDelegate.videoFrame != videoFrame;
}
