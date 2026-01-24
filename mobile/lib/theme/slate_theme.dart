import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class SlateTheme {
  // -------------------------
  // LIGHT THEME GETTER
  // -------------------------
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: _LightColors.background,

      // Typography
      fontFamily: GoogleFonts.inter().fontFamily,
      textTheme: GoogleFonts.interTextTheme().apply(
        bodyColor: _LightColors.foreground,
        displayColor: _LightColors.foreground,
      ),

      // Color Scheme
      colorScheme: const ColorScheme(
        brightness: Brightness.light,
        primary: _LightColors.primary,
        onPrimary: _LightColors.primaryForeground,
        secondary: _LightColors.secondary,
        onSecondary: _LightColors.secondaryForeground,
        error: _LightColors.destructive,
        onError: _LightColors.destructiveForeground,
        surface: _LightColors.card,
        onSurface: _LightColors.cardForeground,
        outline: _LightColors.border,
      ),

      // Component Styles
      appBarTheme: const AppBarTheme(
        backgroundColor: _LightColors.background,
        foregroundColor: _LightColors.foreground,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
          color: _LightColors.foreground,
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _LightColors.primary,
          foregroundColor: _LightColors.primaryForeground,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _LightColors.foreground,
          side: const BorderSide(color: _LightColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),

      cardTheme: CardThemeData(
        color: _LightColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: _LightColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _LightColors.background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _LightColors.input),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _LightColors.input),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _LightColors.ring, width: 2),
        ),
        hintStyle: const TextStyle(color: _LightColors.mutedForeground),
      ),
    );
  }

  // -------------------------
  // DARK THEME GETTER
  // -------------------------
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _DarkColors.background,

      // Typography
      fontFamily: GoogleFonts.inter().fontFamily,
      textTheme: GoogleFonts.interTextTheme().apply(
        bodyColor: _DarkColors.foreground,
        displayColor: _DarkColors.foreground,
      ),

      // Color Scheme
      colorScheme: const ColorScheme(
        brightness: Brightness.dark,
        primary: _DarkColors.primary,
        onPrimary: _DarkColors.primaryForeground,
        secondary: _DarkColors.secondary,
        onSecondary: _DarkColors.secondaryForeground,
        error: _DarkColors.destructive,
        onError: _DarkColors.destructiveForeground,
        surface: _DarkColors.card,
        onSurface: _DarkColors.cardForeground,
        outline: _DarkColors.border,
      ),

      // Component Styles
      appBarTheme: const AppBarTheme(
        backgroundColor: _DarkColors.background,
        foregroundColor: _DarkColors.foreground,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
          color: _DarkColors.foreground,
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _DarkColors.primary,
          foregroundColor: _DarkColors.primaryForeground,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _DarkColors.foreground,
          side: const BorderSide(color: _DarkColors.border),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),

      cardTheme: CardThemeData(
        color: _DarkColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: _DarkColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _DarkColors.background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _DarkColors.input),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _DarkColors.input),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: _DarkColors.ring, width: 2),
        ),
        hintStyle: const TextStyle(color: _DarkColors.mutedForeground),
      ),
    );
  }
}

// -------------------------
// COLOR PALETTES
// -------------------------

class _LightColors {
  static const Color background = Color(0xFFFFFFFF);
  static const Color foreground = Color(0xFF020817);
  static const Color card = Color(0xFFFFFFFF);
  static const Color cardForeground = Color(0xFF020817);
  static const Color primary = Color(0xFF0F172A);
  static const Color primaryForeground = Color(0xFFF8FAFC);
  static const Color secondary = Color(0xFFF1F5F9);
  static const Color secondaryForeground = Color(0xFF0F172A);
  static const Color mutedForeground = Color(0xFF64748B);
  static const Color destructive = Color(0xFFEF4444);
  static const Color destructiveForeground = Color(0xFFF8FAFC);
  static const Color border = Color(0xFFE2E8F0);
  static const Color input = Color(0xFFE2E8F0);
  static const Color ring = Color(0xFF020817);
}

class _DarkColors {
  static const Color background = Color(0xFF020817);
  static const Color foreground = Color(0xFFF8FAFC);
  static const Color card = Color(0xFF020817);
  static const Color cardForeground = Color(0xFFF8FAFC);
  static const Color primary = Color(0xFFF8FAFC);
  static const Color primaryForeground = Color(0xFF0F172A);
  static const Color secondary = Color(0xFF1E293B);
  static const Color secondaryForeground = Color(0xFFF8FAFC);
  static const Color mutedForeground = Color(0xFF94A3B8);
  static const Color destructive = Color(0xFF7F1D1D);
  static const Color destructiveForeground = Color(0xFFF8FAFC);
  static const Color border = Color(0xFF1E293B);
  static const Color input = Color(0xFF1E293B);
  static const Color ring = Color(0xFFCBD5E1);
}
