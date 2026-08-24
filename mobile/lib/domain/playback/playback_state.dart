import 'package:equatable/equatable.dart';

enum PlaybackPriority {
  inactive,
  sleepOrPrayer,
  scheduled,
  manual,
}

enum AppPlaybackState {
  inactive,
  activeIdle,
  manualPlaying,
  scheduledPlaying,
  sleepPaused,
  prayerPaused,
}

class PlaybackSnapshot extends Equatable {
  const PlaybackSnapshot({
    required this.state,
    this.playlistId,
    this.playlistName,
    this.clipTitle,
    this.isPlaying = false,
    this.shuffleEnabled = false,
    this.modalVisible = false,
    this.durationMs = 0,
  });

  final AppPlaybackState state;
  final String? playlistId;
  final String? playlistName;
  final String? clipTitle;
  final bool isPlaying;
  final bool shuffleEnabled;
  final bool modalVisible;

  /// Known clip length from the DB / native probe. The mini-player prefers
  /// this over just_audio's durationStream during source swaps, because the
  /// silence keep-alive is a 10-second WAV and briefly leaks into the
  /// duration stream between clips (QA: "next flashes 0:10").
  final int durationMs;

  bool get canPlay =>
      state == AppPlaybackState.activeIdle ||
      state == AppPlaybackState.manualPlaying ||
      state == AppPlaybackState.scheduledPlaying;

  /// True when the Spotify-style mini-player should occupy shell space.
  /// Shared by [MainShell] and [MiniPlayerBar] so layout reserve and
  /// visibility never disagree.
  ///
  /// Contract (Round 50/52): the bar stays visible for the whole clip session
  /// (playing or paused) until dismiss/stop/inactive. It must never vanish
  /// mid next/prev, after pause, or while MediaSession still owns a clip.
  bool showsMiniPlayer({
    bool nativeActive = false,
    bool dartClipActive = false,
    bool hasMediaSessionClip = false,
  }) {
    if (modalVisible) return false;
    if (state == AppPlaybackState.inactive) return false;
    // Whole clip session (playing or paused) keeps the Spotify bar up.
    if (state == AppPlaybackState.manualPlaying ||
        state == AppPlaybackState.scheduledPlaying) {
      return true;
    }
    if (nativeActive || dartClipActive || hasMediaSessionClip || isPlaying) {
      return true;
    }
    // Keep the bar during handoff / skip gaps when we still know what was
    // playing — vanishing mid next/prev is the Round 59 visibility bug.
    if (clipTitle != null || playlistName != null) return true;
    return false;
  }

  PlaybackSnapshot copyWith({
    AppPlaybackState? state,
    String? playlistId,
    String? playlistName,
    String? clipTitle,
    bool? isPlaying,
    bool? shuffleEnabled,
    bool? modalVisible,
    int? durationMs,
  }) {
    return PlaybackSnapshot(
      state: state ?? this.state,
      playlistId: playlistId ?? this.playlistId,
      playlistName: playlistName ?? this.playlistName,
      clipTitle: clipTitle ?? this.clipTitle,
      isPlaying: isPlaying ?? this.isPlaying,
      shuffleEnabled: shuffleEnabled ?? this.shuffleEnabled,
      modalVisible: modalVisible ?? this.modalVisible,
      durationMs: durationMs ?? this.durationMs,
    );
  }

  @override
  List<Object?> get props => [
        state,
        playlistId,
        playlistName,
        clipTitle,
        isPlaying,
        shuffleEnabled,
        modalVisible,
        durationMs,
      ];
}
