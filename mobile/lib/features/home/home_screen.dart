import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/layout/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/playback/playback_state.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/playback_providers.dart';
import '../../core/widgets/depth_surface.dart';
import '../widgets/active_toggle.dart';
import 'widgets/home_ambience.dart';

enum _GreetingPeriod { morning, afternoon, evening }

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playbackSnapshotProvider);
    final snapshot = playback.valueOrNull ??
        const PlaybackSnapshot(state: AppPlaybackState.inactive);
    final isActive = snapshot.state != AppPlaybackState.inactive;

    final playlistsAsync = ref.watch(playlistsProvider);
    final clipsAsync = ref.watch(clipsProvider);
    final schedulesAsync = ref.watch(schedulesProvider);
    final theme = whisperTheme(context);
    final greetingPeriod = _greetingPeriod();

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: theme.isDark
                  ? [
                      AppColors.deep2,
                      AppColors.deep,
                      AppColors.ink,
                    ]
                  : [
                      AppColors.lightBg,
                      AppColors.lightBg2,
                      AppColors.lightBg3,
                    ],
            ),
          ),
        ),
        HomeAmbience(isActive: isActive),
        Stack(
          children: [
            DepthOrb(
              size: 100,
              color: theme.isDark ? AppColors.brandLight : AppColors.ink,
              top: 48,
              right: -20,
            ),
            DepthOrb(
              size: 72,
              color: theme.isDark ? AppColors.gold : AppColors.lightMuted,
              top: 120,
              left: -24,
            ),
          ],
        ),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final r = context.responsive;
              final scrollable = r.isCompactHeight || constraints.maxHeight < 680;

              Widget buildContent({required bool useSpacers}) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    _HomeHeader(
                      theme: theme,
                      onSleep: () => context.push('/sleep'),
                    ),
                    SizedBox(height: r.isFlipCover ? 12 : 20),
                    _GreetingCard(
                      theme: theme,
                      playlistCount: playlistsAsync.valueOrNull?.length ?? 0,
                      greetingPeriod: greetingPeriod,
                    ),
                    if (useSpacers) const Spacer(flex: 2) else SizedBox(height: r.isFlipCover ? 16 : 24),
                    Center(
                      child: DepthScene(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            HomeWaveBars(active: isActive),
                            SizedBox(height: r.isFlipCover ? 10 : 16),
                            ActiveToggle(
                              isActive: isActive,
                              onToggle: () =>
                                  ref.read(playbackCoordinatorProvider).toggleActive(),
                            ),
                            const SizedBox(height: 10),
                            const DepthPedestal(),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: r.isFlipCover ? 6 : 8),
                    Center(child: _StatusPill(isActive: isActive, theme: theme)),
                    SizedBox(height: r.isFlipCover ? 14 : 20),
                    _QuickStats(
                      theme: theme,
                      playlistCount: playlistsAsync.valueOrNull?.length ?? 0,
                      clipCount: clipsAsync.valueOrNull?.length ?? 0,
                      scheduleCount: schedulesAsync.valueOrNull?.length ?? 0,
                    ),
                    if (isActive) ...[
                      const SizedBox(height: 14),
                      _NextWhisperCard(theme: theme),
                    ],
                    if (useSpacers) const Spacer(flex: 3) else const SizedBox(height: 20),
                    if (snapshot.state == AppPlaybackState.sleepPaused)
                      _ModeChip(
                        icon: AppIcons.bedtime,
                        label: context.l10n.sleepModeActive,
                        color: AppColors.brandLight,
                        theme: theme,
                      ),
                    if (snapshot.state == AppPlaybackState.prayerPaused)
                      _ModeChip(
                        icon: AppIcons.prayer,
                        label: context.l10n.prayerPauseActive,
                        color: AppColors.gold,
                        theme: theme,
                      ),
                    SizedBox(height: ShellMetrics.scrollBottomInset(context, extra: 4)),
                  ],
                );
              }

              return Padding(
                padding: EdgeInsets.symmetric(horizontal: r.horizontalGutter),
                child: scrollable
                    ? SingleChildScrollView(
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: constraints.maxHeight),
                          child: buildContent(useSpacers: false),
                        ),
                      )
                    : buildContent(useSpacers: true),
              );
            },
          ),
        ),
      ],
    );
  }

  _GreetingPeriod _greetingPeriod() {
    final hour = DateTime.now().hour;
    if (hour < 12) return _GreetingPeriod.morning;
    if (hour < 17) return _GreetingPeriod.afternoon;
    return _GreetingPeriod.evening;
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.theme, required this.onSleep});

  final WhisperThemeExtension theme;
  final VoidCallback onSleep;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final locale = Localizations.localeOf(context).toString();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WhisperBack',
                style: GoogleFonts.fraunces(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.4,
                  color: theme.foreground,
                ),
              ),
              Text(
                DateFormat('EEEE, MMM d', locale).format(now),
                style: TextStyle(fontSize: 12, color: theme.muted),
              ),
            ],
          ),
        ),
        Semantics(
          label: context.l10n.sleepMode,
          button: true,
          child: _ZzzButton(onPressed: onSleep, theme: theme),
        ),
      ],
    );
  }
}

class _GreetingCard extends StatelessWidget {
  const _GreetingCard({
    required this.theme,
    required this.playlistCount,
    required this.greetingPeriod,
  });

  final WhisperThemeExtension theme;
  final int playlistCount;
  final _GreetingPeriod greetingPeriod;

  IconData get _icon => switch (greetingPeriod) {
        _GreetingPeriod.morning => AppIcons.sun,
        _GreetingPeriod.afternoon => AppIcons.cloudSun,
        _ => AppIcons.moon,
      };

  String _greetingText(AppLocalizations l10n) => switch (greetingPeriod) {
        _GreetingPeriod.morning => l10n.goodMorning,
        _GreetingPeriod.afternoon => l10n.goodAfternoon,
        _ => l10n.goodEvening,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DepthSurface(
      radius: AppRadii.sm,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      tiltX: 0.025,
      lift: 6,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: theme.isDark
                    ? [AppColors.cardElevated, AppColors.ink, const Color(0xFF040B1E)]
                    : [AppColors.brand, AppColors.ink],
                stops: theme.isDark ? const [0, 0.6, 1] : const [0, 1],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: theme.isDark
                    ? const Color(0x28FFFFFF)
                    : AppColors.lightGlassBorder,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: theme.isDark ? 0.35 : 0.14),
                  offset: const Offset(0, 4),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Icon(
              _icon,
              color: theme.isDark ? AppColors.brandLight : AppColors.lightBg,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greetingText(l10n),
                  style: GoogleFonts.fraunces(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: theme.foreground,
                  ),
                ),
                Text(
                  playlistCount > 0
                      ? l10n.playlistsReady(playlistCount)
                      : l10n.createPlaylistToStart,
                  style: TextStyle(fontSize: 12, color: theme.muted, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NextWhisperCard extends StatelessWidget {
  const _NextWhisperCard({required this.theme});

  final WhisperThemeExtension theme;

  @override
  Widget build(BuildContext context) {
    return DepthSurface(
      radius: AppRadii.sm,
      padding: const EdgeInsets.all(14),
      tiltX: 0.02,
      lift: 4,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.glass,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(AppIcons.schedule, color: theme.foreground, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.nextWhisper,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Text(
                  context.l10n.nextWhisperSample,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: theme.foreground,
                  ),
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

class _ZzzButton extends StatelessWidget {
  const _ZzzButton({required this.onPressed, required this.theme});

  final VoidCallback onPressed;
  final WhisperThemeExtension theme;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.glass,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.glassBorder),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Text(
              'Zzz',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: theme.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.isActive, required this.theme});

  final bool isActive;
  final WhisperThemeExtension theme;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.success.withValues(alpha: 0.12)
            : theme.glass,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: isActive
              ? AppColors.success.withValues(alpha: 0.35)
              : theme.glassBorder,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: AppColors.success.withValues(alpha: 0.15),
                  blurRadius: 20,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulsingDot(active: isActive),
          const SizedBox(width: 10),
          Text(
            isActive ? l10n.activeWhispersPlaying : l10n.tapPowerToBegin,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isActive ? AppColors.success : theme.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.active});

  final bool active;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.active ? AppColors.success : AppColors.muted2,
            boxShadow: widget.active
                ? [
                    BoxShadow(
                      color: AppColors.success.withValues(
                        alpha: 0.4 + _c.value * 0.4,
                      ),
                      blurRadius: 6 + _c.value * 6,
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }
}

class _QuickStats extends StatelessWidget {
  const _QuickStats({
    required this.theme,
    required this.playlistCount,
    required this.clipCount,
    required this.scheduleCount,
  });

  final WhisperThemeExtension theme;
  final int playlistCount;
  final int clipCount;
  final int scheduleCount;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            theme: theme,
            icon: AppIcons.playlists,
            value: '$playlistCount',
            label: l10n.statPlaylists,
            accent: AppColors.brandLight,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            theme: theme,
            icon: AppIcons.schedule,
            value: '$scheduleCount',
            label: l10n.statScheduled,
            accent: AppColors.gold,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            theme: theme,
            icon: AppIcons.mic,
            value: '$clipCount',
            label: l10n.statClips,
            accent: AppColors.success,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.theme,
    required this.icon,
    required this.value,
    required this.label,
    required this.accent,
  });

  final WhisperThemeExtension theme;
  final IconData icon;
  final String value;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DepthSurface(
      radius: AppRadii.sm,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      tiltX: 0.03,
      lift: 5,
      child: Column(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: AppDepth.iconTile(isDark: theme.isDark, radius: 8),
            child: Icon(icon, size: 16, color: accent),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: theme.foreground,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 10, color: theme.muted, letterSpacing: 0.2),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.theme,
  });

  final IconData icon;
  final String label;
  final Color color;
  final WhisperThemeExtension theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: theme.foreground)),
        ],
      ),
    );
  }
}
