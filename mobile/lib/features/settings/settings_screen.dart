import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/config/feature_flags.dart';
import '../../core/layout/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/premium_screen_background.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/settings_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final showLabels = ref.watch(showLabelsProvider);
    final themeMode = ref.watch(themeModeProvider);
    final defaultAlarm = ref.watch(defaultAlarmProvider);
    final defaultInterval = ref.watch(defaultIntervalProvider);
    final locale = ref.watch(localeProvider);
    final theme = whisperTheme(context);
    final currentLanguage = AppLanguage.fromCode(locale.languageCode);

    return PremiumScreenBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
                20, 8, 20, context.shellScrollPadding.bottom + 12),
            children: [
              Text(
                l10n.settings,
                style: GoogleFonts.fraunces(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: theme.foreground,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.settingsSubtitle,
                style: TextStyle(fontSize: 13, color: theme.muted, height: 1.4),
              ),
              const SizedBox(height: 24),
              _GroupTitle(l10n.groupDisplay, theme: theme),
              _SettingsCard(
                theme: theme,
                children: [
                  _SettingsThemeSection(
                    theme: theme,
                    themeMode: themeMode,
                    onThemeChanged: (mode) =>
                        ref.read(themeModeProvider.notifier).setMode(mode),
                  ),
                  Divider(height: 1, color: theme.glassBorder),
                  _SettingsLinkRow(
                    theme: theme,
                    icon: AppIcons.language,
                    title: l10n.language,
                    subtitle: currentLanguage.label,
                    onTap: () => context.push('/language'),
                  ),
                  Divider(height: 1, color: theme.glassBorder),
                  _SettingsToggleRow(
                    theme: theme,
                    icon: AppIcons.visibility,
                    title: l10n.showLabels,
                    subtitle: l10n.showLabelsSubtitle,
                    value: showLabels,
                    onChanged: (v) =>
                        ref.read(showLabelsProvider.notifier).toggle(v),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _GroupTitle(l10n.groupSchedulesAlarms, theme: theme),
              _SettingsCard(
                theme: theme,
                children: [
                  _SettingsToggleRow(
                    theme: theme,
                    icon: AppIcons.alarm,
                    title: l10n.alarmsByDefault,
                    subtitle: l10n.alarmsByDefaultSubtitle,
                    value: defaultAlarm,
                    onChanged: (v) =>
                        ref.read(defaultAlarmProvider.notifier).set(v),
                  ),
                  Divider(height: 1, color: theme.glassBorder),
                  _SettingsLinkRow(
                    theme: theme,
                    icon: AppIcons.timer,
                    title: l10n.defaultInterval,
                    subtitle: l10n.minutesBetweenWhispers(defaultInterval),
                    onTap: () => _pickInterval(context, ref, defaultInterval),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _GroupTitle(l10n.groupAccount, theme: theme),
              _SettingsCard(
                theme: theme,
                children: [
                  _SettingsLinkRow(
                    theme: theme,
                    icon: AppIcons.person,
                    title: l10n.signIn,
                    subtitle: l10n.signInSubtitle,
                    onTap: () => context.push('/sign-in'),
                  ),
                  Divider(height: 1, color: theme.glassBorder),
                  _SettingsLinkRow(
                    theme: theme,
                    icon: AppIcons.personAdd,
                    title: l10n.createAccount,
                    subtitle: l10n.createAccountSettingsSubtitle,
                    onTap: () => context.push('/sign-up'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _GroupTitle(l10n.groupModes, theme: theme),
              _SettingsCard(
                theme: theme,
                children: [
                  _SettingsLinkRow(
                    theme: theme,
                    icon: AppIcons.bedtime,
                    title: l10n.sleepMode,
                    subtitle: l10n.sleepModeSubtitle,
                    onTap: () => context.push('/sleep'),
                  ),
                  if (kAdhanFeatureEnabled) ...[
                    Divider(height: 1, color: theme.glassBorder),
                    _SettingsLinkRow(
                      theme: theme,
                      icon: AppIcons.prayer,
                      title: l10n.prayerMode,
                      subtitle: l10n.prayerModeSubtitle,
                      onTap: () => context.push('/prayer'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),
              _GroupTitle(l10n.groupDevice, theme: theme),
              _SettingsCard(
                theme: theme,
                children: [
                  _SettingsLinkRow(
                    theme: theme,
                    icon: AppIcons.battery,
                    title: l10n.batteryOptimization,
                    subtitle: l10n.batteryOptimizationSubtitle,
                    onTap: () => context.push('/battery'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Center(
                child: Text(
                  l10n.versionFooter,
                  style: TextStyle(
                      fontSize: 11, color: theme.muted.withValues(alpha: 0.85)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickInterval(
      BuildContext context, WidgetRef ref, int current) async {
    final l10n = context.l10n;
    final theme = whisperTheme(context);
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: theme.isDark ? AppColors.card : AppColors.lightCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetHandle(theme: theme),
            Text(
              l10n.defaultInterval,
              style: GoogleFonts.fraunces(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: theme.foreground,
              ),
            ),
            const SizedBox(height: 16),
            ...([15, 30, 45, 60, 90].map(
              (m) => ListTile(
                title: Text(
                  l10n.minutesCount(m),
                  style: TextStyle(color: theme.foreground),
                ),
                trailing: m == current
                    ? const Icon(AppIcons.checkCircle, color: AppColors.neon)
                    : null,
                onTap: () {
                  ref.read(defaultIntervalProvider.notifier).set(m);
                  Navigator.pop(ctx, m);
                },
              ),
            )),
          ],
        ),
      ),
    );
    if (picked != null) ref.read(defaultIntervalProvider.notifier).set(picked);
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle({required this.theme});

  final WhisperThemeExtension theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 18),
        decoration: BoxDecoration(
          color: theme.muted.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text, {required this.theme});

  final String text;
  final WhisperThemeExtension theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.35,
          color: theme.muted,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children, required this.theme});

  final List<Widget> children;
  final WhisperThemeExtension theme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: theme.isDark
              ? [
                  const Color(0x1FFFFFFF),
                  const Color(0x0DFFFFFF),
                ]
              : [
                  Colors.white,
                  const Color(0xFFF8FAFC),
                ],
        ),
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(
          color: theme.isDark
              ? const Color(0x24FFFFFF)
              : AppColors.ink.withValues(alpha: 0.1),
        ),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: Column(children: children),
      ),
    );
  }
}

class _SettingsThemeSection extends StatelessWidget {
  const _SettingsThemeSection({
    required this.theme,
    required this.themeMode,
    required this.onThemeChanged,
  });

  final WhisperThemeExtension theme;
  final AppThemeMode themeMode;
  final ValueChanged<AppThemeMode> onThemeChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _IconBox(AppIcons.palette, theme: theme),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.theme,
                      style: TextStyle(
                        color: theme.foreground,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.themeSubtitle,
                      style: TextStyle(
                          fontSize: 12, color: theme.muted, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<AppThemeMode>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: AppThemeMode.light,
                icon: const Icon(AppIcons.lightMode, size: 16),
                label: Text(l10n.light),
              ),
              ButtonSegment(
                value: AppThemeMode.dark,
                icon: const Icon(AppIcons.darkMode, size: 16),
                label: Text(l10n.dark),
              ),
              ButtonSegment(
                value: AppThemeMode.system,
                icon: const Icon(AppIcons.autoTheme, size: 16),
                label: Text(l10n.auto),
              ),
            ],
            selected: {themeMode},
            onSelectionChanged: (s) => onThemeChanged(s.first),
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              padding: WidgetStateProperty.all(
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 10)),
              textStyle: WidgetStateProperty.all(
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsToggleRow extends StatelessWidget {
  const _SettingsToggleRow({
    required this.theme,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final WhisperThemeExtension theme;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              _IconBox(icon, theme: theme),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: theme.foreground,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                          fontSize: 12, color: theme.muted, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _SettingsSwitch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsLinkRow extends StatelessWidget {
  const _SettingsLinkRow({
    required this.theme,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final WhisperThemeExtension theme;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              _IconBox(icon, theme: theme),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: theme.foreground,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                          fontSize: 12, color: theme.muted, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : AppColors.ink.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: theme.isDark
                        ? Colors.white.withValues(alpha: 0.10)
                        : AppColors.ink.withValues(alpha: 0.07),
                  ),
                ),
                child:
                    Icon(AppIcons.chevronRight, color: theme.muted, size: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSwitch extends StatelessWidget {
  const _SettingsSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = whisperTheme(context);
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: 48,
        height: 28,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: value
              ? theme.actionFill
              : (theme.isDark
                  ? AppColors.muted2.withValues(alpha: 0.55)
                  : AppColors.lightMuted2.withValues(alpha: 0.35)),
          border: Border.all(
            color: value
                ? theme.actionFill.withValues(alpha: 0.35)
                : theme.glassBorder,
          ),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? theme.onActionFill : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black
                      .withValues(alpha: theme.isDark ? 0.22 : 0.12),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox(this.icon, {required this.theme});

  final IconData icon;
  final WhisperThemeExtension theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: theme.isDark
              ? [
                  Colors.white.withValues(alpha: 0.16),
                  Colors.white.withValues(alpha: 0.05),
                ]
              : [
                  AppColors.ink.withValues(alpha: 0.08),
                  AppColors.ink.withValues(alpha: 0.03),
                ],
        ),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: theme.isDark
              ? Colors.white.withValues(alpha: 0.14)
              : AppColors.ink.withValues(alpha: 0.08),
        ),
      ),
      child: Icon(
        icon,
        size: 18,
        color: theme.isDark
            ? AppColors.brandLight
            : AppColors.ink.withValues(alpha: 0.75),
      ),
    );
  }
}
