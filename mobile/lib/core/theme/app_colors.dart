import 'package:flutter/material.dart';

abstract final class AppColors {
  // Dark palette
  static const deep = Color(0xFF020611);
  static const deep2 = Color(0xFF040B1E);
  static const brand = Color(0xFFF1F5F9);
  static const brandLight = Color(0xFFFFFFFF);
  static const brandDark = Color(0xFFCBD5E1);
  static const brandGlow = Color(0x1FFFFFFF);
  static const soft = Color(0xFFF1F5F9);
  static const accent = Color(0xFF94A3B8);
  static const accentBright = Color(0xFFB8C5D6);
  static const gold = Color(0xFFB8C5D6);
  static const goldSoft = Color(0x29B8C5D6);
  static const ink = Color(0xFF061331);
  static const inkSecondary = Color(0xFF0A2048);
  static const muted = Color(0xFF94A3B8);
  static const muted2 = Color(0xFF64748B);
  static const card = Color(0xFF0C2044);
  static const cardElevated = Color(0xFF102850);
  static const surface = Color(0x1AFFFFFF);
  static const surfaceHover = Color(0x24FFFFFF);
  static const glass = Color(0x1AFFFFFF);
  static const glassBorder = Color(0x33FFFFFF);
  static const line = Color(0xFFCBD5E1);
  static const success = Color(0xFF4ADEAA);
  static const error = Color(0xFFC44B4B);

  // Light palette
  static const lightBg = Color(0xFFF8FAFC);
  static const lightBg2 = Color(0xFFF1F5F9);
  static const lightBg3 = Color(0xFFE2E8F0);
  static const lightSoft = Color(0xFF020611);
  static const lightMuted = Color(0xFF475569);
  static const lightMuted2 = Color(0xFF64748B);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightGlass = Color(0x08061331);
  static const lightGlassBorder = Color(0x1A061331);
  static const lightBrandGlow = Color(0x1A061331);

  /// Primary action fill — navy in light, soft white in dark.
  static Color actionFill(bool isDark) => isDark ? brand : ink;

  /// Text/icon on primary action buttons.
  static Color onActionFill(bool isDark) => isDark ? deep : lightBg;

  /// Accent icon tint for tiles and highlights.
  static Color accentIcon(bool isDark) => isDark ? brandLight : ink;

  static const backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [deep, deep2, ink],
  );

  static const lightBackgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [lightBg, lightBg2, lightBg3],
  );

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brand, brandDark],
  );

  static const goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brand, brandDark],
  );

  static List<BoxShadow> elevationSm(bool isDark) => [
        BoxShadow(
          color: isDark
              ? Colors.black.withValues(alpha: 0.22)
              : const Color(0xFF061331).withValues(alpha: 0.08),
          blurRadius: isDark ? 16 : 14,
          offset: const Offset(0, 4),
        ),
      ];

  static BoxDecoration proSurface({
    required bool isDark,
    double radius = 10,
    Color? borderColor,
  }) =>
      BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0x17FFFFFF), const Color(0x0AFFFFFF)]
              : [lightCard, lightBg],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ??
              (isDark ? const Color(0x29FFFFFF) : lightGlassBorder),
        ),
        boxShadow: elevationSm(isDark),
      );
}
