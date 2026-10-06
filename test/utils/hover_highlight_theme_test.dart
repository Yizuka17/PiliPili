import 'package:Pilipili/utils/hover_highlight_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test(
    'hides component hover ink while preserving focus, press and selection',
    () {
      final original = ThemeData(useMaterial3: true);
      final theme = HoverHighlightTheme.apply(original);
      expect(theme.hoverColor, Colors.transparent);
      for (final overlay in [
        theme.iconButtonTheme.style!.overlayColor!,
        theme.textButtonTheme.style!.overlayColor!,
        theme.filledButtonTheme.style!.overlayColor!,
        theme.tabBarTheme.overlayColor!,
        theme.navigationBarTheme.overlayColor!,
        theme.switchTheme.overlayColor!,
        theme.checkboxTheme.overlayColor!,
        theme.menuButtonTheme.style!.overlayColor!,
      ]) {
        expect(overlay.resolve({WidgetState.hovered}), Colors.transparent);
        expect(
          overlay.resolve({WidgetState.hovered, WidgetState.selected}),
          Colors.transparent,
        );
        expect(overlay.resolve({WidgetState.pressed}), isNull);
        expect(overlay.resolve({WidgetState.focused}), isNull);
      }
      expect(theme.focusColor, original.focusColor);
      expect(theme.highlightColor, original.highlightColor);
      expect(theme.splashColor, original.splashColor);
      expect(theme.floatingActionButtonTheme.hoverColor, Colors.transparent);
    },
  );
  testWidgets(
    'navigation rail and floating button respect disabled hover ink',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: HoverHighlightTheme.apply(ThemeData(useMaterial3: true)),
          home: Scaffold(
            body: NavigationRail(
              selectedIndex: 0,
              onDestinationSelected: (_) {},
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.home),
                  label: Text('home'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.person),
                  label: Text('profile'),
                ),
              ],
            ),
            floatingActionButton: FloatingActionButton(
              onPressed: () {},
              child: const Icon(Icons.add),
            ),
          ),
        ),
      );
      final inks = tester.widgetList<InkResponse>(
        find.descendant(
          of: find.byType(NavigationRail),
          matching: find.bySubtype<InkResponse>(),
        ),
      );
      expect(inks.length, greaterThanOrEqualTo(2));
      for (final ink in inks) {
        expect(ink.hoverColor, Colors.transparent);
      }
      final button = tester.widget<RawMaterialButton>(
        find.descendant(
          of: find.byType(FloatingActionButton),
          matching: find.byType(RawMaterialButton),
        ),
      );
      expect(button.hoverColor, Colors.transparent);
      expect(button.hoverElevation, button.elevation);
    },
  );
  testWidgets(
    'button remains clickable with transparent hover and visible press feedback',
    (tester) async {
      var clicks = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: HoverHighlightTheme.apply(ThemeData(useMaterial3: true)),
          home: Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => clicks++,
                child: const Text('button'),
              ),
            ),
          ),
        ),
      );
      final position = tester.getCenter(find.byType(TextButton));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: position);
      await tester.pumpAndSettle();
      final ink = tester.widget<InkWell>(
        find.descendant(
          of: find.byType(TextButton),
          matching: find.byType(InkWell),
        ),
      );
      expect(
        ink.overlayColor!.resolve({WidgetState.hovered}),
        Colors.transparent,
      );
      expect(
        ink.overlayColor!.resolve({WidgetState.pressed}),
        isNot(Colors.transparent),
      );
      await mouse.down(position);
      await mouse.up();
      await tester.pumpAndSettle();
      expect(clicks, 1);
    },
  );
}
