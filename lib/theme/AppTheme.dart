import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary      = Color(0xFF6C63FF);
  static const Color primaryDark  = Color(0xFF4A42D6);
  static const Color accent       = Color(0xFF00D4AA);
  static const Color background   = Color(0xFF0D0E1A);
  static const Color surface      = Color(0xFF161728);
  static const Color surfaceLight = Color(0xFF1E2035);
  static const Color textPrimary  = Color(0xFFEEEEFF);
  static const Color textSecondary= Color(0xFF8888AA);
  static const Color myMsgBg      = Color(0xFF6C63FF);
  static const Color otherMsgBg   = Color(0xFF1E2035);
  static const Color online       = Color(0xFF00D4AA);
  static const Color offline      = Color(0xFF555577);

  static ThemeData get darkTheme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    primaryColor: primary,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      secondary: accent,
      surface: surface,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      elevation: 0,
      iconTheme: IconThemeData(color: textPrimary),
      titleTextStyle: TextStyle(
        color: textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
      hintStyle: const TextStyle(color: textSecondary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    ),
    textTheme: const TextTheme(
      bodyLarge:  TextStyle(color: textPrimary,   fontSize: 15),
      bodyMedium: TextStyle(color: textPrimary,   fontSize: 14),
      bodySmall:  TextStyle(color: textSecondary, fontSize: 12),
    ),
  );
}