import 'package:material_ui/material_ui.dart';

/// Hide hover ink without disabling hit testing, clicks, focus, or tooltips.
abstract final class HoverHighlightTheme {
  static WidgetStateProperty<Color?> overlay(
    WidgetStateProperty<Color?>? original,
  ) => WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.hovered) &&
        !states.contains(WidgetState.pressed) &&
        !states.contains(WidgetState.dragged) &&
        !states.contains(WidgetState.focused)) {
      return Colors.transparent;
    }
    return original?.resolve(states);
  });

  static ButtonStyle _button(ButtonStyle? style, {double? restingElevation}) =>
      (style ?? const ButtonStyle()).copyWith(
        overlayColor: overlay(style?.overlayColor),
        elevation: restingElevation == null
            ? style?.elevation
            : WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.hovered) &&
                    !states.contains(WidgetState.pressed) &&
                    !states.contains(WidgetState.focused)) {
                  return style?.elevation?.resolve(
                        {...states}..remove(WidgetState.hovered),
                      ) ??
                      (states.contains(WidgetState.disabled)
                          ? 0
                          : restingElevation);
                }
                return style?.elevation?.resolve(states);
              }),
      );

  static ThemeData apply(ThemeData theme) => theme.copyWith(
    hoverColor: Colors.transparent,
    textButtonTheme: TextButtonThemeData(
      style: _button(theme.textButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: _button(theme.outlinedButtonTheme.style),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: _button(theme.filledButtonTheme.style),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: _button(theme.elevatedButtonTheme.style, restingElevation: 1),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: _button(theme.iconButtonTheme.style),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: _button(theme.segmentedButtonTheme.style),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: _button(theme.menuButtonTheme.style),
    ),
    navigationBarTheme: theme.navigationBarTheme.copyWith(
      overlayColor: overlay(theme.navigationBarTheme.overlayColor),
    ),
    tabBarTheme: theme.tabBarTheme.copyWith(
      overlayColor: overlay(theme.tabBarTheme.overlayColor),
    ),
    checkboxTheme: theme.checkboxTheme.copyWith(
      overlayColor: overlay(theme.checkboxTheme.overlayColor),
    ),
    radioTheme: theme.radioTheme.copyWith(
      overlayColor: overlay(theme.radioTheme.overlayColor),
    ),
    switchTheme: theme.switchTheme.copyWith(
      overlayColor: overlay(theme.switchTheme.overlayColor),
    ),
    sliderTheme: theme.sliderTheme.copyWith(
      overlayColor: WidgetStateColor.resolveWith(
        (states) {
          if (states.contains(WidgetState.hovered) &&
              !states.contains(WidgetState.pressed) &&
              !states.contains(WidgetState.dragged) &&
              !states.contains(WidgetState.focused)) {
            return Colors.transparent;
          }
          return WidgetStateProperty.resolveAs(
                theme.sliderTheme.overlayColor,
                states,
              ) ??
              theme.colorScheme.primary.withValues(alpha: 0.12);
        },
      ),
    ),
    toggleButtonsTheme: theme.toggleButtonsTheme.copyWith(
      hoverColor: Colors.transparent,
    ),
    inputDecorationTheme: theme.inputDecorationTheme.copyWith(
      hoverColor: Colors.transparent,
    ),
    floatingActionButtonTheme: theme.floatingActionButtonTheme.copyWith(
      hoverColor: Colors.transparent,
      hoverElevation: theme.floatingActionButtonTheme.elevation ?? 6.0,
    ),
  );
}
