import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/layout/responsive.dart';
import '../../core/layout/shell_messenger.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/audio_clip.dart';
import '../../core/widgets/async_error_view.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/duration_format.dart';
import '../../providers/playback_providers.dart';
import '../../providers/repository_providers.dart';
import 'widgets/clip_library_tile.dart';

enum _ClipFilter { all, recorded, imported }

class ClipsScreen extends ConsumerStatefulWidget {
  const ClipsScreen({super.key});

  @override
  ConsumerState<ClipsScreen> createState() => _ClipsScreenState();
}

class _ClipsScreenState extends ConsumerState<ClipsScreen> {
  _ClipFilter _filter = _ClipFilter.all;

  List<AudioClip> _applyFilter(List<AudioClip> clips) {
    return switch (_filter) {
      _ClipFilter.all => clips,
      _ClipFilter.recorded =>
        clips.where((c) => c.source == ClipSource.recorded).toList(),
      _ClipFilter.imported =>
        clips.where((c) => c.source == ClipSource.imported).toList(),
    };
  }

  Future<void> _deleteClip(AudioClip clip) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteClip),
        content: Text(l10n.deleteClipConfirm),
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
    await ref.read(clipRepositoryProvider).delete(clip.id);
    ref.invalidate(clipsProvider);
    ref.invalidate(playlistsProvider);
    if (mounted) {
      context.showShellSnackBar(l10n.clipDeleted, icon: AppIcons.checkCircle);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clipsAsync = ref.watch(clipsProvider);
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
        Positioned(
          top: -50,
          left: -40,
          child: Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.success
                  .withValues(alpha: theme.isDark ? 0.08 : 0.12),
            ),
          ),
        ),
        Positioned(
          top: 80,
          right: -50,
          child: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.brandLight
                  .withValues(alpha: theme.isDark ? 0.1 : 0.14),
            ),
          ),
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: clipsAsync.when(
              data: (clips) {
                if (clips.isEmpty) {
                  return _EmptyClipsState(
                    theme: theme,
                    onRecord: () => context.push('/clips/record'),
                    onImport: () => context.push('/clips/import'),
                  );
                }
                return _ClipsBody(
                  clips: clips,
                  filtered: _applyFilter(clips),
                  filter: _filter,
                  theme: theme,
                  onFilter: (f) => setState(() => _filter = f),
                  onRecord: () => context.push('/clips/record'),
                  onImport: () => context.push('/clips/import'),
                  onPlayClip: (clip) =>
                      ref.read(playbackCoordinatorProvider).playClip(clip),
                  onDeleteClip: _deleteClip,
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => AsyncErrorView(
                error: e,
                onRetry: () => ref.invalidate(clipsProvider),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ClipsBody extends StatelessWidget {
  const _ClipsBody({
    required this.clips,
    required this.filtered,
    required this.filter,
    required this.theme,
    required this.onFilter,
    required this.onRecord,
    required this.onImport,
    required this.onPlayClip,
    required this.onDeleteClip,
  });

  final List<AudioClip> clips;
  final List<AudioClip> filtered;
  final _ClipFilter filter;
  final WhisperThemeExtension theme;
  final ValueChanged<_ClipFilter> onFilter;
  final VoidCallback onRecord;
  final VoidCallback onImport;
  final void Function(AudioClip clip) onPlayClip;
  final Future<void> Function(AudioClip clip) onDeleteClip;

  int get _recordedCount =>
      clips.where((c) => c.source == ClipSource.recorded).length;

  int get _importedCount =>
      clips.where((c) => c.source == ClipSource.imported).length;

  int get _totalMs => clips.fold(0, (s, c) => s + c.durationMs);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.clipLibrary,
                  style: GoogleFonts.fraunces(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: theme.foreground,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.clipsSummary(
                    clips.length,
                    formatPlaylistDurationLocalized(context, _totalMs),
                  ),
                  style: TextStyle(fontSize: 13, color: theme.muted),
                ),
                const SizedBox(height: 20),
                _ActionToolbar(
                  theme: theme,
                  onRecord: onRecord,
                  onImport: onImport,
                ),
                const SizedBox(height: 16),
                _FilterRow(
                  filter: filter,
                  theme: theme,
                  total: clips.length,
                  recorded: _recordedCount,
                  imported: _importedCount,
                  onFilter: onFilter,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.yourClips,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.35,
                        color: theme.muted,
                      ),
                    ),
                    Text(
                      l10n.itemsCount(filtered.length),
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.muted.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
        if (filtered.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                filter == _ClipFilter.recorded
                    ? l10n.noRecordedClips
                    : l10n.noImportedClips,
                style: TextStyle(color: theme.muted, fontSize: 14),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
                20, 0, 20, context.shellScrollPadding.bottom),
            sliver: SliverList.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) => ClipLibraryTile(
                clip: filtered[i],
                onPlay: () => onPlayClip(filtered[i]),
                onDelete: () => onDeleteClip(filtered[i]),
              ),
            ),
          ),
      ],
    );
  }
}

class _ActionToolbar extends StatelessWidget {
  const _ActionToolbar({
    required this.theme,
    required this.onRecord,
    required this.onImport,
  });

  final WhisperThemeExtension theme;
  final VoidCallback onRecord;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: theme.isDark ? theme.glass : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.glassBorder),
        boxShadow: theme.isDark
            ? null
            : [
                BoxShadow(
                  color: AppColors.ink.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _ToolbarButton(
              theme: theme,
              primary: true,
              icon: AppIcons.mic,
              label: l10n.record,
              onTap: onRecord,
            ),
          ),
          Expanded(
            child: _ToolbarButton(
              theme: theme,
              icon: AppIcons.upload,
              label: l10n.import,
              onTap: onImport,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.theme,
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final WhisperThemeExtension theme;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Colors.white : AppColors.neonBright;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: primary ? AppColors.neonGradient : null,
        borderRadius: BorderRadius.circular(8),
        border: primary
            ? null
            : Border.all(color: AppColors.neon.withValues(alpha: 0.45)),
        boxShadow: primary
            ? [
                BoxShadow(
                  color: AppColors.neon.withValues(alpha: 0.45),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          splashColor: AppColors.neonCyan.withValues(alpha: 0.18),
          child: SizedBox(
            height: 44,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: fg),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.filter,
    required this.theme,
    required this.total,
    required this.recorded,
    required this.imported,
    required this.onFilter,
  });

  final _ClipFilter filter;
  final WhisperThemeExtension theme;
  final int total;
  final int recorded;
  final int imported;
  final ValueChanged<_ClipFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          _FilterChip(
            label: l10n.filterLabel(l10n.all, total),
            selected: filter == _ClipFilter.all,
            theme: theme,
            onTap: () => onFilter(_ClipFilter.all),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: l10n.filterLabel(l10n.recorded, recorded),
            selected: filter == _ClipFilter.recorded,
            theme: theme,
            onTap: () => onFilter(_ClipFilter.recorded),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: l10n.filterLabel(l10n.imported, imported),
            selected: filter == _ClipFilter.imported,
            theme: theme,
            onTap: () => onFilter(_ClipFilter.imported),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.theme,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final WhisperThemeExtension theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? theme.actionFill : Colors.transparent,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? theme.actionFill : theme.glassBorder,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? theme.onActionFill : theme.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyClipsState extends StatelessWidget {
  const _EmptyClipsState({
    required this.theme,
    required this.onRecord,
    required this.onImport,
  });

  final WhisperThemeExtension theme;
  final VoidCallback onRecord;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: AppColors.neonGradient,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.25),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.neon.withValues(alpha: 0.55),
                  blurRadius: 34,
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: AppColors.neonCyan.withValues(alpha: 0.35),
                  blurRadius: 16,
                ),
              ],
            ),
            child: const Icon(AppIcons.mic, size: 38, color: Colors.white),
          ),
          const SizedBox(height: 24),
          Text(
            l10n.noClipsYet,
            style: GoogleFonts.fraunces(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: theme.foreground,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.noClipsEmptyHint,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.muted, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 28),
          _ActionToolbar(
            theme: theme,
            onRecord: onRecord,
            onImport: onImport,
          ),
        ],
      ),
    );
  }
}
