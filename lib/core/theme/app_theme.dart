import 'package:flutter/material.dart';

class AppTheme {
  // Colors - Dark Theme (matching mobile app)
  static const Color primaryColor = Color(0xFFFFD54F); // Gold/Yellow accent
  static const Color secondaryColor = Color(0xFFFFC107); // Amber
  static const Color errorColor = Color(0xFFEF5350); // Red 400
  static const Color successColor = Color(0xFF4CAF50); // Green 500
  static const Color warningColor = Color(0xFFFFDA6A); // Yellow warning

  // Gradient Colors - Gold gradient
  static const Color gradientStart = Color(0xFFFFD54F);
  static const Color gradientEnd = Color(0xFFFFC107);

  // Text Colors - Light text for dark theme
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0B0B0);
  static const Color textHint = Color(0xFF666666);

  // Background Colors - Dark theme
  static const Color backgroundColor = Color(0xFF121212); // Main background
  static const Color surfaceColor = Color(0xFF1E1E1E); // Cards, dialogs
  static const Color elevatedSurfaceColor = Color(0xFF252525); // Elevated cards, inputs
  static const Color cardColor = Color(0xFF252525);

  // Border Colors - Dark borders
  static const Color borderColor = Color(0xFF2D2D2D);

  // Gradient
  static const LinearGradient primaryGradient =
      LinearGradient(
        colors: [gradientStart, gradientEnd],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  // Background Image Decoration
  static BoxDecoration get backgroundDecoration => const BoxDecoration(
    image: DecorationImage(
      image: AssetImage('assets/images/background.png'),
      fit: BoxFit.cover,
    ),
  );

  // Main Theme - Dark Theme (matching mobile app)
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    primaryColor: primaryColor,
    scaffoldBackgroundColor: backgroundColor,
    colorScheme: const ColorScheme.dark(
      primary: primaryColor,
      secondary: secondaryColor,
      error: errorColor,
      surface: surfaceColor,
      onPrimary: Color(0xFF121212), // Dark text on gold buttons
      onSurface: Color(0xFFFFFFFF),
      onError: Colors.white,
    ),

    // AppBar Theme
    appBarTheme: const AppBarTheme(
      backgroundColor: surfaceColor,
      foregroundColor: textPrimary,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
    ),

    // Card Theme
    cardTheme: CardThemeData(
      color: cardColor,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),

    // Input Decoration Theme
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: elevatedSurfaceColor,
      hintStyle: const TextStyle(
        color: textHint,
        fontSize: 14,
      ),
      labelStyle: const TextStyle(
        color: textSecondary,
        fontSize: 14,
      ),
      floatingLabelStyle: const TextStyle(
        color: primaryColor,
        fontSize: 14,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(
          color: primaryColor,
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: errorColor),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 16,
      ),
    ),

    // Elevated Button Theme
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Color(0xFF121212), // Dark text on gold
        padding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 12,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: 2,
      ),
    ),

    // Text Button Theme
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primaryColor,
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
      ),
    ),

    // Icon Theme
    iconTheme: const IconThemeData(
      color: textSecondary,
      size: 24,
    ),

    // Dialog Theme
    dialogTheme: DialogThemeData(
      backgroundColor: surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),

    // Snackbar Theme
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: elevatedSurfaceColor,
      contentTextStyle: TextStyle(color: textPrimary),
    ),
  );

  // Dark Theme alias
  static ThemeData darkTheme = lightTheme;
}
