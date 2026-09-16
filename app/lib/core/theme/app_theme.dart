import 'package:flutter/material.dart';

import 'app_colors.dart';

/// The two families shipped in assets/fonts and declared in pubspec.
///
/// They used to come from google_fonts, which can't work here: the app runs
/// on the node's own Wi-Fi with no internet, runtime fetching is therefore
/// switched off, and the package then threw on every single label — the UI
/// only looked right because Flutter quietly fell back to the platform
/// typeface. Bundling them makes the design real and the exceptions go away.
const appFontFamily = 'Manrope';
const appMonoFontFamily = 'IBM Plex Mono';

/// Monospace text style for DMX values / addresses, matching the wireframes'
/// IBM Plex Mono readouts.
TextStyle appMonoStyle({
  double fontSize = 13,
  FontWeight fontWeight = FontWeight.w500,
  Color? color,
}) {
  return TextStyle(
    fontFamily: appMonoFontFamily,
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
  );
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      surface: AppColors.background,
      primary: AppColors.accent,
      onPrimary: AppColors.accentOn,
      secondary: AppColors.accent2,
      onSecondary: AppColors.accent2On,
      error: AppColors.danger,
    ),
    fontFamily: appFontFamily,
    textTheme: ThemeData.dark().textTheme.apply(
      fontFamily: appFontFamily,
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      // Spelled out here, and on the rail's labels below, because a style
      // named in a component theme replaces the default one rather than
      // merging with it — without this the screen titles came out in the
      // platform's own typeface next to Manrope everywhere else.
      titleTextStyle: TextStyle(
        fontFamily: appFontFamily,
        color: AppColors.text,
        fontSize: 21,
        fontWeight: FontWeight.w800,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.panel,
      indicatorColor: AppColors.panel2,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: selected ? AppColors.accent : AppColors.textFaint,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(color: selected ? AppColors.accent : AppColors.textFaint);
      }),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: AppColors.panel,
      selectedIconTheme: const IconThemeData(color: AppColors.accent),
      unselectedIconTheme: const IconThemeData(color: AppColors.textFaint),
      selectedLabelTextStyle: const TextStyle(fontFamily: appFontFamily, color: AppColors.accent),
      unselectedLabelTextStyle: const TextStyle(fontFamily: appFontFamily, color: AppColors.textFaint),
      indicatorColor: AppColors.panel2,
    ),
    cardTheme: CardThemeData(
      color: AppColors.panel,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.panel2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.accent),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      hintStyle: const TextStyle(color: AppColors.textFaint),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: AppColors.accent,
      inactiveTrackColor: AppColors.panel2,
      thumbColor: AppColors.accent,
      overlayColor: AppColors.accent.withValues(alpha: 0.15),
      trackHeight: 6,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? AppColors.accent : AppColors.panel2,
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
  );
}
