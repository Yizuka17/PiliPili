import 'dart:math' show pi;

import 'package:material_ui/material_ui.dart';

/// Remaining playback time follows the pill's outline instead of a tiny icon.
class CapsuleCountdownBorder extends StatelessWidget {
  const CapsuleCountdownBorder({
    super.key,
    required this.value,
    required this.color,
    required this.trackColor,
    required this.child,
  });

  final double value;
  final Color color;
  final Color trackColor;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _CountdownPainter(value, color, trackColor),
    child: child,
  );
}

class _CountdownPainter extends CustomPainter {
  const _CountdownPainter(this.value, this.color, this.trackColor);

  final double value;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 1.5;
    if (size.width <= stroke || size.height <= stroke) return;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final radius = rect.height / 2;
    final path = Path()
      ..moveTo(rect.center.dx, rect.top)
      ..lineTo(rect.right - radius, rect.top)
      ..arcTo(
        Rect.fromCircle(
          center: Offset(rect.right - radius, rect.center.dy),
          radius: radius,
        ),
        -pi / 2,
        pi,
        false,
      )
      ..lineTo(rect.left + radius, rect.bottom)
      ..arcTo(
        Rect.fromCircle(
          center: Offset(rect.left + radius, rect.center.dy),
          radius: radius,
        ),
        pi / 2,
        pi,
        false,
      )
      ..close();
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawPath(path, paint);
    final remaining = value.clamp(0.0, 1.0);
    if (remaining <= 0) return;
    paint.color = color;
    if (remaining == 1) {
      canvas.drawPath(path, paint);
    } else {
      final metric = path.computeMetrics().first;
      canvas.drawPath(metric.extractPath(0, metric.length * remaining), paint);
    }
  }

  @override
  bool shouldRepaint(_CountdownPainter oldDelegate) =>
      value != oldDelegate.value ||
      color != oldDelegate.color ||
      trackColor != oldDelegate.trackColor;
}
