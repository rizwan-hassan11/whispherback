import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/sign_in_screen.dart';
import '../../features/auth/sign_up_screen.dart';
import '../../features/clips/clips_screen.dart';
import '../../features/clips/import_screen.dart';
import '../../features/clips/record_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/playlists/add_clips_to_playlist_screen.dart';
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
final _shellKey = GlobalKey<NavigatorState>();

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
      // The five primary tabs live inside the shell (bottom nav visible).
      ShellRoute(
        navigatorKey: _shellKey,
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: HomeScreen()),
          ),
          GoRoute(
            path: '/playlists',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: PlaylistsScreen()),
          ),
          GoRoute(
            path: '/clips',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ClipsScreen()),
          ),
          GoRoute(
            path: '/schedule',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ScheduledOverviewScreen()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SettingsScreen()),
          ),
        ],
      ),
      // Detail / builder pages open full-screen on the root navigator so the
      // bottom nav bar never overlaps their content or action buttons.
      GoRoute(
        path: '/playlists/new',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const NewPlaylistScreen(),
      ),
      GoRoute(
        path: '/playlists/:id/add-clips',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => AddClipsToPlaylistScreen(
          playlistId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/playlists/:id',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => PlaylistDetailScreen(
          playlistId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/clips/record',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const RecordScreen(),
      ),
      GoRoute(
        path: '/clips/import',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const ImportScreen(),
      ),
      GoRoute(
        path: '/schedule/build/:playlistId',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => ScheduleBuilderScreen(
          playlistId: state.pathParameters['playlistId']!,
        ),
      ),
      GoRoute(
        path: '/sleep',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const SleepModeScreen(),
      ),
      GoRoute(
        path: '/prayer',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const PrayerSettingsScreen(),
      ),
      GoRoute(
        path: '/battery',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => const BatterySettingsScreen(),
      ),
    ],
  );
});
