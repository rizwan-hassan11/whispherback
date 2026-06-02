import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/depth_surface.dart';
import '../../core/widgets/brand_logos.dart';
import '../../l10n/app_localizations.dart';

enum AuthTab { signIn, signUp }

class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.footer,
    this.highlights,
    this.benefits,
    this.activeTab = AuthTab.signIn,
    this.onSignInTap,
    this.onSignUpTap,
    this.guestAction,
    this.onBack,
    this.compact = false,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? footer;
  final List<AuthHighlight>? highlights;
  final List<AuthBenefit>? benefits;
  final AuthTab activeTab;
  final VoidCallback? onSignInTap;
  final VoidCallback? onSignUpTap;
  final VoidCallback? guestAction;
  final VoidCallback? onBack;
  final bool compact;

  static TextStyle prosperWordmark(BuildContext context, {double size = 26}) {
    return GoogleFonts.fraunces(
      fontSize: size,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.4,
      height: 1.05,
      color: whisperTheme(context).foreground,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = whisperTheme(context);
    final isDark = theme.isDark;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: isDark
                  ? AppColors.backgroundGradient
                  : AppColors.lightBackgroundGradient,
            ),
          ),
          Positioned(
            top: -80,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 320,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withValues(alpha: isDark ? 0.09 : 0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (compact) ...[
            Positioned(
              top: -30,
              right: -20,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.brandLight
                      .withValues(alpha: isDark ? 0.1 : 0.06),
                ),
              ),
            ),
            Positioned(
              top: 180,
              left: -40,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      AppColors.success.withValues(alpha: isDark ? 0.08 : 0.06),
                ),
              ),
            ),
          ],
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  padding: EdgeInsets.fromLTRB(16, 6, 16, compact ? 20 : 32),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                        minHeight: compact ? 0 : constraints.maxHeight - 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _AuthTopBar(
                          theme: theme,
                          activeTab: activeTab,
                          onBack: onBack,
                          onSignInTap: onSignInTap,
                          onSignUpTap: onSignUpTap,
                        ),
                        SizedBox(height: compact ? 10 : 16),
                        if (compact)
                          _UnifiedAuthPanel(
                            theme: theme,
                            title: title,
                            subtitle: subtitle,
                            highlights: highlights ??
                                benefits
                                    ?.map(
                                      (b) => AuthHighlight(
                                        icon: b.icon,
                                        label: b.label,
                                      ),
                                    )
                                    .toList(),
                            child: child,
                          )
                        else ...[
                          _AuthHeroPanel(
                            theme: theme,
                            title: title,
                            subtitle: subtitle,
                            highlights: highlights,
                            benefits: benefits,
                            compact: compact,
                          ),
                          SizedBox(height: compact ? 10 : 16),
                          DepthSurface(
                            radius: AppRadii.sm,
                            elevated: true,
                            tiltX: 0.02,
                            lift: 8,
                            padding: EdgeInsets.fromLTRB(
                              16,
                              compact ? 16 : 22,
                              16,
                              compact ? 14 : 20,
                            ),
                            child: child,
                          ),
                        ],
                        if (footer != null) ...[
                          SizedBox(height: compact ? 12 : 20),
                          footer!,
                        ],
                        if (guestAction != null) ...[
                          SizedBox(height: compact ? 4 : 10),
                          Center(
                            child: TextButton(
                              onPressed: guestAction,
                              child: Text(
                                context.l10n.continueWithoutAccount,
                                style: TextStyle(
                                  color: theme.muted,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class AuthHighlight {
  const AuthHighlight({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class AuthBenefit {
  const AuthBenefit({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class _AuthTopBar extends StatelessWidget {
  const _AuthTopBar({
    required this.theme,
    required this.activeTab,
    this.onBack,
    this.onSignInTap,
    this.onSignUpTap,
  });

  final WhisperThemeExtension theme;
  final AuthTab activeTab;
  final VoidCallback? onBack;
  final VoidCallback? onSignInTap;
  final VoidCallback? onSignUpTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Row(
      children: [
        if (onBack != null)
          IconButton(
            onPressed: onBack,
            style: IconButton.styleFrom(
              backgroundColor: theme.glass,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
                side: BorderSide(color: theme.glassBorder),
              ),
            ),
            icon: Icon(AppIcons.back, color: theme.foreground),
          ),
        if (onSignInTap != null && onSignUpTap != null) ...[
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color:
                    Colors.white.withValues(alpha: theme.isDark ? 0.06 : 0.5),
                borderRadius: BorderRadius.circular(AppRadii.sm),
                border: Border.all(color: theme.glassBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _TabButton(
                      label: l10n.signIn,
                      selected: activeTab == AuthTab.signIn,
                      onTap: onSignInTap!,
                      theme: theme,
                    ),
                  ),
                  Expanded(
                    child: _TabButton(
                      label: l10n.signUp,
                      selected: activeTab == AuthTab.signUp,
                      onTap: onSignUpTap!,
                      theme: theme,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final WhisperThemeExtension theme;

  @override
  Widget build(BuildContext context) {
    final fill = selected ? theme.actionFill : Colors.transparent;
    final fg = selected ? theme.onActionFill : theme.muted;

    return Material(
      color: fill,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

class _UnifiedAuthPanel extends StatelessWidget {
  const _UnifiedAuthPanel({
    required this.theme,
    required this.title,
    required this.subtitle,
    required this.child,
    this.highlights,
  });

  final WhisperThemeExtension theme;
  final String title;
  final String subtitle;
  final Widget child;
  final List<AuthHighlight>? highlights;

  static const _barHeights = [10.0, 18.0, 24.0, 14.0, 20.0];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: theme.isDark
              ? [
                  Colors.white.withValues(alpha: 0.11),
                  Colors.white.withValues(alpha: 0.04),
                ]
              : [
                  Colors.white,
                  AppColors.lightBg2,
                ],
        ),
        border: Border.all(
          color: theme.isDark
              ? Colors.white.withValues(alpha: 0.16)
              : AppColors.ink.withValues(alpha: 0.1),
        ),
        boxShadow: theme.isDark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.32),
                  blurRadius: 48,
                  offset: const Offset(0, 16),
                ),
              ]
            : [
                BoxShadow(
                  color: AppColors.ink.withValues(alpha: 0.08),
                  blurRadius: 40,
                  offset: const Offset(0, 12),
                ),
              ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.brandLight.withValues(alpha: 0.2),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.card, AppColors.ink],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final h in _barHeights)
                          Container(
                            width: 3,
                            height: h,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WhisperBack',
                      style: AuthShell.prosperWordmark(context, size: 20),
                    ),
                    Text(
                      title,
                      style: GoogleFonts.fraunces(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: theme.foreground,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            style: TextStyle(
              color: theme.muted,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          if (highlights != null && highlights!.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: highlights!
                  .map(
                    (h) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: theme.isDark
                            ? Colors.white.withValues(alpha: 0.07)
                            : AppColors.ink.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(color: theme.glassBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            h.icon,
                            size: 12,
                            color: theme.isDark
                                ? AppColors.brandLight
                                : AppColors.ink,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            h.label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: theme.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _AuthHeroPanel extends StatelessWidget {
  const _AuthHeroPanel({
    required this.theme,
    required this.title,
    required this.subtitle,
    this.highlights,
    this.benefits,
    this.compact = false,
  });

  final WhisperThemeExtension theme;
  final String title;
  final String subtitle;
  final List<AuthHighlight>? highlights;
  final List<AuthBenefit>? benefits;
  final bool compact;

  static const _barHeights = [10.0, 20.0, 28.0, 16.0, 24.0];
  static const _compactBarHeights = [8.0, 14.0, 20.0, 12.0, 18.0];

  Widget _visual(double size, List<double> bars) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 14 : 18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.card, AppColors.ink],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: compact ? 20 : 28,
            offset: Offset(0, compact ? 6 : 10),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final h in bars)
            Container(
              width: compact ? 3 : 4,
              height: h,
              margin: EdgeInsets.symmetric(horizontal: compact ? 1 : 1.5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _highlightChips(List<AuthHighlight> items) {
    return items
        .map(
          (h) => Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 9 : 11,
              vertical: compact ? 5 : 7,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: theme.isDark ? 0.08 : 0.65),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: theme.glassBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(h.icon, size: compact ? 11 : 13, color: theme.muted),
                SizedBox(width: compact ? 5 : 6),
                Text(
                  h.label,
                  style: TextStyle(
                    fontSize: compact ? 10 : 11,
                    fontWeight: FontWeight.w600,
                    color: theme.foreground,
                  ),
                ),
              ],
            ),
          ),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final panelPadding = compact
        ? const EdgeInsets.fromLTRB(14, 14, 14, 12)
        : const EdgeInsets.fromLTRB(18, 22, 18, 20);
    final chipItems = highlights ??
        benefits
            ?.map((b) => AuthHighlight(icon: b.icon, label: b.label))
            .toList();

    return DepthSurface(
      radius: AppRadii.sm,
      elevated: true,
      tiltX: compact ? 0.02 : 0.03,
      lift: compact ? 6 : 10,
      padding: panelPadding,
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _visual(48, _compactBarHeights),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'WhisperBack',
                            style: AuthShell.prosperWordmark(context, size: 18),
                          ),
                          Text(
                            title,
                            style: GoogleFonts.fraunces(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: theme.foreground,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: theme.muted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                if (chipItems != null && chipItems.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _highlightChips(chipItems),
                  ),
                ],
              ],
            )
          : Column(
              children: [
                _visual(64, _barHeights),
                const SizedBox(height: 16),
                Text('WhisperBack', style: AuthShell.prosperWordmark(context)),
                const SizedBox(height: 10),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.fraunces(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: theme.foreground,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: theme.muted, fontSize: 14, height: 1.55),
                ),
                if (chipItems != null && chipItems.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: _highlightChips(chipItems),
                  ),
                ],
              ],
            ),
    );
  }
}

class AuthBenefitsRow extends StatelessWidget {
  const AuthBenefitsRow({super.key, required this.benefits});

  final List<AuthBenefit> benefits;

  @override
  Widget build(BuildContext context) {
    final theme = whisperTheme(context);

    return Row(
      children: List.generate(benefits.length, (i) {
        final b = benefits[i];
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < benefits.length - 1 ? 8 : 0),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
              decoration: BoxDecoration(
                color:
                    Colors.white.withValues(alpha: theme.isDark ? 0.07 : 0.6),
                borderRadius: BorderRadius.circular(AppRadii.sm),
                border: Border.all(color: theme.glassBorder),
              ),
              child: Column(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: theme.glass,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: theme.glassBorder),
                    ),
                    child: Icon(b.icon, size: 16, color: theme.foreground),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    b.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: theme.muted,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

class AuthTermsRow extends StatelessWidget {
  const AuthTermsRow({
    super.key,
    required this.checked,
    required this.onChanged,
    this.compact = false,
  });

  final bool checked;
  final ValueChanged<bool> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = whisperTheme(context);
    final isDark = theme.isDark;

    return InkWell(
      onTap: () => onChanged(!checked),
      borderRadius: BorderRadius.circular(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: compact ? 20 : 22,
            height: compact ? 20 : 22,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              color: checked ? AppColors.brand : theme.glass,
              border: Border.all(
                color: checked
                    ? Colors.white.withValues(alpha: 0.35)
                    : theme.glassBorder,
              ),
            ),
            child: checked
                ? Icon(
                    AppIcons.check,
                    size: 16,
                    color: isDark ? AppColors.deep : AppColors.brand,
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  color: theme.muted,
                  fontSize: compact ? 11 : 12,
                  height: 1.45,
                ),
                children: [
                  TextSpan(text: l10n.termsPrefix),
                  TextSpan(
                    text: l10n.termsOfService,
                    style: TextStyle(
                      color: theme.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(text: l10n.and),
                  TextSpan(
                    text: l10n.privacyPolicy,
                    style: TextStyle(
                      color: theme.foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AuthTextField extends StatelessWidget {
  const AuthTextField({
    super.key,
    required this.label,
    this.hint,
    this.obscure = false,
    this.controller,
    this.keyboardType,
    this.prefixIcon,
    this.suffix,
    this.onChanged,
    this.compact = false,
  });

  final String label;
  final String? hint;
  final bool obscure;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final IconData? prefixIcon;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = whisperTheme(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: compact ? 11 : 12,
            fontWeight: FontWeight.w600,
            color: theme.muted,
            letterSpacing: 0.2,
          ),
        ),
        SizedBox(height: compact ? 5 : 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.isDark ? AppColors.glass : AppColors.lightGlass,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: Border.all(color: theme.glassBorder),
          ),
          child: Row(
            children: [
              if (prefixIcon != null) ...[
                SizedBox(width: compact ? 12 : 14),
                Icon(prefixIcon, size: compact ? 16 : 18, color: theme.muted),
              ],
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: obscure,
                  keyboardType: keyboardType,
                  onChanged: onChanged,
                  style: TextStyle(fontSize: compact ? 14 : 15),
                  decoration: InputDecoration(
                    hintText: hint,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: compact ? 11 : 14,
                    ),
                    suffixIcon: suffix,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SocialAuthRow extends StatelessWidget {
  const SocialAuthRow({
    super.key,
    required this.onGoogle,
    required this.onApple,
    this.compact = false,
  });

  final VoidCallback onGoogle;
  final VoidCallback onApple;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Row(
      children: [
        Expanded(
          child: SocialAuthButton(
            label: l10n.google,
            logo: const GoogleLogo(size: 18),
            onPressed: onGoogle,
            compact: compact,
          ),
        ),
        SizedBox(width: compact ? 8 : 10),
        Expanded(
          child: SocialAuthButton(
            label: l10n.apple,
            logo: AppleLogo(size: 18, color: whisperTheme(context).foreground),
            onPressed: onApple,
            compact: compact,
          ),
        ),
      ],
    );
  }
}

class SocialAuthButton extends StatelessWidget {
  const SocialAuthButton({
    super.key,
    required this.label,
    required this.logo,
    required this.onPressed,
    this.compact = false,
  });

  final String label;
  final Widget logo;
  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = whisperTheme(context);

    return Material(
      color: theme.isDark ? Colors.white.withValues(alpha: 0.06) : Colors.white,
      elevation: theme.isDark ? 0 : 1,
      shadowColor: Colors.black.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        side: BorderSide(
          color: theme.isDark
              ? Colors.white.withValues(alpha: 0.18)
              : AppColors.ink.withValues(alpha: 0.12),
        ),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: SizedBox(
          height: compact ? 42 : 44,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              logo,
              SizedBox(width: compact ? 6 : 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: compact ? 12 : 13,
                  letterSpacing: -0.1,
                  color: theme.foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon = AppIcons.login,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDark = whisperTheme(context).isDark;

    return FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.sm)),
        backgroundColor: isDark ? AppColors.brand : AppColors.ink,
        foregroundColor: isDark ? AppColors.deep : AppColors.brand,
        elevation: 0,
        shadowColor: AppColors.brandGlow,
      ),
      child: loading
          ? SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: isDark ? AppColors.deep : AppColors.brand,
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 8),
                Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
    );
  }
}

class PasswordStrengthBar extends StatelessWidget {
  const PasswordStrengthBar({
    super.key,
    required this.password,
    this.compact = false,
  });

  final String password;
  final bool compact;

  int get _score {
    var s = 0;
    if (password.length >= 6) s++;
    if (password.length >= 8) s++;
    if (RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[0-9]').hasMatch(password)) {
      s++;
    }
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) s++;
    return s;
  }

  String _hint(BuildContext context) {
    final l10n = context.l10n;
    if (password.isEmpty) return l10n.passwordHintEmpty;
    if (_score <= 1) return l10n.passwordWeak;
    if (_score == 2) return l10n.passwordFair;
    if (_score == 3) return l10n.passwordGood;
    return l10n.passwordStrong;
  }

  @override
  Widget build(BuildContext context) {
    final theme = whisperTheme(context);

    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 10 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(4, (i) {
              return Expanded(
                child: Container(
                  height: 3,
                  margin: EdgeInsets.only(right: i < 3 ? 4 : 0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: i < _score
                        ? (_score < 3
                            ? AppColors.accentBright
                            : AppColors.success)
                        : theme.glassBorder,
                  ),
                ),
              );
            }),
          ),
          SizedBox(height: compact ? 4 : 6),
          Text(
            _hint(context),
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              color: theme.muted,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = whisperTheme(context);
    final label = context.l10n.orContinueWith;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 12 : 18),
      child: Row(
        children: [
          Expanded(child: Divider(color: theme.glassBorder)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: TextStyle(color: theme.muted, fontSize: compact ? 11 : 12),
            ),
          ),
          Expanded(child: Divider(color: theme.glassBorder)),
        ],
      ),
    );
  }
}
