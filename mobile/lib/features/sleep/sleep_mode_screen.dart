import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/playback_providers.dart';
import '../../providers/repository_providers.dart';

class SleepModeScreen extends ConsumerStatefulWidget {
  const SleepModeScreen({super.key});

  @override
  ConsumerState<SleepModeScreen> createState() => _SleepModeScreenState();
}

class _SleepModeScreenState extends ConsumerState<SleepModeScreen> {
  int _durationMinutes = 60;

  static const _presets = [30, 60, 120, 480];

  DateTime get _wakeTime =>
      DateTime.now().add(Duration(minutes: _durationMinutes));

  Future<void> _startSleep() async {
    final now = DateTime.now();
    final end = now.add(Duration(minutes: _durationMinutes));
    await ref.read(sleepRepositoryProvider).create(
          startTime: now,
          endTime: end,
        );
    ref.invalidate(activeSleepProvider);
    await ref.read(playbackCoordinatorProvider).refreshModeState();
    if (mounted) {
      final locale = Localizations.localeOf(context).toString();
      final endLabel = DateFormat.jm(locale).format(end);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.sleepModeUntil(endLabel)),
        ),
      );
      context.pop();
    }
  }

  String _presetLabel(BuildContext context, int minutes) {
    return context.l10n.intervalLabel(minutes);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toString();
    final wakeLabel = DateFormat.jm(locale).format(_wakeTime);

    final sleepAsync = ref.watch(activeSleepProvider);
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
        _SleepAmbience(isDark: theme.isDark),
        Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Column(
              children: [
                _SleepTopBar(theme: theme, onBack: () => context.pop()),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                    children: [
                      _SleepHero(theme: theme),
                      const SizedBox(height: 22),
                      sleepAsync.when(
                        data: (window) {
                          if (window != null && window.active) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 22),
                              child: _ActiveSleepBanner(
                                theme: theme,
                                endTime: window.endTime,
                                onEnd: () async {
                                  await ref
                                      .read(sleepRepositoryProvider)
                                      .deactivateAll();
                                  ref.invalidate(activeSleepProvider);
                                  setState(() {});
                                },
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                      _SleepFeatures(theme: theme),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            l10n.duration,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.35,
                              color: theme.muted,
                            ),
                          ),
                          Text(
                            l10n.untilTime(wakeLabel),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: theme.isDark
                                  ? AppColors.brandLight
                                  : AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _DurationGrid(
                        theme: theme,
                        presets: _presets,
                        selected: _durationMinutes,
                        labelFor: (m) => _presetLabel(context, m),
                        onSelect: (m) => setState(() => _durationMinutes = m),
                      ),
                      const SizedBox(height: 28),
                      FilledButton.icon(
                        onPressed: _startSleep,
                        icon: const Icon(AppIcons.moon, size: 18),
                        label: Text(l10n.startSleepMode),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.sleepTapHint,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.muted,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SleepAmbience extends StatelessWidget {
  const _SleepAmbience({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -40,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (isDark ? AppColors.soft : AppColors.ink)
                      .withValues(alpha: isDark ? 0.14 : 0.06),
                ),
              ),
            ),
          ),
          Positioned(
            top: 120,
            right: -30,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.brandLight
                    .withValues(alpha: isDark ? 0.08 : 0.05),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SleepTopBar extends StatelessWidget {
  const _SleepTopBar({required this.theme, required this.onBack});

  final WhisperThemeExtension theme;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: Icon(AppIcons.back, color: theme.foreground),
            style: IconButton.styleFrom(
              backgroundColor: theme.isDark ? theme.glass : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
                side: BorderSide(color: theme.glassBorder),
              ),
            ),
          ),
          Expanded(
            child: Text(
              context.l10n.sleepModeTitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.fraunces(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: theme.foreground,
              ),
            ),
          ),
          const SizedBox(width: 42),
        ],
      ),
    );
  }
}

class _SleepHero extends StatelessWidget {
  const _SleepHero({required this.theme});

  final WhisperThemeExtension theme;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      children: [
        const _MoonVisual(),
        const SizedBox(height: 22),
        Text(
          l10n.nightRoutine,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            color: theme.muted,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.restPeacefully,
          textAlign: TextAlign.center,
          style: GoogleFonts.fraunces(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            height: 1.15,
            letterSpacing: -0.4,
            color: theme.foreground,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          l10n.sleepHeroBody,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: theme.muted,
            fontSize: 14,
            height: 1.6,
          ),
        ),
      ],
    );
  }
}

class _MoonVisual extends StatelessWidget {
  const _MoonVisual();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 148,
      height: 148,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 148,
            height: 148,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.brandLight.withValues(alpha: 0.22),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Container(
            width: 108,
            height: 108,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                center: Alignment(-0.32, -0.28),
                radius: 0.95,
                colors: [
                  Color(0xFFF8FAFC),
                  Color(0xFFCBD5E1),
                  Color(0xFF64748B),
                  Color(0xFF1E293B),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandLight.withValues(alpha: 0.28),
                  blurRadius: 48,
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Stack(
              children: [
                Positioned(
                  top: 28,
                  left: 24,
                  child: _Crater(size: 18, opacity: 1),
                ),
                Positioned(
                  top: 56,
                  left: 52,
                  child: _Crater(size: 12, opacity: 0.7),
                ),
                Positioned(
                  top: 40,
                  right: 22,
                  child: _Crater(size: 10, opacity: 0.55),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Crater extends StatelessWidget {
  const _Crater({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.deep.withValues(alpha: 0.12 * opacity),
      ),
    );
  }
}

class _SleepFeatures extends StatelessWidget {
  const _SleepFeatures({required this.theme});

  final WhisperThemeExtension theme;

  static List<(IconData, String, String)> _items(BuildContext context) {
    final l10n = context.l10n;
    return [
      (AppIcons.volumeOff, l10n.instantPause, l10n.instantPauseDesc),
      (AppIcons.schedule, l10n.schedulesWait, l10n.schedulesWaitDesc),
      (AppIcons.alarmOff, l10n.quietAlarms, l10n.quietAlarmsDesc),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final items = _items(context);
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: theme.isDark ? theme.glass : Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: theme.glassBorder),
        boxShadow: theme.isDark
            ? null
            : [
                BoxShadow(
                  color: AppColors.ink.withValues(alpha: 0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) Divider(height: 1, color: theme.glassBorder),
            _FeatureRow(
              theme: theme,
              icon: items[i].$1,
              title: items[i].$2,
              hint: items[i].$3,
            ),
          ],
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.theme,
    required this.icon,
    required this.title,
    required this.hint,
  });

  final WhisperThemeExtension theme;
  final IconData icon;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.sm),
              color: theme.isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : AppColors.ink.withValues(alpha: 0.04),
              border: Border.all(
                color: theme.isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : AppColors.ink.withValues(alpha: 0.08),
              ),
            ),
            child: Icon(icon, size: 18, color: theme.foreground),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: theme.foreground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style:
                      TextStyle(fontSize: 12, color: theme.muted, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DurationGrid extends StatelessWidget {
  const _DurationGrid({
    required this.theme,
    required this.presets,
    required this.selected,
    required this.labelFor,
    required this.onSelect,
  });

  final WhisperThemeExtension theme;
  final List<int> presets;
  final int selected;
  final String Function(int) labelFor;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 2.4,
      children: presets.map((m) {
        final isSelected = selected == m;
        return Material(
          color: isSelected
              ? theme.actionFill
              : (theme.isDark ? theme.glass : Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.sm),
            side: BorderSide(
              color: isSelected ? theme.actionFill : theme.glassBorder,
            ),
          ),
          child: InkWell(
            onTap: () => onSelect(m),
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: Center(
              child: Text(
                labelFor(m),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? theme.onActionFill : theme.muted,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ActiveSleepBanner extends StatelessWidget {
  const _ActiveSleepBanner({
    required this.theme,
    required this.endTime,
    required this.onEnd,
  });

  final WhisperThemeExtension theme;
  final DateTime endTime;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toString();
    final endLabel = DateFormat.jm(locale).format(endTime);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        gradient: LinearGradient(
          colors: [
            AppColors.brand.withValues(alpha: 0.22),
            theme.isDark ? theme.glass : Colors.white,
          ],
        ),
        border: Border.all(color: AppColors.brandLight.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.sm),
              color: AppColors.neon.withValues(alpha: 0.16),
              border: Border.all(color: AppColors.neon.withValues(alpha: 0.4)),
            ),
            child: const Icon(AppIcons.bedtime,
                color: AppColors.neonBright, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.sleepActive,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: theme.foreground,
                  ),
                ),
                Text(
                  l10n.untilTime(endLabel),
                  style: TextStyle(fontSize: 12, color: theme.muted),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onEnd, child: Text(l10n.endNow)),
        ],
      ),
    );
  }
}
