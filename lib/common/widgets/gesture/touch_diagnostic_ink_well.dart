import 'package:Pilipili/services/touch_diagnostics.dart';
import 'package:material_ui/material_ui.dart';

/// Observe actual InkWell states without changing gesture or focus behavior.
/// IDs identify instances, not comment or video content.
class TouchDiagnosticInkWell extends StatefulWidget {
  const TouchDiagnosticInkWell({
    super.key,
    required this.scope,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.borderRadius,
  });

  final String scope;
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;
  final BorderRadius? borderRadius;

  @override
  State<TouchDiagnosticInkWell> createState() => _TouchDiagnosticInkWellState();
}

class _TouchDiagnosticInkWellState extends State<TouchDiagnosticInkWell> {
  static int _nextId = 0;
  late final int _id = ++_nextId;
  WidgetStatesController? _states;

  @override
  void initState() {
    super.initState();
    if (TouchDiagnostics.enabled) {
      _states = WidgetStatesController()..addListener(_onStateChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _record('mounted');
      });
    }
  }

  void _onStateChanged() => _record('changed');

  void _record(String lifecycle) {
    final states = _states?.value ?? const <WidgetState>{};
    // During unmount the element may already be inactive; its last states are
    // still useful, but querying the render tree would assert in Debug mode.
    final box = lifecycle == 'disposed' ? null : context.findRenderObject();
    final position = box is RenderBox && box.attached && box.hasSize
        ? box.localToGlobal(Offset.zero)
        : null;
    TouchDiagnostics.widgetState({
      'scope': widget.scope,
      'instance': _id,
      'lifecycle': lifecycle,
      'hovered': states.contains(WidgetState.hovered),
      'pressed': states.contains(WidgetState.pressed),
      'focused': states.contains(WidgetState.focused),
      'disabled': states.contains(WidgetState.disabled),
      if (position != null && box is RenderBox) ...{
        'topLeft': [position.dx, position.dy],
        'size': [box.size.width, box.size.height],
      },
    });
  }

  @override
  void dispose() {
    if (_states != null) {
      _record('disposed');
      _states!
        ..removeListener(_onStateChanged)
        ..dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InkWell(
    statesController: _states,
    onTap: widget.onTap,
    onLongPress: widget.onLongPress,
    onSecondaryTap: widget.onSecondaryTap,
    borderRadius: widget.borderRadius,
    child: widget.child,
  );
}
