import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // --- BASE COLORS (UOL Brand) ---
  static const Color uolPrimary = Color(0xFF00693E); // Deep Green
  static const Color uolSecondary = Color(0xFF10B981); // Emerald Green

  // --- GRADIENT COLORS ---
  static const Color lightGradientStart = Color(0xFFFFFFFF);
  static const Color lightGradientMiddle = Color(0xFFF0FDF4);
  static const Color lightGradientEnd = Color(0xFFDCFCE7);

  static const Color darkGradientStart = Colors.black;
  static const Color darkGradientMiddle = Color(0xFF050505);
  static const Color darkGradientEnd = Color(0xFF0A0A0A);

  // ===========================================================================
  // LIGHT THEME (Kept exactly as you provided)
  // Text Color: #5B6469
  // ===========================================================================
  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: uolPrimary,
    scaffoldBackgroundColor: Colors.white,

    // ---- TEXT THEME (Poppins) ----
    textTheme: GoogleFonts.poppinsTextTheme().copyWith(
      // Profile Name (Large)
      headlineLarge: GoogleFonts.poppins(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: Colors.black,
        letterSpacing: 0.5,
      ),
      // Profile Name (Small/Edit Mode)
      headlineSmall: GoogleFonts.poppins(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Colors.black,
      ),
      // Section Headers
      headlineMedium: GoogleFonts.poppins(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: uolPrimary,
      ),
      // Values
      bodyMedium: GoogleFonts.poppins(
        fontSize: 16,
        color: const Color(0xFF5B6469), // Dark Greyish Blue
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
      // Labels
      labelMedium: GoogleFonts.poppins(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF15803D),
        letterSpacing: 0.5,
      ),
    ),

    // --- INPUT FIELDS ---
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      // Hint Text
      hintStyle: GoogleFonts.poppins(
          color: const Color(0xFF5B6469),
          fontSize: 14,
          fontWeight: FontWeight.w500
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: const Color(0xFF5B6469).withOpacity(0.3), width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: uolPrimary, width: 2),
      ),
    ),
    cardColor: Colors.white,
    iconTheme: const IconThemeData(color: uolPrimary),
  );

  // ===========================================================================
  // DARK THEME (Updated for Visibility)
  // Old Grey (#B3B3B3) -> Replaced with Bright Silver (#E0E0E0) & Light Grey (#CCCCCC)
  // ===========================================================================
  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    primaryColor: uolPrimary,
    scaffoldBackgroundColor: Colors.black,

    // ---- TEXT THEME (Poppins) ----
    textTheme: GoogleFonts.poppinsTextTheme().copyWith(
      // Profile Name (Large)
      headlineLarge: GoogleFonts.poppins(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        letterSpacing: 0.5,
      ),
      // Profile Name (Small/Edit Mode)
      headlineSmall: GoogleFonts.poppins(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
      // Section Headers
      headlineMedium: GoogleFonts.poppins(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
      // Values (Body Text) -> UPDATED TO BRIGHTER COLOR
      bodyMedium: GoogleFonts.poppins(
        fontSize: 16,
        color: const Color(0xFFE0E0E0), // Bright Silver (Visible on Black)
        fontWeight: FontWeight.w500,
        height: 1.4,
      ),
      // Labels -> Neon Green
      labelMedium: GoogleFonts.poppins(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF4ADE80),
        letterSpacing: 0.5,
      ),
    ),

    // --- INPUT FIELDS ---
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF151515),
      // Hint Text -> UPDATED TO LIGHTER GREY
      hintStyle: GoogleFonts.poppins(
          color: const Color(0xFFCCCCCC), // Lighter Grey (Visible on Black)
          fontSize: 14,
          fontWeight: FontWeight.w500
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      // Border Color -> UPDATED
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: const Color(0xFFE0E0E0).withOpacity(0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: uolSecondary, width: 2),
      ),
    ),
    cardColor: Colors.black,
    iconTheme: const IconThemeData(color: Colors.white),
  );

  // --- GRADIENT HELPER ---
  static List<Color> getGradient(Brightness brightness) {
    return brightness == Brightness.dark
        ? [darkGradientStart, darkGradientMiddle, darkGradientEnd]
        : [lightGradientStart, lightGradientMiddle, lightGradientEnd];
  }
}