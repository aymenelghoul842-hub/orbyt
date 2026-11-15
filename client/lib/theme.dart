import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const String appName = 'Orbyt';
const String appTagline = 'Meet someone new. Instantly.';

/// Orbyt palette: ink-black base, solar lime + mint energy, ultraviolet depth.
class AppColors {
  static const bg = Color(0xFF05060A);
  static const surface = Color(0xFF0E1018);
  static const violet = Color(0xFF8B6CFF);
  static const mint = Color(0xFF3DF5C8);
  static const lime = Color(0xFFC6FF4D);
  static const pink = Color(0xFFFF5FA8);
  static const green = Color(0xFF34D399);
  static const text = Color(0xFFF2F3F8);
  static const muted = Color(0xFF9A9CB5);
  static const onCta = Color(0xFF0A0F03);

  /// Decorative gradient (logo, headline accents).
  static const gradient = LinearGradient(
    colors: [violet, mint],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Primary call-to-action gradient.
  static const cta = LinearGradient(
    colors: [lime, mint],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Display headline font (Space Grotesk) - body text uses Inter via the theme.
TextStyle display({
  double size = 32,
  FontWeight weight = FontWeight.w700,
  double? height,
  double? letterSpacing,
  Color? color,
}) =>
    GoogleFonts.spaceGrotesk(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      color: color ?? AppColors.text,
    );

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.lime,
      secondary: AppColors.mint,
      tertiary: AppColors.violet,
      surface: AppColors.surface,
    ),
    textTheme: GoogleFonts.interTextTheme(base.textTheme)
        .apply(bodyColor: AppColors.text, displayColor: AppColors.text),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF1A1C28),
      contentTextStyle: GoogleFonts.inter(color: AppColors.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
