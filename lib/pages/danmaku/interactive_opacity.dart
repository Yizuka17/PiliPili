import 'dart:async';

import 'package:Pilipili/utils/storage.dart';
import 'package:Pilipili/utils/storage_key.dart';
import 'package:Pilipili/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart';

/// Watches the shared preference without replacing its child's card state.
class InteractiveCardOpacity extends StatefulWidget {
  final Widget child;
  const InteractiveCardOpacity({super.key, required this.child});

  @override
  State<InteractiveCardOpacity> createState() => _InteractiveCardOpacityState();
}

class _InteractiveCardOpacityState extends State<InteractiveCardOpacity> {
  late double opacity = Pref.interactiveCardOpacity;
  late final StreamSubscription<dynamic> changes;

  @override
  void initState() {
    super.initState();
    changes = GStorage.setting
        .watch(key: SettingBoxKey.interactiveCardOpacity)
        .listen((_) {
          if (mounted) setState(() => opacity = Pref.interactiveCardOpacity);
        });
  }

  @override
  void dispose() {
    unawaited(changes.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: opacity == 0,
    child: ExcludeFocus(
      excluding: opacity == 0,
      child: ExcludeSemantics(
        excluding: opacity == 0,
        child: Opacity(opacity: opacity, child: widget.child),
      ),
    ),
  );
}
