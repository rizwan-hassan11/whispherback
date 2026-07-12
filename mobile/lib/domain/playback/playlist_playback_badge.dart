import 'package:equatable/equatable.dart';

import '../../domain/playback/playback_state.dart';

/// Minimal playback fields list screens need — avoids rebuilding entire
/// scroll views when unrelated snapshot fields change.
class PlaylistPlaybackBadge extends Equatable {
  const PlaylistPlaybackBadge({this.playlistId, this.isPlaying = false});

  final String? playlistId;
  final bool isPlaying;

  factory PlaylistPlaybackBadge.fromSnapshot(PlaybackSnapshot? snapshot) {
    if (snapshot == null) return const PlaylistPlaybackBadge();
    final inContext = snapshot.state == AppPlaybackState.manualPlaying ||
        snapshot.state == AppPlaybackState.scheduledPlaying;
    return PlaylistPlaybackBadge(
      playlistId: snapshot.playlistId,
      isPlaying: inContext && snapshot.isPlaying,
    );
  }

  bool isActiveFor(String playlistId) =>
      this.playlistId == playlistId && isPlaying;

  @override
  List<Object?> get props => [playlistId, isPlaying];
}

/// Cover metadata for mini-player — stable across position ticks.
class PlaylistCoverMeta extends Equatable {
  const PlaylistCoverMeta({
    required this.paletteIndex,
    required this.hasSchedule,
  });

  final int paletteIndex;
  final bool hasSchedule;

  @override
  List<Object?> get props => [paletteIndex, hasSchedule];
}
