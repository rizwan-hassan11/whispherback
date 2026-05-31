import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/sign_in_screen.dart';
import '../../features/auth/sign_up_screen.dart';
import '../../features/clips/clips_screen.dart';
import '../../features/clips/import_screen.dart';
import '../../features/clips/record_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/playlists/new_playlist_screen.dart';
import '../../features/playlists/playlist_detail_screen.dart';
import '../../features/playlists/playlists_screen.dart';
import '../../features/device/battery_settings_screen.dart';
import '../../features/prayer/prayer_settings_screen.dart';
import '../../features/schedule/schedule_builder_screen.dart';
import '../../features/schedule/scheduled_overview_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/sleep/sleep_mode_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../widgets/main_shell.dart';

final _rootKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/sign-in',
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: '/sign-up',
        builder: (context, state) => const SignUpScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) => const NoTransitionPage(child: HomeScreen()),
          ),
          GoRoute(
            path: '/playlists',
            pageBuilder: (context, state) => const NoTransitionPage(child: PlaylistsScreen()),
          ),
          GoRoute(
            path: '/playlists/new',
            builder: (context, state) => const NewPlaylistScreen(),
          ),
          GoRoute(
            path: '/playlists/:id',
            builder: (context, state) => PlaylistDetailScreen(
              playlistId: state.pathParameters['id']!,
            ),
          ),
          GoRoute(
            path: '/clips',
            pageBuilder: (context, state) => const NoTransitionPage(child: ClipsScreen()),
          ),
          GoRoute(
            path: '/clips/record',
            builder: (context, state) => const RecordScreen(),
          ),
          GoRoute(
            path: '/clips/import',
            builder: (context, state) => const ImportScreen(),
          ),
          GoRoute(
            path: '/schedule',
            pageBuilder: (context, state) => const NoTransitionPage(child: ScheduledOverviewScreen()),
          ),
          GoRoute(
            path: '/schedule/build/:playlistId',
            builder: (context, state) => ScheduleBuilderScreen(
              playlistId: state.pathParameters['playlistId']!,
            ),
          ),
          GoRoute(
            path: '/sleep',
            builder: (context, state) => const SleepModeScreen(),
          ),
          GoRoute(
            path: '/prayer',
            builder: (context, state) => const PrayerSettingsScreen(),
          ),
          GoRoute(
            path: '/battery',
            builder: (context, state) => const BatterySettingsScreen(),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => const NoTransitionPage(child: SettingsScreen()),
          ),
        ],
      ),
    ],
  );
});
