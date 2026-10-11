import 'dart:async';

import 'package:Pilipili/utils/storage.dart';
import 'package:Pilipili/utils/storage_key.dart';
import 'package:Pilipili/utils/storage_pref.dart';
import 'package:material_ui/material_ui.dart';

class InteractiveCardOpacityControl extends StatefulWidget {
  const InteractiveCardOpacityControl({super.key});

  @override
  State<InteractiveCardOpacityControl> createState() =>
      _InteractiveCardOpacityControlState();
}

class _InteractiveCardOpacityControlState
    extends State<InteractiveCardOpacityControl> {
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

  void update(double value) => unawaited(
    GStorage.setting.put(SettingBoxKey.interactiveCardOpacity, value),
  );

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(child: Text('互动卡片不透明度 ${(opacity * 100).round()}%')),
          IconButton(
            tooltip: '恢复默认 90%',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () => update(Pref.defaultInteractiveCardOpacity),
          ),
        ],
      ),
      Slider(
        key: const ValueKey('interactive-card-opacity-slider'),
        value: opacity,
        min: 0,
        max: 1,
        divisions: 100,
        label: '${(opacity * 100).round()}%',
        onChanged: update,
      ),
    ],
  );
}
