import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/layout/responsive.dart';
import '../../../core/layout/shell_messenger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/audio_clip.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/duration_format.dart';
import '../../../providers/playback_providers.dart';
import '../../../providers/repository_providers.dart';

/// Professional clip-picker sheet — select which clips to add to a playlist.
Future<void> showAddClipsSheet(
  BuildContext context,
  WidgetRef ref, {
  required String playlistId,
  required String playlistName,
  VoidCallback? onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _AddClipsSheet(
      playlistId: playlistId,
      playlistName: playlistName,
      onChanged: onChanged,
    ),
  );
}

class _AddClipsSheet extends ConsumerStatefulWidget {
  const _AddClipsSheet({
    required this.playlistId,
    required this.playlistName,
    this.onChanged,
  });

  final String playlistId;
  final String playlistName;
  final VoidCallback? onChanged;

  @override
  ConsumerState<_AddClipsSheet> createState() => _AddClipsSheetState();
}

class _AddClipsSheetState extends ConsumerState<_AddClipsSheet> {
  final Set<String> _selected = {};
  final Set<String> _alreadyInPlaylist = {};
  bool _loading = true;
  bool _saving = false;
  List<AudioClip> _allClips = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final playlistRepo = ref.read(playlistRepositoryProvider);
    final clipRepo = ref.read(clipRepositoryProvider);
    final inPlaylist = await playlistRepo.getClips(widget.playlistId);
    final all = await clipRepo.getAll();
    if (!mounted) return;
    setState(() {
      _alreadyInPlaylist.addAll(inPlaylist.map((c) => c.id));
      _allClips = all;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final repo = ref.read(playlistRepositoryProvider);
    final toAdd = _selected.toList();
    if (toAdd.isEmpty) {
      if (mounted) Navigator.pop(context);
      return;
    }

    setState(() => _saving = true);
    try {
      for (final clipId in toAdd) {
        await repo.addClip(widget.playlistId, clipId);
      }
      ref.invalidate(playlistsProvider);
      ref.invalidate(clipsProvider);
      widget.onChanged?.call();
      if (mounted) {
        context.showShellSnackBar(
          context.l10n.clipsAddedToPlaylist(toAdd.length, widget.playlistName),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toggle(String clipId) {
    if (_alreadyInPlaylist.contains(clipId)) return;
    setState(() {
      if (_selected.contains(clipId)) {
        _selected.remove(clipId);
      } else {
        _selected.add(clipId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = whisperTheme(context);
    final maxH = MediaQuery.sizeOf(context).height * 0.82;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom +
            ShellMetrics.sheetBottomInset(context),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Material(
          color: theme.background,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.muted.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.addClips,
                              style: GoogleFonts.fraunces(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: theme.foreground,
                              ),
                            ),
                            Text(
                              widget.playlistName,
                              style: TextStyle(color: theme.muted, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(AppIcons.close, color: theme.muted),
                        onPressed: _saving ? null : () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    l10n.selectClipsForPlaylist,
                    style: TextStyle(color: theme.muted, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 12),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  )
                else if (_allClips.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(l10n.noClipsYet, style: TextStyle(color: theme.muted)),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () async {
                            await context.push('/clips/record');
                            await _load();
                          },
                          icon: const Icon(AppIcons.mic),
                          label: Text(l10n.record),
                        ),
                      ],
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      itemCount: _allClips.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final clip = _allClips[i];
                        final inPlaylist = _alreadyInPlaylist.contains(clip.id);
                        final checked = inPlaylist || _selected.contains(clip.id);
                        return Material(
                          color: checked && !inPlaylist
                              ? AppColors.neon.withValues(alpha: 0.08)
                              : theme.glass,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: inPlaylist ? null : () => _toggle(clip.id),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    checked
                                        ? AppIcons.checkCircle
                                        : AppIcons.circleOutline,
                                    color: inPlaylist
                                        ? theme.muted
                                        : (checked
                                            ? AppColors.neonBright
                                            : theme.muted),
                                    size: 22,
                                  ),
                                  const SizedBox(width: 12),
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      color: AppColors.neon.withValues(alpha: 0.15),
                                    ),
                                    child:                                     Icon(
                                      clip.source == ClipSource.recorded
                                          ? AppIcons.mic
                                          : AppIcons.audioFile,
                                      size: 18,
                                      color: AppColors.neonBright,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          clip.title,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: theme.foreground,
                                          ),
                                        ),
                                        Text(
                                          formatPlaylistDurationLocalized(
                                            context,
                                            clip.durationMs,
                                          ),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: theme.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (inPlaylist)
                                    Text(
                                      l10n.added,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: theme.muted,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: AppColors.neonGradient,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.neon.withValues(alpha: 0.35),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: FilledButton(
                      onPressed: _saving || _selected.isEmpty ? null : _save,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _selected.isEmpty
                                  ? l10n.selectClipsHint
                                  : l10n.addClipsCount(_selected.length),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                    ),
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
