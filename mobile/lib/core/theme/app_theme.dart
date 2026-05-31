import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_radii.dart';

abstract final class AppTheme {
  static ThemeData dark({required bool showLabels, Locale? locale}) =>
      _build(brightness: Brightness.dark, showLabels: showLabels, locale: locale);

  static ThemeData light({required bool showLabels, Locale? locale}) =>
      _build(brightness: Brightness.light, showLabels: showLabels, locale: locale);

  static bool _usesArabicScript(Locale? locale) {
    final code = locale?.languageCode;
    return code == 'ar' || code == 'ur';
  }

  static ThemeData _build({
    required Brightness brightness,
    required bool showLabels,
    Locale? locale,
  }) {
    final isDark = brightness == Brightness.dark;
    final bg = isDark ? AppColors.deep : AppColors.lightBg;
    final fg = isDark ? AppColors.soft : AppColors.lightSoft;
    final muted = isDark ? AppColors.muted : AppColors.lightMuted;
    final surface = isDark ? AppColors.card : AppColors.lightCard;
    final glass = isDark ? AppColors.glass : AppColors.lightGlass;
    final glassBorder = isDark ? AppColors.glassBorder : AppColors.lightGlassBorder;
    final primary = AppColors.actionFill(isDark);
    final onPrimary = AppColors.onActionFill(isDark);

    final useArabicScript = _usesArabicScript(locale);
    final baseTextTheme = ThemeData(brightness: brightness).textTheme;
    final textTheme = (useArabicScript
            ? GoogleFonts.notoSansArabicTextTheme(baseTextTheme)
            : GoogleFonts.dmSansTextTheme(baseTextTheme))
        .apply(bodyColor: fg, displayColor: fg)
        .copyWith(
          headlineLarge: (useArabicScript
                  ? GoogleFonts.notoSansArabic(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    )
                  : GoogleFonts.fraunces(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      color: fg,
                    )),
          headlineMedium: (useArabicScript
                  ? GoogleFonts.notoSansArabic(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    )
                  : GoogleFonts.fraunces(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: fg,
                    )),
          titleMedium: useArabicScript
              ? GoogleFonts.notoSansArabic(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: fg,
                )
              : GoogleFonts.dmSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
          labelSmall: useArabicScript
              ? GoogleFonts.notoSansArabic(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: muted,
                )
              : GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.35,
                  color: muted,
                ),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      textTheme: textTheme,
      splashFactory: InkRipple.splashFactory,
      highlightColor: fg.withValues(alpha: 0.04),
      iconTheme: IconThemeData(size: 20, color: fg),
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: primary,
        onPrimary: onPrimary,
        secondary: isDark ? AppColors.gold : AppColors.lightMuted,
        onSecondary: onPrimary,
        error: AppColors.error,
        onError: Colors.white,
        surface: surface,
        onSurface: fg,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: glass,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: BorderSide(color: glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: BorderSide(color: glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          borderSide: BorderSide(
            color: isDark ? AppColors.brandLight : AppColors.ink,
            width: 1.5,
          ),
        ),
        labelStyle: TextStyle(color: muted),
        hintStyle: TextStyle(color: muted.withValues(alpha: 0.85)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: fg,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: useArabicScript
            ? GoogleFonts.notoSansArabic(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: fg,
              )
            : GoogleFonts.fraunces(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
      ),
      cardTheme: CardThemeData(
        color: isDark ? AppColors.card.withValues(alpha: 0.92) : AppColors.lightCard,
        elevation: isDark ? 0 : 1,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          side: BorderSide(
            color: isDark ? const Color(0x29FFFFFF) : glassBorder,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: glassBorder,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        textColor: fg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          elevation: isDark ? 0 : 1,
          shadowColor: isDark ? AppColors.brandGlow : AppColors.lightBrandGlow,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
          textStyle: GoogleFonts.dmSans(fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: -0.1),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return onPrimary.withValues(alpha: 0.08);
            }
            return null;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          minimumSize: const Size(0, 48),
          side: BorderSide(color: glassBorder),
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
          textStyle: GoogleFonts.dmSans(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: fg,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
          textStyle: GoogleFonts.dmSans(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: isDark ? 4 : 3,
        extendedSizeConstraints: const BoxConstraints(minHeight: 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? AppColors.cardElevated : AppColors.lightCard,
        contentTextStyle: GoogleFonts.dmSans(color: fg),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
        behavior: SnackBarBehavior.floating,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: isDark ? AppColors.brandLight : AppColors.ink,
        inactiveTrackColor: glassBorder,
        thumbColor: isDark ? AppColors.brandLight : AppColors.ink,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return isDark ? AppColors.brand.withValues(alpha: 0.2) : AppColors.ink;
            }
            return isDark ? AppColors.glass : AppColors.lightBg2;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return isDark ? AppColors.soft : AppColors.lightBg;
            }
            return muted;
          }),
          side: WidgetStateProperty.all(BorderSide(color: glassBorder)),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.sm)),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return isDark ? AppColors.deep : AppColors.lightBg;
          }
          return Colors.white;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return isDark ? AppColors.brand : AppColors.ink;
          }
          return isDark ? AppColors.muted2 : AppColors.lightMuted2.withValues(alpha: 0.45);
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      extensions: [
        WhisperThemeExtension(showLabels: showLabels, isDark: isDark),
      ],
    );
  }
}

class WhisperThemeExtension extends ThemeExtension<WhisperThemeExtension> {
  const WhisperThemeExtension({required this.showLabels, required this.isDark});

  final bool showLabels;
  final bool isDark;

  Color get foreground => isDark ? AppColors.soft : AppColors.lightSoft;
  Color get muted => isDark ? AppColors.muted : AppColors.lightMuted;
  Color get surface => isDark ? AppColors.surface : AppColors.lightSurface;
  Color get glass => isDark ? AppColors.glass : AppColors.lightGlass;
  Color get glassBorder => isDark ? AppColors.glassBorder : AppColors.lightGlassBorder;
  Color get background => isDark ? AppColors.deep : AppColors.lightBg;
  Color get actionFill => AppColors.actionFill(isDark);
  Color get onActionFill => AppColors.onActionFill(isDark);
  Color get accentIcon => AppColors.accentIcon(isDark);

  @override
  WhisperThemeExtension copyWith({bool? showLabels, bool? isDark}) {
    return WhisperThemeExtension(
      showLabels: showLabels ?? this.showLabels,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  WhisperThemeExtension lerp(
    ThemeExtension<WhisperThemeExtension>? other,
    double t,
  ) {
    if (other is! WhisperThemeExtension) return this;
    return WhisperThemeExtension(showLabels: other.showLabels, isDark: other.isDark);
  }
}

WhisperThemeExtension whisperTheme(BuildContext context) {
  return Theme.of(context).extension<WhisperThemeExtension>() ??
      const WhisperThemeExtension(showLabels: false, isDark: true);
}
