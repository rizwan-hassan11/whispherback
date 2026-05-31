import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/layout/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/playlist.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/playback_providers.dart';
import 'widgets/playlist_card.dart';

class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistsProvider);
    final theme = whisperTheme(context);
    final l10n = context.l10n;

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
        Positioned(
          top: -40,
          right: -30,
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.brandLight.withValues(alpha: theme.isDark ? 0.08 : 0.12),
            ),
          ),
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: playlistsAsync.when(
              data: (playlists) => _PlaylistsBody(
                playlists: playlists,
                onCreate: () => context.push('/playlists/new'),
                onOpen: (id) => context.push('/playlists/$id'),
                onPlay: (id) =>
                    ref.read(playbackCoordinatorProvider).playPlaylist(id),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
            ),
          ),
          floatingActionButton: playlistsAsync.maybeWhen(
            data: (list) => list.isEmpty ? null : FloatingActionButton.extended(
              onPressed: () => context.push('/playlists/new'),
              icon: const Icon(AppIcons.add),
              label: Text(l10n.newPlaylist),
            ),
            orElse: () => null,
          ),
        ),
      ],
    );
  }

}

class _PlaylistsBody extends StatelessWidget {
  const _PlaylistsBody({
    required this.playlists,
    required this.onCreate,
    required this.onOpen,
    required this.onPlay,
  });

  final List<Playlist> playlists;
  final VoidCallback onCreate;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = whisperTheme(context);
    final l10n = context.l10n;

    if (playlists.isEmpty) {
      return PlaylistsEmptyState(onCreate: onCreate);
    }

    final totalClips = playlists.fold<int>(0, (s, p) => s + p.clipCount);
    final scheduled = playlists.where((p) => p.hasSchedule).length;
    final scheduledList = playlists.where((p) => p.hasSchedule).toList();
    final otherList = playlists.where((p) => !p.hasSchedule).toList();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
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
                  l10n.collectionsSummary(playlists.length, totalClips),
                  style: TextStyle(fontSize: 13, color: theme.muted),
                ),
                const SizedBox(height: 20),
                PlaylistsSummaryStrip(
                  playlistCount: playlists.length,
                  clipCount: totalClips,
                  scheduledCount: scheduled,
                ),
                const SizedBox(height: 24),
                if (scheduledList.isNotEmpty) ...[
                  _SectionLabel(l10n.scheduled, theme: theme),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
        if (scheduledList.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.separated(
              itemCount: scheduledList.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final p = scheduledList[i];
                return PlaylistCard(
                  playlist: p,
                  index: i,
                  onTap: () => onOpen(p.id),
                  onPlay: p.clipCount > 0 ? () => onPlay(p.id) : null,
                );
              },
            ),
          ),
        if (otherList.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _SectionLabel(l10n.yourLibrary, theme: theme),
                  TextButton.icon(
                    onPressed: () => context.push('/clips'),
                    icon: const Icon(AppIcons.mic, size: 18),
                    label: Text(l10n.addClips),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.brandLight,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, context.shellScrollPadding.bottom),
            sliver: SliverList.separated(
              itemCount: otherList.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final p = otherList[i];
                return PlaylistCard(
                  playlist: p,
                  index: scheduledList.length + i,
                  onTap: () => onOpen(p.id),
                  onPlay: p.clipCount > 0 ? () => onPlay(p.id) : null,
                );
              },
            ),
          ),
        ] else
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
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
