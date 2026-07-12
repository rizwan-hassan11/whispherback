import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/layout/shell_messenger.dart';
import '../../core/ux/tap_feedback.dart';
import '../../data/repositories/playlist_repository.dart';
import '../../domain/playback/playback_state.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/playback_providers.dart';
import '../../providers/repository_providers.dart';
import '../../services/notifications/notification_sync.dart';

Future<void> renamePlaylistDialog(
  BuildContext context,
  WidgetRef ref, {
  required String playlistId,
  required String currentName,
}) async {
  final l10n = context.l10n;
  final controller = TextEditingController(text: currentName);
  final newName = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.renamePlaylist),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: l10n.playlistName),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: Text(l10n.save),
        ),
      ],
    ),
  );
  if (newName == null || newName.isEmpty || newName == currentName) return;
  try {
    await ref.read(playlistRepositoryProvider).rename(playlistId, newName);
    ref.invalidate(playlistsProvider);
    if (context.mounted) {
      context.showShellSnackBar(l10n.playlistRenamed);
    }
  } on DuplicatePlaylistNameException {
    if (context.mounted) {
      context.showShellSnackBar(l10n.playlistNameTaken(newName));
    }
  }
}

Future<void> deletePlaylistDialog(
  BuildContext context,
  WidgetRef ref, {
  required String playlistId,
  required String playlistName,
}) async {
  final l10n = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.deletePlaylist),
      content: Text(l10n.deletePlaylistConfirm),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.delete),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  final coordinator = ref.read(playbackCoordinatorProvider);
  if (coordinator.snapshot.playlistId == playlistId) {
    await coordinator.stop();
  }

  final deleted =
      await ref.read(playlistRepositoryProvider).delete(playlistId);
  if (!context.mounted) return;
  if (!deleted) {
    context.showShellSnackBar(l10n.deletePlaylistBlocked);
    return;
  }
  ref.invalidate(playlistsProvider);
  if (!context.mounted) return;
  await syncWhisperNotifications(
    appState: ref.read(appStateRepositoryProvider),
    schedules: ref.read(scheduleRepositoryProvider),
  );
  if (!context.mounted) return;
  context.showShellSnackBar(l10n.playlistDeleted);
}

Future<void> togglePlaylistFavourite(
  WidgetRef ref, {
  required String playlistId,
  required bool favourite,
}) async {
  selectionHaptic();
  await ref
      .read(playlistRepositoryProvider)
      .setFavourite(playlistId, favourite);
  ref.invalidate(playlistsProvider);
}

Future<void> togglePlaylistPlayPause(
  BuildContext context,
  WidgetRef ref, {
  required String playlistId,
  required PlaybackSnapshot? snapshot,
}) async {
  tapHaptic();
  final coordinator = ref.read(playbackCoordinatorProvider);
  final isThisPlaylist = snapshot?.playlistId == playlistId;
  final playing = isThisPlaylist &&
      (snapshot?.isPlaying ?? false) &&
      (snapshot?.state == AppPlaybackState.manualPlaying ||
          snapshot?.state == AppPlaybackState.scheduledPlaying);

  if (playing) {
    unawaited(coordinator.pause().catchError((_) {}));
    return;
  }
  if (isThisPlaylist && snapshot != null && !snapshot.isPlaying) {
    unawaited(coordinator.resume().catchError((_) {}));
    return;
  }
  unawaited(
    coordinator.playPlaylist(playlistId).catchError((_) => false),
  );
}
