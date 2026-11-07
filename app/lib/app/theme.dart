import 'package:flutter/material.dart';

/// Design tokens: dark glassmorphism with a teal accent.
abstract final class AppColors {
  static const accent = Color(0xFF2DD4BF);
  static const background = Color(0xFF0B1220);
  static const surface = Color(0xFF111A2E);
  static const glassFill = Color(0x1AFFFFFF); // 10% white
  static const glassBorder = Color(0x33FFFFFF); // 20% white
  static const textPrimary = Color(0xFFF1F5F9);
  static const textSecondary = Color(0xFF94A3B8);
}

abstract final class AppTheme {
  static const fontFamily = 'Cairo';

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.accent,
      surface: AppColors.surface,
      onPrimary: AppColors.background,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: ThemeData.dark().textTheme.apply(
            fontFamily: fontFamily,
            bodyColor: AppColors.textPrimary,
            displayColor: AppColors.textPrimary,
          ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.glassBorder),
          textStyle: const TextStyle(
            fontFamily: fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}
