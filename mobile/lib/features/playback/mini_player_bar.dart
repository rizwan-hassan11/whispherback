import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/layout/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../domain/playback/playback_state.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/playback_providers.dart';

/// Compact now-playing bar above the bottom navigation (Spotify-style).
class MiniPlayerBar extends ConsumerWidget {
  const MiniPlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackSnapshotProvider);
    final snapshot = playback.valueOrNull;
    if (snapshot == null ||
        snapshot.state == AppPlaybackState.inactive ||
        snapshot.state == AppPlaybackState.activeIdle ||
        snapshot.playlistName == null ||
        snapshot.modalVisible) {
      return const SizedBox.shrink();
    }

    final coordinator = ref.read(playbackCoordinatorProvider);
    final audio = ref.read(audioPlaybackServiceProvider);
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isPlaylist = snapshot.playlistId != null;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Material(
          color: isDark
              ? AppColors.card.withValues(alpha: 0.94)
              : Colors.white.withValues(alpha: 0.96),
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
                  isPlaying: snapshot.isPlaying,
                  onTap: coordinator.showModal,
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
                            snapshot.clipTitle ?? snapshot.playlistName ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.fraunces(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isDark ? AppColors.soft : AppColors.ink,
                            ),
                          ),
                          StreamBuilder<Duration?>(
                            stream: audio.positionStream,
                            builder: (context, posSnap) {
                              return StreamBuilder<Duration?>(
                                stream: audio.durationStream,
                                builder: (context, durSnap) {
                                  final pos = posSnap.data ?? Duration.zero;
                                  final dur = durSnap.data ?? Duration.zero;
                                  final text = dur.inMilliseconds > 0
                                      ? '${_fmt(pos)} / ${_fmt(dur)}'
                                      : snapshot.playlistName ?? '';
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
                if (isPlaylist)
                  _MiniIconButton(
                    icon: Icons.skip_previous_rounded,
                    semanticLabel: l10n.previousTrack,
                    color: isDark
                        ? AppColors.soft
                        : AppColors.ink.withValues(alpha: 0.72),
                    onPressed: coordinator.skipPrevious,
                  ),
                _MiniPlayPauseButton(
                  isPlaying: snapshot.isPlaying,
                  onTap: () {
                    if (snapshot.isPlaying) {
                      coordinator.pause();
                    } else {
                      coordinator.resume();
                    }
                  },
                ),
                if (isPlaylist)
                  _MiniIconButton(
                    icon: Icons.skip_next_rounded,
                    semanticLabel: l10n.nextTrack,
                    color: isDark
                        ? AppColors.soft
                        : AppColors.ink.withValues(alpha: 0.72),
                    onPressed: coordinator.skipNext,
                  ),
                _MiniIconButton(
                  icon: AppIcons.close,
                  semanticLabel: l10n.stopPlayback,
                  color: isDark
                      ? AppColors.muted
                      : AppColors.ink.withValues(alpha: 0.55),
                  onPressed: coordinator.stop,
                ),
              ],
            ),
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
      padding: const EdgeInsets.symmetric(horizontal: 4),
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
              width: 40,
              height: 40,
              child: Icon(
                isPlaying ? AppIcons.pause : AppIcons.play,
                color: AppColors.neonBright,
                size: 22,
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
            width: 36,
            height: 36,
            child: Icon(icon, size: 20, color: color),
          ),
        ),
      ),
    );
  }
}

class _MiniCover extends StatelessWidget {
  const _MiniCover({required this.isPlaying, required this.onTap});

  final bool isPlaying;
  final VoidCallback onTap;

  static const _bars = [10.0, 18.0, 24.0, 14.0, 20.0];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
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
        ),
      ),
    );
  }
}
