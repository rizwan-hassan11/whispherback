import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Restricts playback/import to files under the app clips directory.
abstract final class ClipPathGuard {
  static String? _clipsRoot;

  static Future<void> ensureLoaded() async {
    if (_clipsRoot != null) return;
    final dir = await getApplicationDocumentsDirectory();
    _clipsRoot = p.normalize(p.join(dir.path, 'clips'));
  }

  /// Test hook — avoids path_provider in VM unit tests.
  @visibleForTesting
  static void bindClipsRootForTests(String root) {
    _clipsRoot = p.normalize(root);
  }

  static bool isAllowed(String filePath) {
    if (filePath.startsWith('asset://') || filePath.startsWith('demo://')) {
      return false;
    }
    if (filePath.contains('..')) return false;

    final normalized = p.normalize(filePath);
    final lower = normalized.toLowerCase();
    final isAudio = lower.endsWith('.m4a') ||
        lower.endsWith('.mp3') ||
        lower.endsWith('.aac');

    final root = _clipsRoot;
    if (root != null && p.isWithin(root, normalized)) {
      return isAudio;
    }

    // Fallback: clips recorded/imported by this app always live under /clips/.
    if (lower.contains('${p.separator}clips${p.separator}') && isAudio) {
      return true;
    }
    return false;
  }

  static bool isAllowedImportExtension(String sourcePath) {
    final ext = p.extension(sourcePath).toLowerCase();
    return ext == '.mp3' || ext == '.m4a';
  }
}
