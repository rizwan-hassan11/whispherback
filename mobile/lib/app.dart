import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';
import 'providers/repository_providers.dart';
import 'providers/settings_provider.dart';
import 'services/notifications/notification_service.dart';
import 'services/notifications/notification_sync.dart';
import 'services/scheduler/schedule_engine.dart';

class WhisperBackApp extends ConsumerStatefulWidget {
  const WhisperBackApp({super.key});

  @override
  ConsumerState<WhisperBackApp> createState() => _WhisperBackAppState();
}

class _WhisperBackAppState extends ConsumerState<WhisperBackApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(scheduleEngineProvider).start();
      _initNotifications();
    });
  }

  Future<void> _initNotifications() async {
    await NotificationService.instance.init();
    await NotificationService.instance.requestPermissions();
    // Restore the persistent notification + scheduled alarms after a cold
    // start (covers reboots and OS-forced closures while Active was ON).
    await syncWhisperNotifications(
      appState: ref.read(appStateRepositoryProvider),
      schedules: ref.read(scheduleRepositoryProvider),
    );
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final showLabels = ref.watch(showLabelsProvider);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    final materialMode = switch (themeMode) {
      AppThemeMode.dark => ThemeMode.dark,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.system => ThemeMode.system,
    };

    return MaterialApp.router(
      key: ValueKey('locale-${locale.languageCode}'),
      title: 'WhisperBack',
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      scrollBehavior:
          const MaterialScrollBehavior().copyWith(scrollbars: false),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 1.25,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: AppTheme.light(showLabels: showLabels, locale: locale),
      darkTheme: AppTheme.dark(showLabels: showLabels, locale: locale),
      themeMode: materialMode,
      routerConfig: router,
    );
  }
}
