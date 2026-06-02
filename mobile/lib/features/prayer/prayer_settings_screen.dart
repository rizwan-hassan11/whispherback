import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../data/repositories/prayer_repository.dart';
import '../../providers/playback_providers.dart';
import '../../providers/repository_providers.dart';

class PrayerSettingsScreen extends ConsumerStatefulWidget {
  const PrayerSettingsScreen({super.key});

  @override
  ConsumerState<PrayerSettingsScreen> createState() =>
      _PrayerSettingsScreenState();
}

class _PrayerSettingsScreenState extends ConsumerState<PrayerSettingsScreen> {
  static const _methods = ['Karachi', 'MWL', 'ISNA', 'Umm al-Qura', 'Egyptian'];
  static const _madhabs = ['Shafi', 'Hanafi'];

  Future<void> _save(PrayerSettings settings) async {
    await ref.read(prayerRepositoryProvider).saveSettings(settings);
    ref.invalidate(prayerSettingsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settingsAsync = ref.watch(prayerSettingsProvider);
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
        _PrayerAmbience(isDark: theme.isDark),
        Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: settingsAsync.when(
              data: (settings) => Column(
                children: [
                  _SubTopBar(
                    theme: theme,
                    title: l10n.prayerModeTitle,
                    onBack: () => context.pop(),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                      children: [
                        _CompassHero(theme: theme),
                        const SizedBox(height: 20),
                        Text(
                          l10n.faithAndFocus,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                            color: theme.muted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.pauseDuringPrayer,
                          style: GoogleFonts.fraunces(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: theme.foreground,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          l10n.prayerHeroBody,
                          style: TextStyle(
                            color: theme.muted,
                            fontSize: 14,
                            height: 1.55,
                          ),
                        ),
                        const SizedBox(height: 22),
                        _InfoCard(
                          theme: theme,
                          items: [
                            (AppIcons.shield, l10n.private, l10n.onDeviceDesc),
                            (
                              AppIcons.prayer,
                              l10n.accurateTimes,
                              l10n.accurateTimesDesc
                            ),
                            (
                              AppIcons.volumeOff,
                              l10n.autoPause,
                              l10n.autoPausePrayerDesc
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _SectionLabel(l10n.calculationMethod, theme: theme),
                        const SizedBox(height: 12),
                        _OptionGrid(
                          theme: theme,
                          options: _methods,
                          selected: settings.calculationMethod,
                          onSelect: (v) => _save(
                            PrayerSettings(
                              calculationMethod: v,
                              madhab: settings.madhab,
                              useGps: settings.useGps,
                              manualCity: settings.manualCity,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _SectionLabel(l10n.asrMadhab, theme: theme),
                        const SizedBox(height: 12),
                        _OptionGrid(
                          theme: theme,
                          options: _madhabs,
                          selected: settings.madhab,
                          columns: 2,
                          onSelect: (v) => _save(
                            PrayerSettings(
                              calculationMethod: settings.calculationMethod,
                              madhab: v,
                              useGps: settings.useGps,
                              manualCity: settings.manualCity,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _GpsToggleCard(
                          theme: theme,
                          value: settings.useGps,
                          onChanged: (v) => _save(
                            PrayerSettings(
                              calculationMethod: settings.calculationMethod,
                              madhab: settings.madhab,
                              useGps: v,
                              manualCity: settings.manualCity,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
            ),
          ),
        ),
      ],
    );
  }
}

class _PrayerAmbience extends StatelessWidget {
  const _PrayerAmbience({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -30,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.brandLight
                      .withValues(alpha: isDark ? 0.1 : 0.08),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubTopBar extends StatelessWidget {
  const _SubTopBar({
    required this.theme,
    required this.title,
    required this.onBack,
  });

  final WhisperThemeExtension theme;
  final String title;
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
              title,
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

class _CompassHero extends StatelessWidget {
  const _CompassHero({required this.theme});

  final WhisperThemeExtension theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.brandLight
                  .withValues(alpha: theme.isDark ? 0.14 : 0.1),
            ),
          ),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.sm),
              color: theme.isDark ? theme.glass : Colors.white,
              border: Border.all(color: theme.glassBorder),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandGlow.withValues(alpha: 0.3),
                  blurRadius: 24,
                ),
              ],
            ),
            child: const Icon(AppIcons.prayer,
                size: 32, color: AppColors.brandLight),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.theme, required this.items});

  final WhisperThemeExtension theme;
  final List<(IconData, String, String)> items;

  @override
  Widget build(BuildContext context) {
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                      color: AppColors.brand.withValues(alpha: 0.1),
                      border: Border.all(
                        color: AppColors.brandLight.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Icon(items[i].$1,
                        size: 18, color: AppColors.brandLight),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          items[i].$2,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: theme.foreground,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          items[i].$3,
                          style: TextStyle(fontSize: 12, color: theme.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {required this.theme});

  final String text;
  final WhisperThemeExtension theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.35,
        color: theme.muted,
      ),
    );
  }
}

class _OptionGrid extends StatelessWidget {
  const _OptionGrid({
    required this.theme,
    required this.options,
    required this.selected,
    required this.onSelect,
    this.columns = 2,
  });

  final WhisperThemeExtension theme;
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelect;
  final int columns;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: columns == 2 ? 2.2 : 2.8,
      ),
      itemCount: options.length,
      itemBuilder: (context, i) {
        final option = options[i];
        final isSelected = option == selected;
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
            onTap: () => onSelect(option),
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: Center(
              child: Text(
                option,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? theme.onActionFill : theme.muted,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GpsToggleCard extends StatelessWidget {
  const _GpsToggleCard({
    required this.theme,
    required this.value,
    required this.onChanged,
  });

  final WhisperThemeExtension theme;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: theme.isDark ? theme.glass : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        side: BorderSide(color: theme.glassBorder),
      ),
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  color: AppColors.success.withValues(alpha: 0.1),
                ),
                child: const Icon(AppIcons.sunrise,
                    color: AppColors.success, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.useGpsLocation,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: theme.foreground,
                      ),
                    ),
                    Text(
                      context.l10n.useGpsLocationDesc,
                      style: TextStyle(fontSize: 12, color: theme.muted),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}
