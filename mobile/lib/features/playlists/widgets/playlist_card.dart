import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_radii.dart';
import '../../../core/theme/playlist_cover.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/duration_format.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ux/tap_feedback.dart';
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
    this.isPlaying = false,
    this.onTap,
    this.onPlayPause,
    this.onFavourite,
    this.onEdit,
    this.onDelete,
  });

  final Playlist playlist;
  final int index;
  final bool isPlaying;
  final VoidCallback? onTap;
  final VoidCallback? onPlayPause;
  final VoidCallback? onFavourite;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = whisperTheme(context);
    final colors =
        PlaylistCoverPalette.colorsForIndex(index, isDark: theme.isDark);

    return RepaintBoundary(
      child: DepthSurface(
        radius: AppRadii.sm,
        elevated: true,
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap == null
                      ? null
                      : () {
                          selectionHaptic();
                          onTap!();
                        },
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      PlaylistCoverArt(
                        colors: colors,
                        size: 52,
                        hasSchedule: playlist.hasSchedule,
                        isPlaying: isPlaying,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                          child:
                              _PlaylistInfo(playlist: playlist, theme: theme)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _PlaylistCardActions(
              theme: theme,
              playlist: playlist,
              isPlaying: isPlaying,
              onOpen: onTap,
              onPlayPause: onPlayPause,
              onFavourite: onFavourite,
              onEdit: onEdit,
              onDelete: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaylistInfo extends StatelessWidget {
  const _PlaylistInfo({required this.playlist, required this.theme});

  final Playlist playlist;
  final WhisperThemeExtension theme;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: theme.foreground,
                ),
              ),
            ),
            if (playlist.isFavourite)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(AppIcons.heart, size: 14, color: AppColors.gold),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          l10n.clipsSummary(
            playlist.clipCount,
            formatPlaylistDurationLocalized(context, playlist.totalDurationMs),
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
              if (playlist.shuffleEnabled) WhisperBadge(label: l10n.shuffleOn),
            ],
          ),
        ],
      ],
    );
  }
}

class _PlaylistCardActions extends StatelessWidget {
  const _PlaylistCardActions({
    required this.theme,
    required this.playlist,
    required this.isPlaying,
    this.onOpen,
    this.onPlayPause,
    this.onFavourite,
    this.onEdit,
    this.onDelete,
  });

  final WhisperThemeExtension theme;
  final Playlist playlist;
  final bool isPlaying;
  final VoidCallback? onOpen;
  final VoidCallback? onPlayPause;
  final VoidCallback? onFavourite;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canPlay = playlist.clipCount > 0 && onPlayPause != null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canPlay)
          ProminentPlayButton(
            onTap: onPlayPause,
            isPlaying: isPlaying,
            size: 42,
            iconSize: 19,
          )
        else
          Semantics(
            label: l10n.addClips,
            button: true,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onOpen == null
                    ? null
                    : () {
                        selectionHaptic();
                        onOpen!();
                      },
                borderRadius: BorderRadius.circular(21),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.glass,
                    border: Border.all(color: theme.glassBorder),
                  ),
                  child: Icon(AppIcons.add, size: 20, color: theme.muted),
                ),
              ),
            ),
          ),
        _PlaylistOverflowMenu(
          theme: theme,
          isFavourite: playlist.isFavourite,
          onFavourite: onFavourite,
          onEdit: onEdit,
          onDelete: onDelete,
        ),
      ],
    );
  }
}

/// Compact 3-dot overflow menu holding the secondary card actions
/// (favourite / rename / delete). Keeps the card short and tidy.
class _PlaylistOverflowMenu extends StatelessWidget {
  const _PlaylistOverflowMenu({
    required this.theme,
    required this.isFavourite,
    this.onFavourite,
    this.onEdit,
    this.onDelete,
  });

  final WhisperThemeExtension theme;
  final bool isFavourite;
  final VoidCallback? onFavourite;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopupMenuButton<_CardAction>(
      tooltip: l10n.moreOptions,
      icon: Icon(AppIcons.moreVertical, size: 20, color: theme.muted),
      padding: EdgeInsets.zero,
      splashRadius: 20,
      color: theme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      position: PopupMenuPosition.under,
      onSelected: (action) {
        selectionHaptic();
        switch (action) {
          case _CardAction.favourite:
            onFavourite?.call();
            break;
          case _CardAction.edit:
            onEdit?.call();
            break;
          case _CardAction.delete:
            onDelete?.call();
            break;
        }
      },
      itemBuilder: (context) => [
        if (onFavourite != null)
          PopupMenuItem(
            value: _CardAction.favourite,
            child: _MenuRow(
              icon: AppIcons.heart,
              color: isFavourite ? AppColors.gold : theme.foreground,
              label: isFavourite
                  ? l10n.removeFromFavourites
                  : l10n.addToFavourites,
              theme: theme,
            ),
          ),
        if (onEdit != null)
          PopupMenuItem(
            value: _CardAction.edit,
            child: _MenuRow(
              icon: AppIcons.edit,
              color: theme.foreground,
              label: l10n.renamePlaylist,
              theme: theme,
            ),
          ),
        if (onDelete != null)
          PopupMenuItem(
            value: _CardAction.delete,
            child: _MenuRow(
              icon: AppIcons.trash,
              color: AppColors.error,
              label: l10n.deletePlaylist,
              theme: theme,
            ),
          ),
      ],
    );
  }
}

enum _CardAction { favourite, edit, delete }

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.theme,
  });

  final IconData icon;
  final Color color;
  final String label;
  final WhisperThemeExtension theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(fontSize: 14, color: theme.foreground),
        ),
      ],
    );
  }
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
              color: AppColors.neonBright,
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
              color: AppColors.neonBright,
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
