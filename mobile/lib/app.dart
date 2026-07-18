import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/layout/shell_messenger.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';
import 'l10n/runtime_copy.dart';
import 'providers/repository_providers.dart';
import 'providers/settings_provider.dart';
import 'services/notifications/notification_service.dart';
import 'services/notifications/notification_sync.dart';
import 'services/platform/android_runtime_permissions.dart';
import 'services/platform/permission_prompt.dart';
import 'services/scheduler/native_alarms_bridge.dart';
import 'services/scheduler/schedule_engine.dart';
import 'services/scheduler/schedule_engine_binding.dart';
import 'services/scheduler/schedule_last_fired_store.dart';

class WhisperBackApp extends ConsumerStatefulWidget {
  const WhisperBackApp({super.key});

  @override
  ConsumerState<WhisperBackApp> createState() => _WhisperBackAppState();
}

class _WhisperBackAppState extends ConsumerState<WhisperBackApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ScheduleLastFiredStore.ensureLoaded();
      // Round 21: register the PlaylistRepository globally so the
      // notification-sync layer can hand it to `NativeAlarmsBridge`
      // without every call site having to thread it through. The
      // bridge needs the playlist's first playable clip path so the
      // native `WhisperPlaybackService` can play it when the alarm
      // fires (even if the app is fully killed).
      registerPlaylistRepositoryForBridge(
        ref.read(playlistRepositoryProvider),
      );
      // Eagerly create the engine (starts its timer in the provider).
      ref.read(scheduleEngineProvider);
      await _initNotifications();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ScheduleEngineBinding.instance.fireNow();
      // Round 29: await native playback poll BEFORE re-syncing the
      // keep-alive / schedule card. Parallel fetch+sync used to restart
      // silence under an in-flight MediaPlayer and hide the mini-player.
      unawaited(() async {
        try {
          await NativeAlarmsBridge.instance.fetchPlaybackState();
        } catch (_) {}
        if (!mounted) return;
        await _refreshPermissionsAndSync();
      }());
    }
  }

  Future<void> _refreshPermissionsAndSync() async {
    await ensureAndroidSchedulingPermissions();
    // Re-post the persistent notification IMMEDIATELY on resume and then
    // again 500 ms later as a defensive double-tap. The QA report
    // "notification bar becomes hidden when I open the app" was caused
    // by some OEMs (Vivo / Xiaomi) silently dismissing the WhisperBack
    // ongoing card during the activity transition. Re-posting on
    // every resume is cheap (idempotent — `_plugin.show` with the
    // same id just replaces) and guarantees the user always sees
    // the card after switching back to the app.
    try {
      await syncWhisperNotifications(
        appState: ref.read(appStateRepositoryProvider),
        schedules: ref.read(scheduleRepositoryProvider),
        prayer: ref.read(prayerRepositoryProvider),
      );
    } catch (_) {}
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    try {
      await syncWhisperNotifications(
        appState: ref.read(appStateRepositoryProvider),
        schedules: ref.read(scheduleRepositoryProvider),
        prayer: ref.read(prayerRepositoryProvider),
      );
    } catch (_) {}
  }

  Future<void> _initNotifications() async {
    await NotificationService.instance.init();

    // Detect an alarm-triggered cold start BEFORE requesting anything.
    // Round 26: when a scheduled alarm cold-starts the app, a clip is about
    // to play in the background and the user probably isn't even looking at
    // the screen. We must NOT pop any permission/settings dialog here — doing
    // so (especially the OEM battery-optimization screen) interrupts playback
    // and yanks the user into system settings. This was the QA report
    // "schedule plays a few seconds then pauses and redirects me to App
    // battery usage". On alarm launches we skip all prompts and go straight
    // to firing the schedule.
    final fromAlarm =
        await NotificationService.instance.launchedFromScheduleAlarm();

    // Eager permission requests on a NORMAL cold start so the user is asked
    // ONCE up front instead of being routed through a manual "Finish
    // setup" chip. Each call is best-effort: a denial is fine — the
    // setup chip remains visible so the user can grant later. Order
    // matters: notification first (so the rest can post status), then
    // microphone (recording), and finally battery exemption — which is
    // requested AT MOST ONCE ever (see requestBatteryExemptionOnce) so we
    // never re-open the OEM battery screen on later launches.
    if (!fromAlarm) {
      try {
        await NotificationService.instance.requestPermissions();
      } catch (_) {}
      try {
        await requestAppPermissionKind(AppPermissionKind.microphone);
      } catch (_) {}
      try {
        await requestBatteryExemptionOnce();
      } catch (_) {}
      await ensureAndroidSchedulingPermissions();
    }

    await syncWhisperNotifications(
      appState: ref.read(appStateRepositoryProvider),
      schedules: ref.read(scheduleRepositoryProvider),
      prayer: ref.read(prayerRepositoryProvider),
    );
    // Cold start / alarm tap — run an immediate scheduling pass.
    // Round 19: when the app was launched from a scheduled-alarm
    // notification, ALSO bypass the lateness cap. Without this, a
    // user who taps the alarm 3-10 minutes after it rang (because
    // their device was in their pocket) would see the engine
    // silently skip the slot and feel like nothing happened.
    await ScheduleEngineBinding.instance.fireNow(force: fromAlarm);

    // POST_NOTIFICATIONS is asked asynchronously by the OS dialog; the
    // first sync above may have run BEFORE the user tapped "Allow". A
    // delayed retry guarantees the persistent "active" notification
    // appears within a couple of seconds of granting permission instead
    // of waiting for the next lifecycle event. Best-effort: re-sync
    // every 2 s for 10 s then stop. Cheap and bounded.
    if (mounted) {
      for (final delay in const [
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 8),
      ]) {
        await Future<void>.delayed(delay);
        if (!mounted) return;
        try {
          await syncWhisperNotifications(
            appState: ref.read(appStateRepositoryProvider),
            schedules: ref.read(scheduleRepositoryProvider),
            prayer: ref.read(prayerRepositoryProvider),
          );
        } catch (_) {}
      }
    }
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
      scaffoldMessengerKey: rootMessengerKey,
      title: 'WhisperBack',
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      scrollBehavior:
          const MaterialScrollBehavior().copyWith(scrollbars: false),
      builder: (context, child) {
        RuntimeCopy.bind(AppLocalizations.ofOrThrow(context));
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
