import 'dart:math' as math;
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

class PlaybackModal extends ConsumerWidget {
  const PlaybackModal({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackSnapshotProvider);
    final snapshot = playback.valueOrNull;
    if (snapshot == null ||
        snapshot.state == AppPlaybackState.inactive ||
        snapshot.state == AppPlaybackState.activeIdle ||
        snapshot.playlistName == null ||
        !snapshot.modalVisible) {
      return const SizedBox.shrink();
    }

    final coordinator = ref.read(playbackCoordinatorProvider);
    final audio = ref.read(audioPlaybackServiceProvider);
    final l10n = context.l10n;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          0,
          0,
          0,
          ShellMetrics.playbackModalBottomInset(context),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFA081634), Color(0xFA020611)],
                ),
                border: Border(top: BorderSide(color: AppColors.glassBorder)),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: -80,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        width: 280,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.07),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const _NowPlayingChip(),
                        const SizedBox(height: 18),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _CoverArt(isPlaying: snapshot.isPlaying),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    snapshot.playlistName ?? '',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.1,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    snapshot.clipTitle ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.fraunces(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      height: 1.15,
                                      color: AppColors.soft,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Semantics(
                              label: l10n.minimizePlayer,
                              button: true,
                              child: Material(
                                color: AppColors.glass,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: const BorderSide(color: AppColors.glassBorder),
                                ),
                                child: InkWell(
                                  onTap: coordinator.dismissModal,
                                  borderRadius: BorderRadius.circular(12),
                                  child: const SizedBox(
                                    width: 36,
                                    height: 36,
                                    child: Icon(
                                      AppIcons.chevronDown,
                                      size: 22,
                                      color: AppColors.muted,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        StreamBuilder<Duration?>(
                          stream: audio.positionStream,
                          builder: (context, posSnap) {
                            return StreamBuilder<Duration?>(
                              stream: audio.durationStream,
                              builder: (context, durSnap) {
                                final pos = posSnap.data ?? Duration.zero;
                                final dur = durSnap.data ?? Duration.zero;
                                final progress = dur.inMilliseconds > 0
                                    ? pos.inMilliseconds / dur.inMilliseconds
                                    : 0.0;
                                final clamped = progress.clamp(0.0, 1.0);
                                final remaining = dur - pos;

                                return Column(
                                  children: [
                                    _WaveformProgress(progress: clamped),
                                    const SizedBox(height: 10),
                                    LayoutBuilder(
                                      builder: (context, constraints) {
                                        final thumbLeft =
                                            (clamped * constraints.maxWidth - 7)
                                                .clamp(0.0, constraints.maxWidth - 14);
                                        return SizedBox(
                                          height: 14,
                                          child: Stack(
                                            clipBehavior: Clip.none,
                                            alignment: Alignment.centerLeft,
                                            children: [
                                              ClipRRect(
                                                borderRadius: BorderRadius.circular(4),
                                                child: SizedBox(
                                                  height: 4,
                                                  width: constraints.maxWidth,
                                                  child: Stack(
                                                    children: [
                                                      Container(color: AppColors.glassBorder),
                                                      FractionallySizedBox(
                                                        widthFactor: clamped,
                                                        child: Container(color: AppColors.brand),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              Positioned(
                                                left: thumbLeft,
                                                top: 0,
                                                child: Container(
                                                  width: 14,
                                                  height: 14,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: AppColors.brand,
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: AppColors.brand
                                                            .withValues(alpha: 0.12),
                                                        blurRadius: 0,
                                                        spreadRadius: 4,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _format(pos),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.soft,
                                            fontFeatures: [FontFeature.tabularFigures()],
                                          ),
                                        ),
                                        Text(
                                          remaining.isNegative
                                              ? _format(Duration.zero)
                                              : '−${_format(remaining)}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.muted,
                                            fontFeatures: [FontFeature.tabularFigures()],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (snapshot.playlistId != null)
                              _CtrlButton(
                                semanticLabel: l10n.toggleShuffle,
                                icon: AppIcons.shuffle,
                                highlighted: snapshot.shuffleEnabled,
                                onPressed: () => coordinator.toggleShuffle(
                                  snapshot.playlistId!,
                                  !snapshot.shuffleEnabled,
                                ),
                              ),
                            if (snapshot.playlistId != null) const SizedBox(width: 18),
                            _CtrlButton(
                              semanticLabel: snapshot.isPlaying ? l10n.pause : l10n.play,
                              icon: snapshot.isPlaying
                                  ? AppIcons.pause
                                  : AppIcons.play,
                              filled: true,
                              onPressed: () {
                                if (snapshot.isPlaying) {
                                  coordinator.pause();
                                } else {
                                  coordinator.resume();
                                }
                              },
                            ),
                            const SizedBox(width: 18),
                            _CtrlButton(
                              semanticLabel: l10n.stopPlayback,
                              icon: AppIcons.stop,
                              onPressed: coordinator.stop,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _NowPlayingChip extends StatelessWidget {
  const _NowPlayingChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
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
            context.l10n.nowPlaying,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverArt extends StatelessWidget {
  const _CoverArt({required this.isPlaying});

  final bool isPlaying;

  static const _barHeights = [12.0, 22.0, 30.0, 18.0, 26.0, 14.0];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.card, AppColors.ink],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final h in _barHeights)
            AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut,
              width: 3,
              height: isPlaying ? h : h * 0.55,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}

class _WaveformProgress extends StatelessWidget {
  const _WaveformProgress({required this.progress});

  final double progress;

  static const _count = 52;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(_count, (i) {
          final h = 5 +
              (24 * (0.5 + 0.5 * _wave(i * 0.38 + 0.4)).abs()) +
              (4 * _wave(i * 0.17));
          final clampedH = h.clamp(4.0, 36.0);
          final played = i / _count < progress;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  height: clampedH,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: played
                        ? const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [AppColors.brand, Color(0x8CF1F5F9)],
                          )
                        : null,
                    color: played ? null : AppColors.muted.withValues(alpha: 0.28),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  double _wave(double x) => math.sin(x * 3.7);
}

class _CtrlButton extends StatelessWidget {
  const _CtrlButton({
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.filled = false,
    this.highlighted = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final bool filled;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return Semantics(
        label: semanticLabel,
        button: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: Ink(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.brand,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brandGlow,
                    blurRadius: 28,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(icon, color: AppColors.deep, size: 30),
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: semanticLabel,
      button: true,
      child: Material(
        color: highlighted
            ? Colors.white.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.06),
        shape: CircleBorder(
          side: BorderSide(
            color: highlighted
                ? Colors.white.withValues(alpha: 0.28)
                : AppColors.glassBorder,
          ),
        ),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(
              icon,
              color: highlighted ? AppColors.brand : AppColors.soft,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}
