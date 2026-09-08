import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Monospace text style for DMX values / addresses, matching the wireframes'
/// IBM Plex Mono readouts.
TextStyle appMonoStyle({
  double fontSize = 13,
  FontWeight fontWeight = FontWeight.w500,
  Color? color,
}) {
  return GoogleFonts.ibmPlexMono(
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
    textTheme: GoogleFonts.manropeTextTheme(ThemeData.dark().textTheme).apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: TextStyle(
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
      selectedLabelTextStyle: const TextStyle(color: AppColors.accent),
      unselectedLabelTextStyle: const TextStyle(color: AppColors.textFaint),
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
