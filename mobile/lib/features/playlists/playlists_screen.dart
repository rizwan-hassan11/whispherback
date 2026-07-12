import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/layout/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_error_view.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/playback/playlist_playback_badge.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/playback_providers.dart';
import 'playlist_actions.dart';
import 'widgets/playlist_card.dart';
import 'widgets/playlist_picker_sheet.dart';

class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistsProvider);
    // Rebuild the list only when the active playlist or play/pause state
    // changes — not on every unrelated snapshot tick.
    final playbackBadge = ref.watch(
      playbackSnapshotProvider.select(
        (async) => PlaylistPlaybackBadge.fromSnapshot(async.valueOrNull),
      ),
    );
    final theme = whisperTheme(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: theme.isDark
                  ? [AppColors.deep2, AppColors.deep]
                  : [AppColors.lightBg, AppColors.lightBg2],
            ),
          ),
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: playlistsAsync.when(
              data: (playlists) => _PlaylistsBody(
                playlists: playlists,
                playbackBadge: playbackBadge,
                onCreate: () => context.push('/playlists/new'),
                onOpen: (id) => context.push('/playlists/$id'),
                onAddClips: () => showPlaylistPickerForClips(
                  context,
                  ref,
                  playlists: playlists,
                ),
                onPlayPause: (id) => togglePlaylistPlayPause(
                  context,
                  ref,
                  playlistId: id,
                  snapshot: ref.read(playbackSnapshotProvider).valueOrNull,
                ),
                onFavourite: (id, fav) => togglePlaylistFavourite(
                  ref,
                  playlistId: id,
                  favourite: fav,
                ),
                onEdit: (id, name) => renamePlaylistDialog(
                  context,
                  ref,
                  playlistId: id,
                  currentName: name,
                ),
                onDelete: (id, name) => deletePlaylistDialog(
                  context,
                  ref,
                  playlistId: id,
                  playlistName: name,
                ),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => AsyncErrorView(
                error: e,
                onRetry: () => ref.invalidate(playlistsProvider),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlaylistsBody extends StatelessWidget {
  const _PlaylistsBody({
    required this.playlists,
    required this.playbackBadge,
    required this.onCreate,
    required this.onOpen,
    required this.onAddClips,
    required this.onPlayPause,
    required this.onFavourite,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Playlist> playlists;
  final PlaylistPlaybackBadge playbackBadge;
  final VoidCallback onCreate;
  final ValueChanged<String> onOpen;
  final VoidCallback onAddClips;
  final ValueChanged<String> onPlayPause;
  final void Function(String id, bool favourite) onFavourite;
  final void Function(String id, String name) onEdit;
  final void Function(String id, String name) onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = whisperTheme(context);
    final l10n = context.l10n;

    if (playlists.isEmpty) {
      return PlaylistsEmptyState(onCreate: onCreate);
    }

    final totalClips = playlists.fold<int>(0, (s, p) => s + p.clipCount);
    final scheduled = playlists.where((p) => p.hasSchedule).length;
    final favouriteList = playlists.where((p) => p.isFavourite).toList();
    final scheduledList =
        playlists.where((p) => p.hasSchedule && !p.isFavourite).toList();
    final otherList =
        playlists.where((p) => !p.hasSchedule && !p.isFavourite).toList();

    int cardIndex(String id) => playlists.indexWhere((p) => p.id == id);

    Widget buildCard(Playlist p) {
      final i = cardIndex(p.id);
      return PlaylistCard(
        key: ValueKey(p.id),
        playlist: p,
        index: i,
        isPlaying: playbackBadge.isActiveFor(p.id),
        onTap: () => onOpen(p.id),
        onPlayPause: () => onPlayPause(p.id),
        onFavourite: () => onFavourite(p.id, !p.isFavourite),
        onEdit: () => onEdit(p.id, p.name),
        onDelete: () => onDelete(p.id, p.name),
      );
    }

    return CustomScrollView(
      cacheExtent: 480,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.playlists,
                            style: GoogleFonts.fraunces(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: theme.foreground,
                            ),
                          ),
                          Text(
                            l10n.collectionsSummary(
                                playlists.length, totalClips),
                            style: TextStyle(fontSize: 13, color: theme.muted),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: onCreate,
                      icon: const Icon(AppIcons.add, size: 18),
                      label: Text(l10n.newPlaylist),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                PlaylistsSummaryStrip(
                  playlistCount: playlists.length,
                  clipCount: totalClips,
                  scheduledCount: scheduled,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        if (favouriteList.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: _SectionLabel(l10n.favourites, theme: theme),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.separated(
              itemCount: favouriteList.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) => buildCard(favouriteList[i]),
            ),
          ),
        ],
        if (scheduledList.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  20, favouriteList.isEmpty ? 0 : 24, 20, 10),
              child: _SectionLabel(l10n.scheduled, theme: theme),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.separated(
              itemCount: scheduledList.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) => buildCard(scheduledList[i]),
            ),
          ),
        ],
        if (otherList.isNotEmpty || favouriteList.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _SectionLabel(l10n.yourLibrary, theme: theme),
                  TextButton.icon(
                    onPressed: onAddClips,
                    icon: const Icon(AppIcons.add, size: 18),
                    label: Text(l10n.addClips),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.brandLight,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (otherList.isNotEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
                20, 0, 20, context.shellScrollPadding.bottom),
            sliver: SliverList.separated(
              itemCount: otherList.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) => buildCard(otherList[i]),
            ),
          )
        else
          SliverToBoxAdapter(
            child: SizedBox(height: context.shellScrollPadding.bottom),
          ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.theme});

  final String text;
  final WhisperThemeExtension theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
        color: theme.muted,
      ),
    );
  }
}
