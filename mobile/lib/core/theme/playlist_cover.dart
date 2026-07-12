import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_theme.dart';

/// Stable gradient palettes for playlist cover art.
///
/// Playlist colours identify individual playlists throughout the app
/// (cards, mini-player, detail hero). Index is derived from list order.
class PlaylistCoverPalette {
  const PlaylistCoverPalette._();

  static final List<List<Color>> _darkPalettes = [
    [AppColors.brandDark, AppColors.brandLight],
    [AppColors.deep2, AppColors.inkSecondary],
    [const Color(0xFF0A2048), AppColors.gold.withValues(alpha: 0.85)],
    [const Color(0xFF3D5A80), const Color(0xFF5B8FC4)],
    [AppColors.neon.withValues(alpha: 0.35), AppColors.brand],
  ];

  static final List<List<Color>> _lightPalettes = [
    [AppColors.ink, AppColors.inkSecondary],
    [const Color(0xFF0A2048), AppColors.ink],
    [const Color(0xFF1E3A5F), const Color(0xFF3D5A80)],
    [AppColors.inkSecondary, const Color(0xFF0A2048)],
    [AppColors.brand, AppColors.brandLight],
  ];

  static List<Color> colorsForIndex(int index, {required bool isDark}) {
    final palettes = isDark ? _darkPalettes : _lightPalettes;
    return palettes[index % palettes.length];
  }

  static bool coverIsDark(List<Color> colors) {
    final mid = Color.lerp(colors.first, colors.last, 0.5)!;
    return mid.computeLuminance() < 0.45;
  }

  static int indexForPlaylist(String playlistId, List<String> orderedIds) {
    final i = orderedIds.indexOf(playlistId);
    return i >= 0 ? i : playlistId.hashCode.abs();
  }
}

/// Small cover tile with waveform bars — used on cards and mini-player.
class PlaylistCoverArt extends StatelessWidget {
  const PlaylistCoverArt({
    super.key,
    required this.colors,
    this.size = 56,
    this.hasSchedule = false,
    this.isPlaying = false,
    this.borderRadius = 12,
  });

  final List<Color> colors;
  final double size;
  final bool hasSchedule;
  final bool isPlaying;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final darkCover = PlaylistCoverPalette.coverIsDark(colors);
    final barColor = darkCover
        ? Colors.white.withValues(alpha: 0.92)
        : AppColors.deep.withValues(alpha: 0.62);
    final markColor = darkCover
        ? Colors.white.withValues(alpha: 0.38)
        : AppColors.deep.withValues(alpha: 0.2);
    final scale = size / 56.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 16 * scale,
                offset: Offset(0, 4 * scale),
              ),
            ],
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.music_note_rounded,
                color: markColor,
                size: 24 * scale,
              ),
              Positioned(
                bottom: 10 * scale,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _bar(8 * scale, barColor, isPlaying),
                    _bar(14 * scale, barColor, isPlaying),
                    _bar(20 * scale, barColor, isPlaying),
                    _bar(12 * scale, barColor, isPlaying),
                    _bar(16 * scale, barColor, isPlaying),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (hasSchedule)
          Positioned(
            top: -5 * scale,
            right: -5 * scale,
            child: Container(
              width: 20 * scale,
              height: 20 * scale,
              decoration: BoxDecoration(
                color: AppColors.neon,
                shape: BoxShape.circle,
                border: Border.all(
                  color: whisperTheme(context).isDark
                      ? AppColors.deep
                      : AppColors.lightBg,
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.schedule_rounded,
                size: 11 * scale,
                color: AppColors.deep,
              ),
            ),
          ),
      ],
    );
  }

  Widget _bar(double h, Color color, bool animate) {
    final height = animate ? h : h * 0.55;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      width: 4 * (size / 56),
      height: height,
      margin: EdgeInsets.symmetric(horizontal: 1.5 * (size / 56)),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
