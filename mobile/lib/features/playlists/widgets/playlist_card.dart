import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_radii.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/duration_format.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/depth_surface.dart';
import '../../../core/widgets/prominent_play_button.dart';
import '../../../core/widgets/whisper_card.dart';
import '../../../domain/entities/playlist.dart';

/// Legacy English formatter; prefer [formatPlaylistDurationLocalized].
String formatPlaylistDuration(int totalMs) {
  if (totalMs <= 0) return '0 sec';
  final sec = totalMs ~/ 1000;
  if (sec < 60) return '$sec sec';
  final min = sec ~/ 60;
  final rem = sec % 60;
  if (rem == 0) return '$min min';
  return '$min min $rem sec';
}

class PlaylistCard extends StatelessWidget {
  const PlaylistCard({
    super.key,
    required this.playlist,
    required this.index,
    this.onTap,
    this.onPlay,
  });

  final Playlist playlist;
  final int index;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;

  List<Color> _coverColors(WhisperThemeExtension theme) {
    if (theme.isDark) {
      final palettes = [
        [AppColors.brandDark, AppColors.brandLight],
        [AppColors.deep2, AppColors.inkSecondary],
        [const Color(0xFF0A2048), AppColors.gold.withValues(alpha: 0.85)],
        [const Color(0xFF3D5A80), const Color(0xFF5B8FC4)],
      ];
      return palettes[index % palettes.length];
    }
    final lightPalettes = [
      [AppColors.ink, AppColors.inkSecondary],
      [const Color(0xFF0A2048), AppColors.ink],
      [const Color(0xFF1E3A5F), const Color(0xFF3D5A80)],
      [AppColors.inkSecondary, const Color(0xFF0A2048)],
    ];
    return lightPalettes[index % lightPalettes.length];
  }

  static bool _coverIsDark(List<Color> colors) {
    final mid = Color.lerp(colors.first, colors.last, 0.5)!;
    return mid.computeLuminance() < 0.45;
  }

  @override
  Widget build(BuildContext context) {
    final theme = whisperTheme(context);
    final l10n = context.l10n;
    final colors = _coverColors(theme);
    final darkCover = _coverIsDark(colors);

    return DepthTile(
      onTap: onTap,
      radius: AppRadii.sm,
      elevated: true,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CoverArt(
            colors: colors,
            hasSchedule: playlist.hasSchedule,
            darkCover: darkCover,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  playlist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: theme.foreground,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.clipsSummary(
                    playlist.clipCount,
                    formatPlaylistDurationLocalized(
                        context, playlist.totalDurationMs),
                  ),
                  style: TextStyle(fontSize: 12, color: theme.muted),
                ),
                if (playlist.hasSchedule || playlist.shuffleEnabled) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (playlist.hasSchedule)
                        WhisperBadge(
                          label: l10n.scheduledBadge,
                          variant: WhisperBadgeVariant.gold,
                        ),
                      if (playlist.shuffleEnabled)
                        WhisperBadge(label: l10n.shuffleOn),
                    ],
                  ),
                ],
                if (playlist.hasSchedule && playlist.clipCount > 0) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: 0.55,
                      minHeight: 4,
                      backgroundColor: theme.glassBorder,
                      color: theme.actionFill,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              if (playlist.clipCount > 0 && onPlay != null)
                ProminentPlayButton(onTap: onPlay)
              else
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.glass,
                    border: Border.all(color: theme.glassBorder),
                  ),
                  child: Icon(AppIcons.add, size: 20, color: theme.muted),
                ),
              const SizedBox(height: 10),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: theme.isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : AppColors.ink.withValues(alpha: 0.05),
                  border: Border.all(
                    color: theme.isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : AppColors.ink.withValues(alpha: 0.08),
                  ),
                ),
                child: Icon(AppIcons.chevronRight,
                    color: theme.foreground, size: 16),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CoverArt extends StatelessWidget {
  const _CoverArt({
    required this.colors,
    required this.hasSchedule,
    required this.darkCover,
  });

  final List<Color> colors;
  final bool hasSchedule;
  final bool darkCover;

  @override
  Widget build(BuildContext context) {
    final barColor = darkCover
        ? Colors.white.withValues(alpha: 0.92)
        : AppColors.deep.withValues(alpha: 0.62);
    final markColor = darkCover
        ? Colors.white.withValues(alpha: 0.38)
        : AppColors.deep.withValues(alpha: 0.2);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.sm),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                AppIcons.music,
                color: markColor,
                size: 24,
              ),
              Positioned(
                bottom: 10,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _bar(8, barColor),
                    _bar(14, barColor),
                    _bar(20, barColor),
                    _bar(12, barColor),
                    _bar(16, barColor),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (hasSchedule)
          const Positioned(
            top: -5,
            right: -5,
            child: ScheduleBadgeDot(),
          ),
      ],
    );
  }

  Widget _bar(double h, Color color) => Container(
        width: 4,
        height: h,
        margin: const EdgeInsets.symmetric(horizontal: 1.5),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      );
}

class PlaylistsSummaryStrip extends StatelessWidget {
  const PlaylistsSummaryStrip({
    super.key,
    required this.playlistCount,
    required this.clipCount,
    required this.scheduledCount,
  });

  final int playlistCount;
  final int clipCount;
  final int scheduledCount;

  @override
  Widget build(BuildContext context) {
    final theme = whisperTheme(context);
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.brand.withValues(alpha: theme.isDark ? 0.28 : 0.12),
            theme.glass,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.glassBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryCell(
              theme: theme,
              value: '$playlistCount',
              label: l10n.playlists,
              icon: AppIcons.playlists,
              color: AppColors.brandLight,
            ),
          ),
          Container(width: 1, height: 36, color: theme.glassBorder),
          Expanded(
            child: _SummaryCell(
              theme: theme,
              value: '$clipCount',
              label: l10n.totalClips,
              icon: AppIcons.mic,
              color: AppColors.success,
            ),
          ),
          Container(width: 1, height: 36, color: theme.glassBorder),
          Expanded(
            child: _SummaryCell(
              theme: theme,
              value: '$scheduledCount',
              label: l10n.scheduled,
              icon: AppIcons.schedule,
              color: AppColors.gold,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCell extends StatelessWidget {
  const _SummaryCell({
    required this.theme,
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  final WhisperThemeExtension theme;
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: theme.foreground,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 10, color: theme.muted)),
      ],
    );
  }
}

class PlaylistsEmptyState extends StatelessWidget {
  const PlaylistsEmptyState({super.key, required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final theme = whisperTheme(context);
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.brandLight.withValues(alpha: 0.25),
                    theme.glass,
                  ],
                ),
                border: Border.all(color: theme.glassBorder),
              ),
              child: Icon(
                AppIcons.playlists,
                size: 44,
                color: AppColors.brandLight.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.noPlaylistsYet,
              style: GoogleFonts.fraunces(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: theme.foreground,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.afterCreatingHint,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.muted, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(AppIcons.add),
              label: Text(l10n.createPlaylist),
            ),
          ],
        ),
      ),
    );
  }
}
