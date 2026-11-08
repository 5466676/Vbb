import 'package:flutter/material.dart';

/// Design tokens: an old war-map look — dark walnut wood, parchment panels, ink and gold.
abstract final class AppColors {
  static const background = Color(0xFF1B140D); // dark walnut
  static const surface = Color(0xFF2A2016);
  static const parchment = Color(0xFFEFE2C4);
  static const parchmentDark = Color(0xFFD9C7A0);
  static const ink = Color(0xFF2B2216);
  static const gold = Color(0xFFD4A64A);
  static const seal = Color(0xFF9E2B1F); // wax-seal red
  static const accent = gold;
  static const textPrimary = Color(0xFFF5ECD7);
  static const textSecondary = Color(0xFFB9A88A);
  static const good = Color(0xFF4E9A5B);
  static const bad = Color(0xFFC0473A);
  static const glassFill = Color(0x26000000);
  static const glassBorder = Color(0x55D4A64A);

  /// One colour per seat (flags, borders, territories). Distinct and readable on the maps.
  // «رايات ملكية»: deep banner tones that stay readable on the painted map
  static const seats = [
    Color(0xFFA4161A), // crimson
    Color(0xFF1D3D7A), // royal blue
    Color(0xFF2D6A4F), // forest green
    Color(0xFFC98A00), // gold amber
    Color(0xFF5B2A86), // royal purple
    Color(0xFF0E6E73), // deep teal
    Color(0xFFB4531C), // burnt orange
    Color(0xFF4A4E57), // iron
  ];
  static const bannerGold = Color(0xFFE8C15A);
  static const bannerText = Color(0xFFFFF3D6);

  static Color seat(int? s) => s == null || s < 0 ? const Color(0x00000000) : seats[s % seats.length];
}

abstract final class AppTheme {
  static const fontFamily = 'Cairo';
  static const headingFont = 'Ruqaa'; // Aref Ruqaa, for titles only

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.gold, brightness: Brightness.dark).copyWith(
      primary: AppColors.gold,
      onPrimary: AppColors.ink,
      secondary: AppColors.seal,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.bad,
    );

    final base = ThemeData.dark();
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: base.textTheme.apply(
        fontFamily: fontFamily,
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.glassFill,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.glassBorder),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 46),
          backgroundColor: AppColors.gold,
          foregroundColor: AppColors.ink,
          textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 18, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 46),
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.glassBorder),
          textStyle: const TextStyle(fontFamily: fontFamily, fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      dialogTheme: DialogThemeData(
        backgroundColor: const Color(0xFF2B1D0F),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.gold, width: 2),
        ),
        titleTextStyle: const TextStyle(fontFamily: headingFont, fontSize: 28, color: AppColors.gold),
      ),
    );
  }
}
