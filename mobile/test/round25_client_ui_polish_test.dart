import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

String _read(String relPath) {
  return File(p.join(Directory.current.path, relPath)).readAsStringSync();
}

void main() {
  group('Round 25 client UI polish', () {
    test('Sleep is a bottom-nav tab', () {
      final shell = _read('lib/core/widgets/main_shell.dart');
      expect(shell, contains("label: l10n.navSleep"));
      expect(shell, contains("context.go('/sleep')"));
      final router = _read('lib/core/router/app_router.dart');
      expect(router, contains("path: '/sleep'"));
      expect(
          router,
          isNot(contains(
              "parentNavigatorKey: _rootKey,\n        builder: (context, state) => const SleepModeScreen()")));
    });

    test('Home header no longer hosts the sleep shortcut', () {
      final home = _read('lib/features/home/home_screen.dart');
      expect(home, isNot(contains('_ZzzButton')));
      expect(home, isNot(contains("context.push('/sleep')")));
    });

    test('Playlist cards expose play/pause + favourite + edit + delete', () {
      final card = _read('lib/features/playlists/widgets/playlist_card.dart');
      expect(card, contains('onFavourite'));
      expect(card, contains('onEdit'));
      expect(card, contains('onDelete'));
      expect(card, contains('isPlaying: isPlaying'));
    });

    test('ProminentPlayButton supports pause state', () {
      final btn = _read('lib/core/widgets/prominent_play_button.dart');
      expect(btn, contains('isPlaying'));
      expect(btn, contains('AppIcons.pause'));
    });

    test('Mini-player inherits playlist cover palette', () {
      final mini = _read('lib/features/playback/mini_player_bar.dart');
      expect(mini, contains('PlaylistCoverPalette'));
      expect(mini, contains('snapshot.playlistId'));
    });

    test('Playlists add-clips opens picker not raw clips tab', () {
      final screen = _read('lib/features/playlists/playlists_screen.dart');
      expect(screen, contains('showPlaylistPickerForClips'));
      expect(screen, isNot(contains("context.push('/clips')")));
    });

    test('Playlists list uses selective playback rebuild', () {
      final screen = _read('lib/features/playlists/playlists_screen.dart');
      expect(screen, contains('PlaylistPlaybackBadge.fromSnapshot'));
      expect(screen, contains('playbackSnapshotProvider.select'));
      expect(screen, contains('cacheExtent: 480'));
    });

    test('Favourites column exists in schema v5', () {
      final db = _read('lib/data/database/database_helper.dart');
      expect(db, contains('is_favourite'));
      expect(db, contains('version: 5'));
    });

    test('Tap feedback wired for snappy interactions', () {
      expect(_read('lib/core/ux/tap_feedback.dart'), contains('tapHaptic'));
      expect(
          _read('lib/core/widgets/glass_nav_bar.dart'), contains('tapHaptic'));
      expect(_read('lib/features/playlists/playlist_actions.dart'),
          contains('unawaited'));
    });

    test('Launcher icon source asset exists', () {
      expect(
        File(p.join(Directory.current.path, 'assets/branding/app_logo.png'))
            .existsSync(),
        isTrue,
      );
    });
  });
}
