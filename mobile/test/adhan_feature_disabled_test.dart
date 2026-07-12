// Pins that adhan is shelved for the current client release.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

String _read(String relPath) {
  final root = Directory.current.path;
  return File(p.join(root, relPath)).readAsStringSync();
}

void main() {
  group('Adhan feature shelved', () {
    test('kAdhanFeatureEnabled is false', () {
      final src = _read('lib/core/config/feature_flags.dart');
      expect(src, contains('const bool kAdhanFeatureEnabled = false'));
    });

    test('refreshModeState does not play adhan when feature is off', () {
      final src = _read('lib/services/playback/playback_coordinator.dart');
      expect(src, contains('if (kAdhanFeatureEnabled)'));
      expect(src, contains('AdhanPlayer.instance.playFor'));
      // playFor must be inside the kAdhanFeatureEnabled guard.
      final playIdx = src.indexOf('AdhanPlayer.instance.playFor');
      final guardIdx = src.lastIndexOf('if (kAdhanFeatureEnabled)', playIdx);
      expect(guardIdx, greaterThanOrEqualTo(0));
    });

    test('notification sync cancels prayer alarms when adhan is off', () {
      final src = _read('lib/services/notifications/notification_sync.dart');
      expect(src, contains('cancelAllScheduled'));
      expect(src, contains('!kAdhanFeatureEnabled'));
    });

    test('prayer settings UI is hidden when adhan is off', () {
      final src = _read('lib/features/settings/settings_screen.dart');
      expect(src, contains('if (kAdhanFeatureEnabled)'));
    });
  });
}
