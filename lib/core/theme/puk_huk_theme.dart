import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Puk Huk Design System
// Mirrors WSW dark aesthetic: deep navy surfaces, neon cyan primary,
// amber accents, Orbitron display font for game feel.
// ─────────────────────────────────────────────────────────────────────────────
abstract class PukHukTheme {
  // ── Brand Palette ──────────────────────────────────────────────────────────
  static const Color primary = Color(0xFF00E5FF);       // Neon cyan
  static const Color secondary = Color(0xFFFF6D00);     // Amber (opponent)
  static const Color surface = Color(0xFF0D1117);       // Deep navy
  static const Color surfaceVariant = Color(0xFF161B22);
  static const Color cardBg = Color(0xFF1C2128);
  static const Color eloGold = Color(0xFFFFD700);
  static const Color success = Color(0xFF00C853);
  static const Color danger = Color(0xFFD50000);
  static const Color textPrimary = Color(0xFFE6EDF3);
  static const Color textSecondary = Color(0xFF8B949E);

  // ── HUD-specific ───────────────────────────────────────────────────────────
  static const Color hudBackground = Color(0xCC0D1117); // 80% opacity
  static const Color hudBorder = Color(0xFF30363D);
  static const Color speedHigh = Color(0xFFFF4444);
  static const Color speedLow = Color(0xFF44FF88);

  // ── Tier Colors ────────────────────────────────────────────────────────────
  static const Map<String, Color> tierColors = {
    'bronze': Color(0xFFCD7F32),
    'silver': Color(0xFFC0C0C0),
    'gold': eloGold,
    'diamond': primary,
  };

  // ── Full Theme ─────────────────────────────────────────────────────────────
  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: surface,
        surfaceContainerHighest: surfaceVariant,
        onPrimary: Color(0xFF0D1117),
        onSurface: textPrimary,
        onSecondary: Colors.white,
        error: danger,
      ),
      scaffoldBackgroundColor: surface,
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: hudBorder, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: surface,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: GoogleFonts.orbitron(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            letterSpacing: 1.5,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: const BorderSide(color: primary),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: hudBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: hudBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        labelStyle: const TextStyle(color: textSecondary),
        hintStyle: const TextStyle(color: textSecondary),
      ),
      dividerTheme:
          const DividerThemeData(color: hudBorder, thickness: 1, space: 1),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: hudBorder,
      ),
      textTheme: _buildTextTheme(base.textTheme),
    );
  }

  static TextTheme _buildTextTheme(TextTheme base) {
    return base.copyWith(
      // Display — game titles, score digits
      displayLarge: GoogleFonts.orbitron(
        fontSize: 48,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        letterSpacing: 2,
      ),
      displayMedium: GoogleFonts.orbitron(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: textPrimary,
        letterSpacing: 1,
      ),
      displaySmall: GoogleFonts.orbitron(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: textPrimary,
      ),
      // Headlines — section titles
      headlineMedium: GoogleFonts.orbitron(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      // Titles — card headers, nav labels
      titleLarge: GoogleFonts.orbitron(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: textPrimary,
        letterSpacing: 1,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      titleSmall: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: textSecondary,
      ),
      // Body — general content
      bodyLarge: GoogleFonts.inter(fontSize: 16, color: textPrimary),
      bodyMedium: GoogleFonts.inter(fontSize: 14, color: textPrimary),
      bodySmall: GoogleFonts.inter(fontSize: 12, color: textSecondary),
      // Labels — tags, badges, buttons
      labelLarge: GoogleFonts.orbitron(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: primary,
        letterSpacing: 1.5,
      ),
      labelSmall: GoogleFonts.orbitron(
        fontSize: 9,
        fontWeight: FontWeight.w600,
        color: textSecondary,
        letterSpacing: 2,
      ),
    );
  }
}
