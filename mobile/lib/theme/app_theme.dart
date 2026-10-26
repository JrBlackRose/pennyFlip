import 'package:flutter/material.dart';

/// Dark, high-contrast "institutional quant terminal" palette — think a
/// trading desk monitor, not a consumer fintech app. Numbers are the hero;
/// chrome stays quiet and monochrome so pass/fail/veto colors read
/// instantly against it.
class AppColors {
  AppColors._();

  static const bgVoid = Color(0xFF05070A); // outermost background
  static const bgSurface = Color(0xFF0B0F14); // cards / panels
  static const bgSurfaceRaised = Color(0xFF121821); // nested panels, inputs
  static const borderSubtle = Color(0xFF1E2630);
  static const borderStrong = Color(0xFF2B3542);

  static const textPrimary = Color(0xFFE7EDF4);
  static const textSecondary = Color(0xFF8C98A8);
  static const textTertiary = Color(0xFF5C6878);

  // Semantic signal colors — used consistently for pass/fail/veto/pending
  // across the funnel, badges and candidate feed.
  static const signalPass = Color(0xFF1FE3A8); // mint/teal — module cleared
  static const signalFail = Color(0xFFFF5470); // red — module rejected
  static const signalVeto = Color(0xFFFF8A3D); // amber-orange — dump-trap veto specifically
  static const signalPending = Color(0xFF4C7EFF); // blue — in progress / queued
  static const signalWarn = Color(0xFFFFC94C); // yellow — caution / near-threshold

  static const accentPrimary = Color(0xFF1FE3A8); // ticker/brand accent, daemon-active glow
  static const accentDim = Color(0xFF0E7A5A);

  static const chartGrid = Color(0xFF1A212B);
}

class AppTheme {
  AppTheme._();

  static const monoFontFamily = 'monospace';

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bgVoid,
      colorScheme: const ColorScheme.dark(
        surface: AppColors.bgSurface,
        primary: AppColors.accentPrimary,
        secondary: AppColors.signalPending,
        error: AppColors.signalFail,
        onSurface: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bgVoid,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: AppColors.bgSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.borderSubtle),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.borderSubtle, thickness: 1),
      textTheme: base.textTheme
          .apply(
            bodyColor: AppColors.textPrimary,
            displayColor: AppColors.textPrimary,
          )
          .copyWith(
            bodySmall: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.bgSurfaceRaised,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.accentPrimary),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? AppColors.accentPrimary : AppColors.textTertiary),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? AppColors.accentDim : AppColors.bgSurfaceRaised),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentPrimary,
          foregroundColor: Colors.black,
          textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.3),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.borderStrong),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.bgSurfaceRaised,
        contentTextStyle: TextStyle(color: AppColors.textPrimary),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static TextStyle mono({
    double size = 13,
    Color color = AppColors.textPrimary,
    FontWeight weight = FontWeight.w500,
    double letterSpacing = 0.2,
  }) {
    return TextStyle(
      fontFamily: monoFontFamily,
      fontSize: size,
      color: color,
      fontWeight: weight,
      letterSpacing: letterSpacing,
    );
  }
}

Color signalColor(SignalKind kind) {
  switch (kind) {
    case SignalKind.pass:
      return AppColors.signalPass;
    case SignalKind.fail:
      return AppColors.signalFail;
    case SignalKind.veto:
      return AppColors.signalVeto;
    case SignalKind.pending:
      return AppColors.signalPending;
    case SignalKind.warn:
      return AppColors.signalWarn;
  }
}

enum SignalKind { pass, fail, veto, pending, warn }
