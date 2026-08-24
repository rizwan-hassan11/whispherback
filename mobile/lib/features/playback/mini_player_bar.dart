import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/layout/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/playlist_cover.dart';
import '../../core/ux/tap_feedback.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/playback/playback_state.dart';
import '../../domain/playback/playlist_playback_badge.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/playback_providers.dart';
import '../../services/audio/audio_services.dart';
import '../../services/playback/playback_coordinator.dart';
import '../../services/scheduler/native_alarms_bridge.dart';

/// True when progress must come from native MediaPlayer (scheduled fire),
/// not the Dart silence keep-alive's 10-second duration stream.
bool _useNativeProgress(PlaybackSnapshot snapshot, AudioPlaybackService audio) {
  return (snapshot.state == AppPlaybackState.scheduledPlaying ||
          NativeAlarmsBridge.instance.lastSnapshot.isNativeActive) &&
      audio.currentPath == null;
}

/// Prefer the known clip length from [PlaybackSnapshot.durationMs] so a brief
/// leak of the 10-second silence keep-alive never flashes in the mini-player
/// during next/previous source swaps.
Duration _resolveDisplayDuration({
  required PlaybackSnapshot snapshot,
  required Duration? streamDuration,
  NativePlaybackSnapshot? native,
}) {
  final knownMs = snapshot.durationMs > 0
      ? snapshot.durationMs
      : (native != null && native.durationMs > 0 ? native.durationMs : 0);
  final streamMs = streamDuration?.inMilliseconds ?? 0;
  // Silence keep-alive WAV is ~10s — reject it when we know the real clip.
  final looksLikeSilence = streamMs >= 9500 && streamMs <= 10500;
  if (knownMs > 0 && (streamMs <= 0 || looksLikeSilence)) {
    return Duration(milliseconds: knownMs);
  }
  if (streamMs > 0) return Duration(milliseconds: streamMs);
  if (knownMs > 0) return Duration(milliseconds: knownMs);
  return Duration.zero;
}

/// Fires [body] without awaiting; routes any thrown future error to a
/// logged no-op instead of letting it propagate as an unhandled
/// future error (which the OS surfaces as "app crashed").
void _safeCall(Future<void> Function() body, String tag) {
  tapHaptic();
  unawaited(() async {
    try {
      await body();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('mini_player $tag failed (handled): $e\n$st');
      }
    }
  }());
}

/// Compact now-playing bar above the bottom navigation (Spotify-style).
///
/// Round 51: title + play/pause follow the same live MediaSession streams
/// as the system notification when Dart owns audio. Snapshot alone drifted
/// (pause icon stuck, stale clip name) while the notification stayed correct.
class MiniPlayerBar extends ConsumerWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackSnapshotProvider);
    final snapshot = playback.valueOrNull;
    final coordinator = ref.read(playbackCoordinatorProvider);
    final audio = ref.read(audioPlaybackServiceProvider);
    final nativeAsync = ref.watch(nativePlaybackProvider);
    final native =
        nativeAsync.valueOrNull ?? NativeAlarmsBridge.instance.lastSnapshot;

    ref.listen<AsyncValue<NativePlaybackSnapshot>>(nativePlaybackProvider,
        (prev, next) {
      final n = next.valueOrNull;
      if (n == null) return;
      coordinator.applyNativePlaybackSnapshot(n);
    });

    if (snapshot == null || snapshot.modalVisible) {
      return const SizedBox.shrink();
    }
    final nativeLive = native.isNativeActive;

    return StreamBuilder<MediaItem?>(
      stream: audio.mediaItemStream,
      initialData: audio.mediaItem,
      builder: (context, mediaSnap) {
        return StreamBuilder<bool>(
          stream: audio.playbackStateStream.map((s) => s.playing).distinct(),
          initialData: audio.mediaSessionPlaying,
          builder: (context, playingSnap) {
            final mediaItem = mediaSnap.data;
            // Keep the bar mounted for the whole session — including mid skip,
            // MediaSession gaps, and paused clips (QA: Spotify bar "hides").
            final dartClipActive = coordinator.skipTransportActive ||
                audio.currentPath != null ||
                audio.isPlayingClip ||
                mediaItem != null ||
                snapshot.isPlaying ||
                snapshot.clipTitle != null;
            final hasMediaSessionClip =
                audio.isPlayingClip && mediaItem != null;
            if (!snapshot.showsMiniPlayer(
              nativeActive: nativeLive,
              dartClipActive: dartClipActive,
              hasMediaSessionClip: hasMediaSessionClip,
            )) {
              return const SizedBox.shrink();
            }
            final dartOwns =
                (audio.currentPath != null ||
                        audio.isPlayingClip ||
                        coordinator.skipTransportActive) &&
                    !nativeLive;
            return _MiniPlayerBody(
              snapshot: snapshot,
              native: native,
              nativeLive: nativeLive,
              dartOwns: dartOwns,
              mediaItem: mediaItem,
              mediaSessionPlaying: playingSnap.data ?? false,
              coordinator: coordinator,
              audio: audio,
              playlistsAsync: ref.watch(playlistsProvider),
            );
          },
        );
      },
    );
  }
}

class _MiniPlayerBody extends StatelessWidget {
  const _MiniPlayerBody({
    required this.snapshot,
    required this.native,
    required this.nativeLive,
    required this.dartOwns,
    required this.mediaItem,
    required this.mediaSessionPlaying,
    required this.coordinator,
    required this.audio,
    required this.playlistsAsync,
  });

  final PlaybackSnapshot snapshot;
  final NativePlaybackSnapshot native;
  final bool nativeLive;
  final bool dartOwns;
  final MediaItem? mediaItem;
  final bool mediaSessionPlaying;
  final PlaybackCoordinator coordinator;
  final AudioPlaybackService audio;
  final AsyncValue<List<Playlist>> playlistsAsync;

  @override
  Widget build(BuildContext context) {
    final nativeTitle =
        (native.clipTitle != null && native.clipTitle!.trim().isNotEmpty)
            ? native.clipTitle!.trim()
            : null;
    final nativeSubtitle =
        (native.playlistName != null && native.playlistName!.trim().isNotEmpty)
            ? native.playlistName!.trim()
            : null;
    final snapTitle = snapshot.clipTitle?.trim();
    final snapSubtitle = snapshot.playlistName?.trim();
    final mediaTitle = mediaItem?.title.trim();
    final mediaSubtitle = mediaItem?.album?.trim() ?? mediaItem?.artist?.trim();

    // While a skip is in flight, prefer the coordinator snapshot title so the
    // bar updates on the first tap. Once bound, MediaItem wins.
    final skipPending = coordinator.skipTransportActive;
    final title = dartOwns
        ? (skipPending && snapTitle?.isNotEmpty == true
            ? snapTitle
            : (mediaTitle?.isNotEmpty == true ? mediaTitle : snapTitle))
        : (nativeTitle ??
            (mediaTitle?.isNotEmpty == true ? mediaTitle : snapTitle));
    final subtitle = dartOwns
        ? (snapSubtitle?.isNotEmpty == true
            ? snapSubtitle
            : (mediaSubtitle?.isNotEmpty == true
                ? mediaSubtitle
                : nativeSubtitle))
        : (nativeSubtitle ?? snapSubtitle ?? mediaSubtitle);

    final displayTitle = (title != null && title.isNotEmpty)
        ? title
        : (subtitle != null && subtitle.isNotEmpty ? subtitle : 'Now playing');
    final displaySubtitle =
        (subtitle != null && subtitle.isNotEmpty) ? subtitle : 'WhisperBack';

    // During skip keep showing "playing" so the control does not flicker.
    final displayPlaying = dartOwns
        ? (skipPending ? true : mediaSessionPlaying)
        : (nativeLive ? native.isPlaying : snapshot.isPlaying);

    final progressKey = ValueKey<String>(
      'mini-${mediaItem?.id ?? displayTitle}-${snapshot.durationMs}-'
      '${dartOwns ? 'd' : 'n'}',
    );
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final canSkip = coordinator.canSkipClips;
    final playlistId = snapshot.playlistId;
    PlaylistCoverMeta? coverMeta;
    if (playlistId != null) {
      final list = playlistsAsync.valueOrNull;
      if (list != null) {
        final idx = list.indexWhere((p) => p.id == playlistId);
        if (idx >= 0) {
          coverMeta = PlaylistCoverMeta(
            paletteIndex: idx,
            hasSchedule: list[idx].hasSchedule,
          );
        }
      }
    }
    List<Color>? coverColors;
    var hasSchedule = false;
    if (coverMeta != null) {
      coverColors = PlaylistCoverPalette.colorsForIndex(
        coverMeta.paletteIndex,
        isDark: isDark,
      );
      hasSchedule = coverMeta.hasSchedule;
    }

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Material(
        // Fully opaque — translucent blur made the bar look "hidden" behind
        // the glass nav scrim (QA Round 59 visibility).
        color: isDark ? AppColors.card : Colors.white,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        child: Container(
            height: ShellMetrics.miniPlayerHeight,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? AppColors.glassBorder
                      : AppColors.ink.withValues(alpha: 0.08),
                ),
              ),
            ),
            child: Row(
              children: [
                _MiniCover(
                  isPlaying: displayPlaying,
                  onTap: coordinator.showModal,
                  colors: coverColors,
                  hasSchedule: hasSchedule,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: coordinator.showModal,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.fraunces(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isDark ? AppColors.soft : AppColors.ink,
                            ),
                          ),
                          StreamBuilder<Duration?>(
                            key: progressKey,
                            stream: _useNativeProgress(snapshot, audio)
                                ? NativeAlarmsBridge.instance.stateStream
                                    .map<Duration?>((n) =>
                                        Duration(milliseconds: n.positionMs))
                                : audio.positionStream,
                            initialData: _useNativeProgress(snapshot, audio)
                                ? Duration(
                                    milliseconds: NativeAlarmsBridge
                                        .instance.lastSnapshot.positionMs)
                                : audio.player.position,
                            builder: (context, posSnap) {
                              return StreamBuilder<Duration?>(
                                stream: _useNativeProgress(snapshot, audio)
                                    ? NativeAlarmsBridge.instance.stateStream
                                        .map<Duration?>((n) => Duration(
                                            milliseconds: n.durationMs))
                                    : audio.durationStream,
                                initialData: _useNativeProgress(snapshot, audio)
                                    ? Duration(
                                        milliseconds: NativeAlarmsBridge
                                            .instance.lastSnapshot.durationMs)
                                    : audio.player.duration,
                                builder: (context, durSnap) {
                                  final pos = posSnap.data ?? Duration.zero;
                                  final dur = _resolveDisplayDuration(
                                    snapshot: snapshot,
                                    streamDuration: durSnap.data,
                                    native: _useNativeProgress(snapshot, audio)
                                        ? NativeAlarmsBridge
                                            .instance.lastSnapshot
                                        : null,
                                  );
                                  final text = dur.inMilliseconds > 0
                                      ? '${_fmt(pos)} / ${_fmt(dur)}'
                                      : displaySubtitle;
                                  return Text(
                                    text,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? AppColors.muted
                                          : AppColors.ink
                                              .withValues(alpha: 0.55),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (canSkip)
                  _MiniIconButton(
                    icon: Icons.skip_previous_rounded,
                    semanticLabel: l10n.previousTrack,
                    color: isDark
                        ? AppColors.soft
                        : AppColors.ink.withValues(alpha: 0.72),
                    onPressed: () =>
                        _safeCall(coordinator.skipPrevious, 'skipPrevious'),
                  ),
                const SizedBox(width: 6),
                _MiniPlayPauseButton(
                  isPlaying: displayPlaying,
                  onTap: () {
                    if (displayPlaying) {
                      _safeCall(coordinator.pause, 'pause');
                    } else {
                      _safeCall(coordinator.resume, 'resume');
                    }
                  },
                ),
                const SizedBox(width: 6),
                if (canSkip)
                  _MiniIconButton(
                    icon: Icons.skip_next_rounded,
                    semanticLabel: l10n.nextTrack,
                    color: isDark
                        ? AppColors.soft
                        : AppColors.ink.withValues(alpha: 0.72),
                    onPressed: () =>
                        _safeCall(coordinator.skipNext, 'skipNext'),
                  ),
                const SizedBox(width: 4),
                _MiniIconButton(
                  icon: AppIcons.close,
                  semanticLabel: l10n.stopPlayback,
                  color: isDark
                      ? AppColors.muted
                      : AppColors.ink.withValues(alpha: 0.55),
                  onPressed: () =>
                      _safeCall(coordinator.dismissPlayer, 'dismiss'),
                ),
              ],
            ),
          ),
        ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _MiniPlayPauseButton extends StatelessWidget {
  const _MiniPlayPauseButton({required this.isPlaying, required this.onTap});

  final bool isPlaying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Semantics(
        label: isPlaying ? l10n.pause : l10n.play,
        button: true,
        child: Material(
          color: AppColors.neon.withValues(alpha: 0.15),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(
                isPlaying ? AppIcons.pause : AppIcons.play,
                color: AppColors.neonBright,
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniIconButton extends StatelessWidget {
  const _MiniIconButton({
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    required this.color,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, size: 22, color: color),
          ),
        ),
      ),
    );
  }
}

class _MiniCover extends StatelessWidget {
  const _MiniCover({
    required this.isPlaying,
    required this.onTap,
    this.colors,
    this.hasSchedule = false,
  });

  final bool isPlaying;
  final VoidCallback onTap;
  final List<Color>? colors;
  final bool hasSchedule;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: colors != null
            ? PlaylistCoverArt(
                colors: colors!,
                size: 44,
                borderRadius: 10,
                hasSchedule: hasSchedule,
                isPlaying: isPlaying,
              )
            : _GenericMiniCover(isPlaying: isPlaying),
      ),
    );
  }
}

class _GenericMiniCover extends StatelessWidget {
  const _GenericMiniCover({required this.isPlaying});

  final bool isPlaying;

  static const _bars = [10.0, 18.0, 24.0, 14.0, 20.0];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: const LinearGradient(
          colors: [AppColors.neon, AppColors.brand],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.neon.withValues(alpha: 0.35),
            blurRadius: 12,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final h in _bars)
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              width: 2.5,
              height: isPlaying ? h : h * 0.45,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}
