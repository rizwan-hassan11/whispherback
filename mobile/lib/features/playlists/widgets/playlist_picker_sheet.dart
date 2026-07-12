import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/layout/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/playlist_cover.dart';
import '../../../domain/entities/playlist.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/duration_format.dart';
import '../../../providers/playback_providers.dart';
import 'add_clips_sheet.dart';

/// Pick which playlist to add library clips into.
Future<void> showPlaylistPickerForClips(
  BuildContext context,
  WidgetRef ref, {
  required List<Playlist> playlists,
}) {
  final l10n = context.l10n;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final theme = whisperTheme(ctx);
      final r = ctx.responsive;
      return Padding(
        padding: EdgeInsets.only(
          left: r.horizontalGutter,
          right: r.horizontalGutter,
          bottom: MediaQuery.paddingOf(ctx).bottom + 12,
        ),
        child: Material(
          color: theme.isDark ? AppColors.card : Colors.white,
          borderRadius: BorderRadius.circular(20),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Text(
                    l10n.selectPlaylistForClips,
                    style: GoogleFonts.fraunces(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: theme.foreground,
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(ctx).height * 0.5,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                    itemCount: playlists.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final p = playlists[i];
                      final colors = PlaylistCoverPalette.colorsForIndex(
                        i,
                        isDark: theme.isDark,
                      );
                      return ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: theme.glassBorder),
                        ),
                        leading: PlaylistCoverArt(
                          colors: colors,
                          size: 44,
                          borderRadius: 10,
                          hasSchedule: p.hasSchedule,
                        ),
                        title: Text(
                          p.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: theme.foreground,
                          ),
                        ),
                        subtitle: Text(
                          l10n.clipsSummary(
                            p.clipCount,
                            formatPlaylistDurationLocalized(
                              context,
                              p.totalDurationMs,
                            ),
                          ),
                          style: TextStyle(fontSize: 12, color: theme.muted),
                        ),
                        trailing: const Icon(AppIcons.chevronRight, size: 18),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          showAddClipsSheet(
                            context,
                            ref,
                            playlistId: p.id,
                            playlistName: p.name,
                            onChanged: () =>
                                ref.invalidate(playlistsProvider),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
