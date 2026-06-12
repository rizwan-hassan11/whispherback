import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/layout/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/audio_clip.dart';
import '../../domain/entities/playback_schedule.dart';
import '../../domain/entities/playlist.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/duration_format.dart';
import '../../l10n/schedule_l10n.dart';
import '../../providers/playback_providers.dart';
import '../../providers/repository_providers.dart';
import '../../services/notifications/notification_sync.dart';
import 'widgets/add_clips_sheet.dart';
import 'widgets/playlist_clip_tile.dart';

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId});

  final String playlistId;

  @override
  ConsumerState<PlaylistDetailScreen> createState() =>
      _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  Playlist? _playlist;
  PlaybackSchedule? _schedule;
  List<AudioClip> _clips = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final playlistRepo = ref.read(playlistRepositoryProvider);
    final scheduleRepo = ref.read(scheduleRepositoryProvider);
    final playlist = await playlistRepo.getById(widget.playlistId);
    final clips = await playlistRepo.getClips(widget.playlistId);
    final schedule = await scheduleRepo.getForPlaylist(widget.playlistId);
    if (!mounted) return;
    setState(() {
      _playlist = playlist;
      _clips = clips;
      _schedule = schedule;
      _loading = false;
    });
  }

  Future<void> _toggleShuffle() async {
    if (_playlist == null) return;
    final next = !_playlist!.shuffleEnabled;
    await ref
        .read(playlistRepositoryProvider)
        .setShuffle(widget.playlistId, next);
    setState(() => _playlist = _playlist!.copyWith(shuffleEnabled: next));
  }

  Future<void> _rename() async {
    if (_playlist == null) return;
    final l10n = context.l10n;
    final controller = TextEditingController(text: _playlist!.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.renamePlaylist),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.playlistName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == _playlist!.name) return;
    await ref.read(playlistRepositoryProvider).rename(widget.playlistId, name);
    ref.invalidate(playlistsProvider);
    if (mounted) {
      setState(() => _playlist = _playlist!.copyWith(name: name));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.playlistRenamed)),
      );
    }
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deletePlaylist),
        content: Text(l10n.deletePlaylistConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final deleted =
        await ref.read(playlistRepositoryProvider).delete(widget.playlistId);
    if (!mounted) return;
    if (!deleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.deletePlaylistBlocked)),
      );
      return;
    }
    ref.invalidate(playlistsProvider);
    await syncWhisperNotifications(
      appState: ref.read(appStateRepositoryProvider),
      schedules: ref.read(scheduleRepositoryProvider),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.playlistDeleted)),
      );
      context.go('/playlists');
    }
  }

  Future<void> _removeClip(AudioClip clip) async {
    await ref
        .read(playlistRepositoryProvider)
        .removeClip(widget.playlistId, clip.id);
    ref.invalidate(playlistsProvider);
    await _load();
  }

  void _showAddClips() {
    showAddClipsSheet(
      context,
      ref,
      playlistId: widget.playlistId,
      playlistName: _playlist?.name ?? context.l10n.playlist,
      onChanged: _load,
    );
  }

  int get _totalMs => _clips.fold(0, (s, c) => s + c.durationMs);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = whisperTheme(context);

    if (_loading) {
      return Scaffold(
        backgroundColor: theme.background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final name = _playlist?.name ?? l10n.playlist;
    final shuffle = _playlist?.shuffleEnabled ?? false;

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
          top: 0,
          left: 0,
          right: 0,
          height: 280,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.brand.withValues(alpha: theme.isDark ? 0.45 : 0.2),
                  AppColors.brandLight
                      .withValues(alpha: theme.isDark ? 0.15 : 0.08),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                leading: IconButton(
                  icon: Icon(AppIcons.back, color: theme.foreground),
                  onPressed: () => context.pop(),
                ),
                actions: [
                  IconButton(
                    tooltip: l10n.schedules,
                    icon: Icon(AppIcons.schedule, color: theme.foreground),
                    onPressed: () =>
                        context.push('/schedule/build/${widget.playlistId}'),
                  ),
                  PopupMenuButton<String>(
                    icon: Icon(AppIcons.moreVertical, color: theme.foreground),
                    onSelected: (v) {
                      switch (v) {
                        case 'rename':
                          _rename();
                        case 'delete':
                          _delete();
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'rename',
                        child: Row(
                          children: [
                            Icon(AppIcons.edit, size: 18, color: theme.foreground),
                            const SizedBox(width: 10),
                            Text(l10n.renamePlaylist),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            const Icon(AppIcons.trash, size: 18, color: AppColors.error),
                            const SizedBox(width: 10),
                            Text(l10n.deletePlaylist,
                                style: const TextStyle(color: AppColors.error)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                expandedHeight: 0,
                toolbarHeight: 56,
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PlaylistHero(
                        theme: theme,
                        name: name,
                        clipCount: _clips.length,
                        totalDuration:
                            formatPlaylistDurationLocalized(context, _totalMs),
                        hasSchedule: _schedule != null,
                      ),
                      const SizedBox(height: 16),
                      _ActionRow(
                        theme: theme,
                        shuffleOn: shuffle,
                        onShuffle: _toggleShuffle,
                        onSchedule: () => context
                            .push('/schedule/build/${widget.playlistId}'),
                        onAddClips: _showAddClips,
                      ),
                      if (_schedule != null) ...[
                        const SizedBox(height: 16),
                        _ScheduleCard(schedule: _schedule!, theme: theme),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        l10n.clipsUpper,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                          color: theme.muted,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              if (_clips.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyClipsState(
                    theme: theme,
                    onAdd: _showAddClips,
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                      20, 0, 20, context.shellScrollPadding.bottom),
                  sliver: SliverList.separated(
                    itemCount: _clips.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final clip = _clips[i];
                      return Dismissible(
                        key: ValueKey(clip.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(AppIcons.trash, color: Colors.white),
                        ),
                        confirmDismiss: (_) async {
                          return await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text(l10n.removeFromPlaylist),
                                  content: Text(clip.title),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: Text(l10n.cancel),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: Text(l10n.removeFromPlaylist),
                                    ),
                                  ],
                                ),
                              ) ??
                              false;
                        },
                        onDismissed: (_) => _removeClip(clip),
                        child: PlaylistClipTile(
                          clip: clip,
                          index: i,
                          onPlay: () => ref
                              .read(playbackCoordinatorProvider)
                              .playClip(clip),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
          bottomNavigationBar: _clips.isEmpty
              ? null
              : _PlayBar(
                  theme: theme,
                  clipCount: _clips.length,
                  onPlay: () => ref
                      .read(playbackCoordinatorProvider)
                      .playPlaylist(widget.playlistId),
                ),
        ),
      ],
    );
  }
}

class _PlaylistHero extends StatelessWidget {
  const _PlaylistHero({
    required this.theme,
    required this.name,
    required this.clipCount,
    required this.totalDuration,
    required this.hasSchedule,
  });

  final WhisperThemeExtension theme;
  final String name;
  final int clipCount;
  final String totalDuration;
  final bool hasSchedule;

  static const _barHeights = [14.0, 26.0, 38.0, 22.0, 34.0, 18.0];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: theme.isDark
              ? [
                  Colors.white.withValues(alpha: 0.11),
                  Colors.white.withValues(alpha: 0.04),
                  AppColors.card.withValues(alpha: 0.35),
                ]
              : [
                  Colors.white.withValues(alpha: 0.95),
                  const Color(0xE0F1F5F9),
                ],
        ),
        border: Border.all(
          color: theme.isDark
              ? Colors.white.withValues(alpha: 0.18)
              : AppColors.ink.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: theme.isDark ? 0.38 : 0.1),
            blurRadius: 52,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.card, AppColors.ink],
                  ),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.42),
                      blurRadius: 42,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final h in _barHeights)
                      Container(
                        width: 5,
                        height: h,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.25),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (hasSchedule)
                Positioned(
                  top: -8,
                  right: -10,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
                    decoration: BoxDecoration(
                      color: AppColors.deep.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                          color: AppColors.success.withValues(alpha: 0.45)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.success,
                            boxShadow: [
                              BoxShadow(
                                color:
                                    AppColors.success.withValues(alpha: 0.65),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          l10n.live,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.soft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (hasSchedule) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.success,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.success.withValues(alpha: 0.55),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.scheduledActiveNow,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.muted,
                    ),
                  ),
                ],
              ),
            ),
          ] else
            const SizedBox(height: 18),
          Text(
            name,
            textAlign: TextAlign.center,
            style: GoogleFonts.fraunces(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: theme.foreground,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeroStatChip(
                theme: theme,
                icon: AppIcons.mic,
                label: l10n.clipCountLabel(clipCount),
              ),
              _HeroStatChip(
                theme: theme,
                icon: AppIcons.schedule,
                label: totalDuration,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStatChip extends StatelessWidget {
  const _HeroStatChip({
    required this.theme,
    required this.icon,
    required this.label,
  });

  final WhisperThemeExtension theme;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: theme.isDark ? 0.1 : 0.65),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: theme.isDark
              ? Colors.white.withValues(alpha: 0.16)
              : AppColors.ink.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.muted),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.theme,
    required this.shuffleOn,
    required this.onShuffle,
    required this.onSchedule,
    required this.onAddClips,
  });

  final WhisperThemeExtension theme;
  final bool shuffleOn;
  final VoidCallback onShuffle;
  final VoidCallback onSchedule;
  final VoidCallback onAddClips;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        stops: [0.0, 0.05, 0.95, 1.0],
        colors: [
          Colors.transparent,
          Colors.black,
          Colors.black,
          Colors.transparent,
        ],
      ).createShader(bounds),
      blendMode: BlendMode.dstIn,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              _ActionChip(
                theme: theme,
                icon: AppIcons.shuffle,
                label: shuffleOn ? l10n.shuffleOn : l10n.shuffleOff,
                selected: shuffleOn,
                onTap: onShuffle,
              ),
              const SizedBox(width: 8),
              _ActionChip(
                theme: theme,
                icon: AppIcons.schedule,
                label: l10n.schedules,
                onTap: onSchedule,
              ),
              const SizedBox(width: 8),
              _ActionChip(
                theme: theme,
                icon: AppIcons.add,
                label: l10n.addClips,
                onTap: onAddClips,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.theme,
    required this.icon,
    required this.label,
    this.selected = false,
    required this.onTap,
  });

  final WhisperThemeExtension theme;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.goldSoft : theme.glass,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected
              ? AppColors.gold.withValues(alpha: 0.35)
              : theme.glassBorder,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? AppColors.gold : theme.foreground,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppColors.gold : theme.foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.schedule, required this.theme});

  final PlaybackSchedule schedule;
  final WhisperThemeExtension theme;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toString();
    final time = DateFormat.jm(locale).format(schedule.startTime);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.goldSoft,
            theme.glass,
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(AppIcons.schedule, color: AppColors.gold),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.scheduledPlayback,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: theme.foreground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.scheduleStartsEvery(
                      time, schedule.intervalLabelL10n(context)),
                  style: TextStyle(fontSize: 12, color: theme.muted),
                ),
              ],
            ),
          ),
          Icon(AppIcons.chevronRight, color: theme.muted, size: 20),
        ],
      ),
    );
  }
}

class _EmptyClipsState extends StatelessWidget {
  const _EmptyClipsState({required this.theme, required this.onAdd});

  final WhisperThemeExtension theme;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(AppIcons.mic, size: 48, color: theme.muted),
          const SizedBox(height: 16),
          Text(
            l10n.noClipsInPlaylist,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: theme.foreground,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.recordOrImportClips,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.muted, fontSize: 13),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(AppIcons.add),
            label: Text(l10n.browseClips),
          ),
        ],
      ),
    );
  }
}

class _PlayBar extends StatelessWidget {
  const _PlayBar({
    required this.theme,
    required this.clipCount,
    required this.onPlay,
  });

  final WhisperThemeExtension theme;
  final int clipCount;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: theme.isDark
            ? AppColors.card.withValues(alpha: 0.95)
            : AppColors.lightCard.withValues(alpha: 0.98),
        border: Border(top: BorderSide(color: theme.glassBorder)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: theme.isDark ? 0.3 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.playAll,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: theme.foreground,
                    ),
                  ),
                  Text(
                    l10n.clipsInOrder(clipCount),
                    style: TextStyle(fontSize: 12, color: theme.muted),
                  ),
                ],
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onPlay,
                customBorder: const StadiumBorder(),
                child: Ink(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(100),
                    gradient: AppColors.brandGradient,
                    boxShadow: const [
                      BoxShadow(color: AppColors.brandGlow, blurRadius: 16),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(AppIcons.play, color: Colors.white, size: 24),
                      const SizedBox(width: 4),
                      Text(
                        l10n.play,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
