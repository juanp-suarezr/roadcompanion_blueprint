import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Configuración centralizada de temas claro y oscuro para ESTELA.
///
/// Implementa Material Design 3 con personalización artesanal basada en la identidad ESTELA:
/// azul noche (#071827), azul marino (#10283B), azul de tarjeta (#183449) y acentos en cian luminoso (#35D6F2).
abstract class AppTheme {
  /// Tema Claro — Conducción diurna y ambientes de alta luminosidad.
  static ThemeData get lightTheme {
    final colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.surfaceNavy,
      onPrimary: Colors.white,
      primaryContainer: AppColors.lightSurfaceVariant,
      onPrimaryContainer: AppColors.primaryTextLight,
      secondary: AppColors.electricBlue,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.lightSurfaceVariant,
      onSecondaryContainer: AppColors.surfaceNavy,
      tertiary: AppColors.cyanLuminous,
      onTertiary: AppColors.nightBlue,
      error: AppColors.error,
      onError: Colors.white,
      surface: AppColors.whiteSurface,
      onSurface: AppColors.primaryTextLight,
      onSurfaceVariant: AppColors.secondaryTextLight,
      outline: AppColors.silver,
      outlineVariant: const Color(0xFFE2E7ED),
      shadow: Colors.black.withValues(alpha: 0.08),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.lightBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.primaryTextLight,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: AppColors.whiteSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.0),
          side: const BorderSide(color: Color(0xFFE3E9F0), width: 1.0),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.surfaceNavy,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(double.infinity, 52.0),
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 14.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          textStyle: const TextStyle(
            fontSize: 16.0,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.surfaceNavy,
          minimumSize: const Size(double.infinity, 50.0),
          side: const BorderSide(color: AppColors.electricBlue, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 14.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          textStyle: const TextStyle(
            fontSize: 15.0,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 14.0,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: const BorderSide(color: Color(0xFFD7DFE8), width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: const BorderSide(
            color: AppColors.electricBlue,
            width: 2.0,
          ),
        ),
        labelStyle: const TextStyle(color: AppColors.secondaryTextLight),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE5EBF2),
        thickness: 1.0,
        space: 24.0,
      ),
    );
  }

  /// Tema Oscuro — Preferencia principal de ESTELA: azul noche inmersivo y acentos cian.
  static ThemeData get darkTheme {
    final colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.cyanLuminous,
      onPrimary: AppColors.nightBlue,
      primaryContainer: AppColors.surfaceNavy,
      onPrimaryContainer: AppColors.coldWhite,
      secondary: AppColors.electricBlue,
      onSecondary: Colors.white,
      secondaryContainer: AppColors.darkSurfaceVariant,
      onSecondaryContainer: AppColors.silver,
      tertiary: AppColors.silver,
      onTertiary: AppColors.nightBlue,
      error: AppColors.error,
      onError: AppColors.nightBlue,
      surface: AppColors.cardNavy,
      onSurface: AppColors.coldWhite,
      onSurfaceVariant: AppColors.secondaryText,
      outline: const Color(0xFF264660),
      outlineVariant: const Color(0xFF162D3E),
      shadow: Colors.black.withValues(alpha: 0.4),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.nightBlue,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.coldWhite,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardNavy,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.0),
          side: const BorderSide(color: Color(0xFF264660), width: 1.0),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.cyanLuminous,
          foregroundColor: AppColors.nightBlue,
          elevation: 0,
          minimumSize: const Size(double.infinity, 52.0),
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 14.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          textStyle: const TextStyle(
            fontSize: 16.0,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.cyanLuminous,
          minimumSize: const Size(double.infinity, 50.0),
          side: const BorderSide(color: AppColors.electricBlue, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 14.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          textStyle: const TextStyle(
            fontSize: 15.0,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 14.0,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: const BorderSide(color: Color(0xFF2B4E6C), width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.0),
          borderSide: const BorderSide(
            color: AppColors.cyanLuminous,
            width: 2.0,
          ),
        ),
        labelStyle: const TextStyle(color: AppColors.secondaryText),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF1E384E),
        thickness: 1.0,
        space: 24.0,
      ),
    );
  }
}
