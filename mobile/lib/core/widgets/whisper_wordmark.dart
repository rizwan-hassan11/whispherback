import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

/// Typographic WhisperBack banner matching the Light/Dark Ocean brand art.
///
/// Renders "Whisper" + "Back" in split brand colors with the official
/// tagline underneath — no raster assets required.
class WhisperWordmark extends StatelessWidget {
  const WhisperWordmark({
    super.key,
    this.showTagline = false,
    this.titleFontSize = 22,
    this.taglineFontSize = 9,
    this.alignment = CrossAxisAlignment.start,
    this.compact = false,
  });

  /// When true, shows "YOUR PERSONALIZED AUDIO WHISPERER" under the title.
  final bool showTagline;

  final double titleFontSize;
  final double taglineFontSize;
  final CrossAxisAlignment alignment;

  /// Tighter letter-spacing / line gaps for compact headers.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final whisperColor =
        isDark ? AppColors.wordmarkWhisperDark : AppColors.wordmarkWhisperLight;
    final backColor =
        isDark ? AppColors.wordmarkBackDark : AppColors.wordmarkBackLight;
    final taglineColor =
        isDark ? AppColors.wordmarkTaglineDark : AppColors.wordmarkTaglineLight;

    final titleStyle = GoogleFonts.montserrat(
      fontSize: titleFontSize,
      fontWeight: FontWeight.w700,
      height: 1.05,
      letterSpacing: compact ? -0.6 : -0.8,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignment,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Whisper',
                style: titleStyle.copyWith(color: whisperColor),
              ),
              TextSpan(
                text: 'Back',
                style: titleStyle.copyWith(color: backColor),
              ),
            ],
          ),
        ),
        if (showTagline) ...[
          SizedBox(height: compact ? 4 : 6),
          Text(
            'YOUR PERSONALIZED AUDIO WHISPERER',
            textAlign: alignment == CrossAxisAlignment.center
                ? TextAlign.center
                : TextAlign.start,
            style: GoogleFonts.montserrat(
              fontSize: taglineFontSize,
              fontWeight: FontWeight.w500,
              letterSpacing: compact ? 1.4 : 2.0,
              height: 1.2,
              color: taglineColor,
            ),
          ),
        ],
      ],
    );
  }
}
