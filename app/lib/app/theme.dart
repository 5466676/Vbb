import 'package:flutter/material.dart';

/// Design tokens: the neon «system window» look — a near-black void, deep navy panels with
/// glowing cyan edges, violet accents and bright seat colours that glow on the dark map.
abstract final class AppColors {
  static const background = Color(0xFF05070F); // void
  static const surface = Color(0xFF0B1730); // panel navy
  static const panel = Color(0xFF0B1730);
  static const panelDeep = Color(0xFF060E22);
  static const parchment = Color(0xFF0E1D3D); // kept name: light panels are now a lifted navy
  static const parchmentDark = Color(0xFF0A1530);
  static const ink = Color(0xFFE6F7FF); // text on panels
  static const neon = Color(0xFF3FD0FF); // edges, focus, primary
  static const violet = Color(0xFF8A5CFF);
  static const gold = Color(0xFFFFCF4A); // rank S, rewards, crowns
  static const seal = Color(0xFFFF3D5A); // danger / attack
  static const accent = neon;
  static const textPrimary = Color(0xFFE6F7FF);
  static const textSecondary = Color(0xFF8FB3C9);
  static const good = Color(0xFF5DFFB0);
  static const bad = Color(0xFFFF4D6A);
  static const glassFill = Color(0xCC0B1730);
  static const glassBorder = Color(0x993FD0FF);

  /// One colour per seat: bright, distinct, readable as a glow on the dark map.
  static const seats = [
    Color(0xFFFF3D5A), // red
    Color(0xFF3FA0FF), // blue
    Color(0xFF3DFFA0), // green
    Color(0xFFFFC93D), // amber
    Color(0xFFB06BFF), // violet
    Color(0xFF2DE2E6), // cyan
    Color(0xFFFF8A3D), // orange
    Color(0xFFC8D0DC), // silver
  ];
  static const bannerGold = neon; // thin bright thread inside owned borders
  static const bannerText = textPrimary;

  static Color seat(int? s) => s == null || s < 0 ? const Color(0x00000000) : seats[s % seats.length];

  /// The glow used on every neon edge.
  static List<BoxShadow> glow(Color c, {double blur = 10, double alpha = 0.6}) => [
    BoxShadow(
      color: c.withValues(alpha: alpha),
      blurRadius: blur,
    ),
  ];

  /// A «system window»: navy panel, 1.5px neon edge, outer glow and a faint inner glow.
  static BoxDecoration window({Color edge = neon, double radius = 8, Color fill = panel}) => BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color.lerp(fill, edge, 0.08)!, fill],
    ),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: edge, width: 1.6),
    boxShadow: glow(edge),
  );
}

abstract final class AppTheme {
  static const fontFamily = 'Cairo';
  static const headingFont = 'Ruqaa'; // Aref Ruqaa, for titles only

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.neon, brightness: Brightness.dark).copyWith(
      primary: AppColors.neon,
      onPrimary: AppColors.background,
      secondary: AppColors.violet,
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
          backgroundColor: AppColors.neon,
          foregroundColor: AppColors.background,
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
        backgroundColor: AppColors.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.neon, width: 1.6),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w900,
          fontSize: 24,
          color: AppColors.neon,
        ),
      ),
    );
  }
}
