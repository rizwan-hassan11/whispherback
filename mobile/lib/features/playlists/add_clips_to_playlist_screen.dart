import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/layout/shell_messenger.dart';
import '../../core/navigation/route_back.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/premium_screen_background.dart';
import '../../domain/entities/audio_clip.dart';
import '../../l10n/app_localizations.dart';
import '../../l10n/duration_format.dart';
import '../../providers/playback_providers.dart';
import '../../providers/repository_providers.dart';

/// Pick clips from the library and attach them to a playlist.
class AddClipsToPlaylistScreen extends ConsumerStatefulWidget {
  const AddClipsToPlaylistScreen({super.key, required this.playlistId});

  final String playlistId;

  @override
  ConsumerState<AddClipsToPlaylistScreen> createState() =>
      _AddClipsToPlaylistScreenState();
}

class _AddClipsToPlaylistScreenState
    extends ConsumerState<AddClipsToPlaylistScreen> {
  final Set<String> _selected = {};
  final Set<String> _alreadyInPlaylist = {};
  String _playlistName = '';
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
    final playlist = await playlistRepo.getById(widget.playlistId);
    final inPlaylist = await playlistRepo.getClips(widget.playlistId);
    final all = await clipRepo.getAll();
    if (!mounted) return;
    setState(() {
      _playlistName = playlist?.name ?? context.l10n.playlist;
      _alreadyInPlaylist.addAll(inPlaylist.map((c) => c.id));
      _selected.addAll(_alreadyInPlaylist);
      _allClips = all;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final repo = ref.read(playlistRepositoryProvider);
    final toAdd =
        _selected.where((id) => !_alreadyInPlaylist.contains(id)).toList();
    if (toAdd.isEmpty) {
      if (mounted) context.pop();
      return;
    }

    setState(() => _saving = true);
    try {
      for (final clipId in toAdd) {
        await repo.addClip(widget.playlistId, clipId);
      }
      ref.invalidate(playlistsProvider);
      ref.invalidate(clipsProvider);
      if (mounted) {
        final message =
            context.l10n.clipsAddedToPlaylist(toAdd.length, _playlistName);
        context.pop();
        context.showShellSnackBar(message, icon: AppIcons.checkCircle);
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
    final newCount =
        _selected.where((id) => !_alreadyInPlaylist.contains(id)).length;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final fallback = '/playlists/${widget.playlistId}';
    return RouteBackScope(
      fallbackLocation: fallback,
      child: PremiumScreenBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(
            l10n.addClips,
            style: GoogleFonts.fraunces(fontWeight: FontWeight.w700),
          ),
          leading: IconButton(
            icon: Icon(AppIcons.back, color: theme.foreground),
            onPressed: _saving ? null : () => popOrGo(context, fallback),
          ),
        ),
        body: _allClips.isEmpty
            ? _EmptyState(
                theme: theme,
                onRecord: () async {
                  await context.push('/clips/record');
                  await _load();
                },
                onImport: () async {
                  await context.push('/clips/import');
                  await _load();
                },
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _playlistName,
                          style: GoogleFonts.fraunces(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: theme.foreground,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.selectClipsForPlaylist,
                          style: TextStyle(color: theme.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      itemCount: _allClips.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final clip = _allClips[i];
                        final inPlaylist = _alreadyInPlaylist.contains(clip.id);
                        final checked = _selected.contains(clip.id);
                        return Material(
                          color: theme.glass,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
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
                                            ? AppColors.success
                                            : theme.muted),
                                    size: 22,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: FilledButton(
                      onPressed: _saving || newCount == 0 ? null : _save,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
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
                              newCount == 0
                                  ? l10n.done
                                  : l10n.addClipsCount(newCount),
                            ),
                    ),
                  ),
                ],
              ),
      ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
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
              l10n.recordOrImportFirst,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.muted, height: 1.5),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRecord,
              icon: const Icon(AppIcons.mic),
              label: Text(l10n.record),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onImport,
              icon: const Icon(AppIcons.upload),
              label: Text(l10n.import),
            ),
          ],
        ),
      ),
    );
  }
}
