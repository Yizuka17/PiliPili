import 'dart:io';

import 'package:Pilipili/common/widgets/gesture/touch_diagnostic_ink_well.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Widget host({VoidCallback? onTap, VoidCallback? onLongPress}) => MaterialApp(
    home: Material(
      child: Center(
        child: TouchDiagnosticInkWell(
          scope: 'testCard',
          onTap: onTap,
          onLongPress: onLongPress,
          child: const SizedBox(width: 120, height: 80),
        ),
      ),
    ),
  );

  // Exercise the real InkWell and the externally observed states. File/channel
  // serialization is covered separately, without mixing real IO and fake time.
  WidgetStatesController controller(WidgetTester tester) => tester
      .widget<InkWell>(
        find.descendant(
          of: find.byType(TouchDiagnosticInkWell),
          matching: find.byType(InkWell),
        ),
      )
      .statesController!;

  testWidgets(
    'distinguishes retained hover from released touch press and focus',
    (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(onTap: () => taps++));
      final states = controller(tester);
      final position = tester.getCenter(find.byType(TouchDiagnosticInkWell));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: position);
      await tester.pump();
      expect(states.value, contains(WidgetState.hovered));
      final touch = await tester.startGesture(position);
      await tester.pump(const Duration(milliseconds: 120));
      expect(states.value, contains(WidgetState.pressed));
      await touch.up();
      await tester.pump();
      expect(taps, 1);
      expect(states.value, isNot(contains(WidgetState.pressed)));
      expect(states.value, contains(WidgetState.hovered));
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(states.value, isNot(contains(WidgetState.hovered)));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(states.value, contains(WidgetState.focused));
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
    skip: !Platform.isWindows,
  );

  testWidgets('cancel clears press and long press still reaches its callback', (
    tester,
  ) async {
    var taps = 0;
    var longPresses = 0;
    await tester.pumpWidget(
      host(onTap: () => taps++, onLongPress: () => longPresses++),
    );
    final states = controller(tester);
    final position = tester.getCenter(find.byType(TouchDiagnosticInkWell));
    final cancelled = await tester.startGesture(position);
    await tester.pump(const Duration(milliseconds: 120));
    expect(states.value, contains(WidgetState.pressed));
    await cancelled.cancel();
    await tester.pump();
    expect(states.value, isNot(contains(WidgetState.pressed)));
    final held = await tester.startGesture(position);
    await tester.pump(const Duration(milliseconds: 600));
    await held.up();
    await tester.pump();
    expect(taps, 0);
    expect(longPresses, 1);
    expect(states.value, isNot(contains(WidgetState.pressed)));
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);
}
