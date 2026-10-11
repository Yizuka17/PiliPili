import 'dart:async';

import 'package:Pilipili/common/widgets/button/icon_button.dart';
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text('互动卡片不透明度 ${(opacity * 100).toStringAsFixed(1)}%'),
          ),
          iconButton(
            tooltip: '默认值: 90.0%',
            icon: const Icon(Icons.refresh),
            onPressed: () => update(Pref.defaultInteractiveCardOpacity),
            iconColor: Theme.of(context).colorScheme.outline,
            size: 24,
            iconSize: 24,
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Slider(
          key: const ValueKey('interactive-card-opacity-slider'),
          value: opacity,
          min: 0,
          max: 1,
          divisions: 100,
          label: '${(opacity * 100).toStringAsFixed(1)}%',
          onChanged: update,
        ),
      ),
    ],
  );
}
