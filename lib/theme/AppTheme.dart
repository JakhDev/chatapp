import 'package:flutter/material.dart';

class AppColors {
  // Dark
  static const Color dBackground   = Color(0xFF0D0E1A);
  static const Color dSurface      = Color(0xFF161728);
  static const Color dSurfaceLight = Color(0xFF1E2035);
  static const Color dTextPrimary  = Color(0xFFEEEEFF);
  static const Color dTextSecondary= Color(0xFF8888AA);
  static const Color dMyMsgBg      = Color(0xFF6C63FF);
  static const Color dOtherMsgBg   = Color(0xFF1E2035);

  // Light
  static const Color lBackground   = Color(0xFFF2F2F7);
  static const Color lSurface      = Color(0xFFFFFFFF);
  static const Color lSurfaceLight = Color(0xFFE8E8F0);
  static const Color lTextPrimary  = Color(0xFF1A1A2E);
  static const Color lTextSecondary= Color(0xFF6B6B8A);
  static const Color lMyMsgBg      = Color(0xFF6C63FF);
  static const Color lOtherMsgBg   = Color(0xFFFFFFFF);

  // Shared
  static const Color primary       = Color(0xFF6C63FF);
  static const Color primaryDark   = Color(0xFF4A42D6);
  static const Color accent        = Color(0xFF00D4AA);
  static const Color online        = Color(0xFF00D4AA);
  static const Color offline       = Color(0xFF555577);
}

class AppTheme {
  // ── Legacy static (dark) — mavjud kod bilan moslik ──────────────────────
  static const Color primary       = AppColors.primary;
  static const Color primaryDark   = AppColors.primaryDark;
  static const Color accent        = AppColors.accent;
  static const Color online        = AppColors.online;
  static const Color offline       = AppColors.offline;

  static const Color background    = AppColors.dBackground;
  static const Color surface       = AppColors.dSurface;
  static const Color surfaceLight  = AppColors.dSurfaceLight;
  static const Color textPrimary   = AppColors.dTextPrimary;
  static const Color textSecondary = AppColors.dTextSecondary;
  static const Color myMsgBg       = AppColors.dMyMsgBg;
  static const Color otherMsgBg    = AppColors.dOtherMsgBg;

  // ── Dark theme ───────────────────────────────────────────────────────────
  static ThemeData get darkTheme => _build(
    brightness:  Brightness.dark,
    bg:          AppColors.dBackground,
    surface:     AppColors.dSurface,
    surfLight:   AppColors.dSurfaceLight,
    textPri:     AppColors.dTextPrimary,
    textSec:     AppColors.dTextSecondary,
  );

  // ── Light theme ──────────────────────────────────────────────────────────
  static ThemeData get lightTheme => _build(
    brightness:  Brightness.light,
    bg:          AppColors.lBackground,
    surface:     AppColors.lSurface,
    surfLight:   AppColors.lSurfaceLight,
    textPri:     AppColors.lTextPrimary,
    textSec:     AppColors.lTextSecondary,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color surfLight,
    required Color textPri,
    required Color textSec,
  }) => ThemeData(
    brightness:             brightness,
    scaffoldBackgroundColor: bg,
    primaryColor:           AppColors.primary,
    colorScheme: ColorScheme(
      brightness:   brightness,
      primary:      AppColors.primary,
      onPrimary:    Colors.white,
      secondary:    AppColors.accent,
      onSecondary:  Colors.white,
      surface:      surface,
      onSurface:    textPri,
      error:        Colors.red,
      onError:      Colors.white,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      elevation: 0,
      iconTheme: IconThemeData(color: textPri),
      titleTextStyle: TextStyle(
          color: textPri, fontSize: 18, fontWeight: FontWeight.w700),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfLight,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      hintStyle: TextStyle(color: textSec),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    ),
    textTheme: TextTheme(
      bodyLarge:  TextStyle(color: textPri,  fontSize: 15),
      bodyMedium: TextStyle(color: textPri,  fontSize: 14),
      bodySmall:  TextStyle(color: textSec, fontSize: 12),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
      s.contains(WidgetState.selected) ? AppColors.primary : null),
      trackColor: WidgetStateProperty.resolveWith((s) =>
      s.contains(WidgetState.selected)
          ? AppColors.primary.withOpacity(0.3) : null),
    ),
  );
}