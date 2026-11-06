import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'palette.dart';
import 'typography.dart';

/// Builds the LilRoutine cozy pixel ThemeData.
ThemeData buildLilRoutineTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Palette.sky,
      primary: Palette.skyDeep,
      secondary: Palette.peachDeep,
      surface: Palette.cream,
      error: Palette.blushDeep,
    ),
    scaffoldBackgroundColor: Palette.cream,
  );

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      displayLarge: AppTypography.pixelDisplay(34),
      displayMedium: AppTypography.pixelDisplay(28),
      headlineMedium: AppTypography.pixelDisplay(22),
      titleLarge: AppTypography.pixelDisplay(18),
      titleMedium: AppTypography.pixelDisplay(14),
      bodyLarge: AppTypography.cozy(16),
      bodyMedium: AppTypography.cozy(14),
      bodySmall: AppTypography.cozy(12, color: Palette.cocoaSoft),
      labelLarge: AppTypography.cozy(14, weight: FontWeight.w600),
    ),
    cardTheme: CardThemeData(
      color: Palette.paper,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Palette.outline, width: 2),
      ),
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Palette.skyDeep,
        foregroundColor: Palette.paper,
        textStyle: AppTypography.pixelDisplay(12, color: Palette.paper),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Palette.outline, width: 2),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Palette.cocoa,
        side: const BorderSide(color: Palette.outline, width: 2),
        textStyle: AppTypography.pixelDisplay(12),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.paper,
      hintStyle: AppTypography.cozy(14, color: Palette.cocoaSoft),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Palette.outline, width: 2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Palette.outline, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Palette.skyDeep, width: 2),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Palette.creamDeep,
      side: const BorderSide(color: Palette.outline, width: 2),
      labelStyle: AppTypography.cozy(13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Palette.cream,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: AppTypography.pixelDisplay(16),
      systemOverlayStyle: SystemUiOverlayStyle.dark,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Palette.creamDeep,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(color: Palette.outline, width: 2),
      ),
      showDragHandle: true,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Palette.cocoa,
      contentTextStyle: AppTypography.cozy(14, color: Palette.paper),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: const DividerThemeData(color: Palette.outline, thickness: 2),
  );
}
