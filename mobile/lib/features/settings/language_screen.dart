import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/premium_screen_background.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/settings_provider.dart';

/// Full-screen language picker — every supported language is always visible
/// and scrollable, with no sheet-height clipping.
class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = whisperTheme(context);
    final current =
        AppLanguage.fromCode(ref.watch(localeProvider).languageCode);

    return PremiumScreenBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(
            l10n.chooseLanguage,
            style: GoogleFonts.fraunces(fontWeight: FontWeight.w700),
          ),
        ),
        body: SafeArea(
          top: false,
          child: ListView.separated(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              MediaQuery.paddingOf(context).bottom + 16,
            ),
            itemCount: AppLanguage.values.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final lang = AppLanguage.values[i];
              final selected = lang == current;
              return Material(
                color: selected
                    ? AppColors.neon.withValues(alpha: 0.12)
                    : (theme.isDark ? theme.glass : Colors.white),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () async {
                    await ref.read(localeProvider.notifier).setLanguage(lang);
                    if (context.mounted) context.pop();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                lang.label,
                                style: GoogleFonts.dmSans(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: theme.foreground,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                lang.nativeScript,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: theme.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (selected)
                          const Icon(AppIcons.checkCircle,
                              color: AppColors.neon),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
