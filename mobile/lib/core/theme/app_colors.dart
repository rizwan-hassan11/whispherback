import 'package:flutter/material.dart';

/// Oceanic brand palette derived from the WhisperBack logo + Light/Dark Ocean banners.
abstract final class AppColors {
  // Dark ocean palette (logo navy + deep water)
  static const deep = Color(0xFF0A2A43);
  static const deep2 = Color(0xFF071E32);
  static const brand = Color(0xFFF1F8FB);
  static const brandLight = Color(0xFFFFFFFF);
  static const brandDark = Color(0xFFB8D4E6);
  static const brandGlow = Color(0x1F5DD5E8);
  static const soft = Color(0xFFF1F8FB);
  static const accent = Color(0xFF7CA4BC);
  static const accentBright = Color(0xFF5DD5E8);
  static const gold = Color(0xFF5DD5E8);
  static const goldSoft = Color(0x295DD5E8);
  static const ink = Color(0xFF0D3554);
  static const inkSecondary = Color(0xFF124A6E);
  static const muted = Color(0xFF7CA4BC);
  static const muted2 = Color(0xFF5C88A0);
  static const card = Color(0xFF0F3554);
  static const cardElevated = Color(0xFF14466A);
  static const surface = Color(0x1AFFFFFF);
  static const surfaceHover = Color(0x24FFFFFF);
  static const glass = Color(0x1AFFFFFF);
  static const glassBorder = Color(0x33FFFFFF);
  static const line = Color(0xFFB8D4E6);
  static const success = Color(0xFF4ADEAA);
  static const error = Color(0xFFC44B4B);

  // Neon / accent — cyan core from the logo center bar.
  static const neon = Color(0xFF34B3E4);
  static const neonBright = Color(0xFF5DD5E8);
  static const neonCyan = Color(0xFF5DD5E8);
  static const neonDeep = Color(0xFF186CA8);
  static const neonGlow = Color(0x665DD5E8);

  static const neonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [neonCyan, neon, neonDeep],
    stops: [0, 0.55, 1],
  );

  /// Dim "powered-off" gradient for the home power control.
  static const powerOffGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0D3554), Color(0xFF071E32)],
  );

  // Light ocean palette (banner Light Ocean)
  static const lightBg = Color(0xFFF5FAFC);
  static const lightBg2 = Color(0xFFEEF5F9);
  static const lightBg3 = Color(0xFFE4EEF4);
  static const lightSoft = Color(0xFF0A2A43);
  static const lightMuted = Color(0xFF3D5F78);
  static const lightMuted2 = Color(0xFF5C88A0);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightGlass = Color(0x080A2A43);
  static const lightGlassBorder = Color(0x1A0A2A43);
  static const lightBrandGlow = Color(0x1A186CA8);

  // Wordmark banner colors (match Light/Dark Ocean art)
  static const wordmarkWhisperDark = Color(0xFFF0F8FB);
  static const wordmarkBackDark = Color(0xFF5DD5E8);
  static const wordmarkTaglineDark = Color(0xFF7CA4BC);
  static const wordmarkWhisperLight = Color(0xFF0A2A43);
  static const wordmarkBackLight = Color(0xFF186CA8);
  static const wordmarkTaglineLight = Color(0xFF5C88A0);

  /// Primary action fill — ocean cyan in dark, deep navy in light.
  static Color actionFill(bool isDark) => isDark ? neonCyan : deep;

  /// Text/icon on primary action buttons.
  static Color onActionFill(bool isDark) => isDark ? deep : lightBg;

  /// Accent icon tint for tiles and highlights.
  static Color accentIcon(bool isDark) => isDark ? neonCyan : deep;

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
    colors: [neonCyan, neon],
  );

  static const goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [neonCyan, neonDeep],
  );

  static List<BoxShadow> elevationSm(bool isDark) => [
        BoxShadow(
          color: isDark
              ? Colors.black.withValues(alpha: 0.28)
              : const Color(0xFF0A2A43).withValues(alpha: 0.08),
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
