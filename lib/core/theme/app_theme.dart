import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color primaryTeal = Color(0xFF008080);
  static const Color primaryBlue = Color(0xFF0000FF);
  static const Color accentTeal = Color(0xFF20B2AA);
  
  static LinearGradient get primaryGradient => const LinearGradient(
        colors: [primaryTeal, primaryBlue],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryTeal,
        primary: primaryTeal,
        secondary: primaryBlue,
      ),
      textTheme: GoogleFonts.outfitTextTheme(),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryTeal,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
        ),
      ),
    );
  }
}
