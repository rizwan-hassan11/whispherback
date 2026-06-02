import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';

class BatterySettingsScreen extends StatelessWidget {
  const BatterySettingsScreen({super.key});

  static List<_OemGuide> _guides(AppLocalizations l10n) => [
        _OemGuide(
          title: l10n.samsungGuide,
          steps: const [
            'Settings → Apps → WhisperBack',
            'Battery → Unrestricted',
            'Allow background activity',
          ],
        ),
        _OemGuide(
          title: l10n.xiaomiGuide,
          steps: const [
            'Settings → Apps → Manage apps → WhisperBack',
            'Battery saver → No restrictions',
            'Autostart → Enable',
          ],
        ),
        _OemGuide(
          title: l10n.huaweiGuide,
          steps: const [
            'Settings → Apps → WhisperBack',
            'Battery → App launch → Manage manually',
            'Enable all three toggles',
          ],
        ),
        _OemGuide(
          title: l10n.stockAndroidGuide,
          steps: const [
            'Settings → Apps → WhisperBack → Battery',
            'Select Unrestricted',
          ],
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = whisperTheme(context);
    final guides = _guides(l10n);

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
        _BatteryAmbience(isDark: theme.isDark),
        Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Column(
              children: [
                _SubTopBar(
                  theme: theme,
                  title: l10n.batteryTitle,
                  onBack: () => context.pop(),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                    children: [
                      _HeroIcon(
                        theme: theme,
                        icon: AppIcons.battery,
                        glowColor: AppColors.success,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        l10n.reliableSchedules,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                          color: theme.muted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.batteryHeroTitle,
                        style: GoogleFonts.fraunces(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: theme.foreground,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        l10n.batteryWhitelistBody,
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
                          (
                            AppIcons.schedule,
                            l10n.onTimePlayback,
                            l10n.onTimePlaybackDesc
                          ),
                          (
                            AppIcons.alarm,
                            l10n.reliableAlarms,
                            l10n.reliableAlarmsDesc
                          ),
                          (
                            AppIcons.shield,
                            l10n.noDataCollection,
                            l10n.noDataCollectionDesc
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        l10n.byPhoneBrand,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.35,
                          color: theme.muted,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...guides.map(
                        (g) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _GuideCard(theme: theme, guide: g),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(l10n.openSystemSettingsSnack)),
                          );
                        },
                        icon: const Icon(AppIcons.settings, size: 18),
                        label: Text(l10n.openSystemSettings),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                          ),
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

class _OemGuide {
  const _OemGuide({required this.title, required this.steps});

  final String title;
  final List<String> steps;
}

class _BatteryAmbience extends StatelessWidget {
  const _BatteryAmbience({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -20,
            right: -30,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.success.withValues(alpha: isDark ? 0.1 : 0.08),
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

class _HeroIcon extends StatelessWidget {
  const _HeroIcon({
    required this.theme,
    required this.icon,
    required this.glowColor,
  });

  final WhisperThemeExtension theme;
  final IconData icon;
  final Color glowColor;

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
              color: glowColor.withValues(alpha: theme.isDark ? 0.15 : 0.12),
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
                  color: glowColor.withValues(alpha: 0.25),
                  blurRadius: 24,
                ),
              ],
            ),
            child: Icon(icon, size: 32, color: glowColor),
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
                      color: AppColors.success.withValues(alpha: 0.1),
                      border: Border.all(
                        color: AppColors.success.withValues(alpha: 0.2),
                      ),
                    ),
                    child:
                        Icon(items[i].$1, size: 18, color: AppColors.success),
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

class _GuideCard extends StatelessWidget {
  const _GuideCard({required this.theme, required this.guide});

  final WhisperThemeExtension theme;
  final _OemGuide guide;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.isDark ? theme.glass : Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: theme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            guide.title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: theme.foreground,
            ),
          ),
          const SizedBox(height: 10),
          ...List.generate(guide.steps.length, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.actionFill.withValues(alpha: 0.15),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color:
                            theme.isDark ? AppColors.brandLight : AppColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      guide.steps[i],
                      style: TextStyle(
                          fontSize: 13, color: theme.muted, height: 1.4),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
