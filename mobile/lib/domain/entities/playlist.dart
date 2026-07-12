import 'package:equatable/equatable.dart';

class Playlist extends Equatable {
  const Playlist({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.shuffleEnabled = false,
    this.isFavourite = false,
    this.clipCount = 0,
    this.totalDurationMs = 0,
    this.hasSchedule = false,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool shuffleEnabled;
  final bool isFavourite;
  final int clipCount;
  final int totalDurationMs;
  final bool hasSchedule;

  Playlist copyWith({
    String? name,
    bool? shuffleEnabled,
    bool? isFavourite,
    int? clipCount,
    int? totalDurationMs,
    bool? hasSchedule,
    DateTime? updatedAt,
  }) {
    return Playlist(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      shuffleEnabled: shuffleEnabled ?? this.shuffleEnabled,
      isFavourite: isFavourite ?? this.isFavourite,
      clipCount: clipCount ?? this.clipCount,
      totalDurationMs: totalDurationMs ?? this.totalDurationMs,
      hasSchedule: hasSchedule ?? this.hasSchedule,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        createdAt,
        updatedAt,
        shuffleEnabled,
        isFavourite,
        clipCount,
        totalDurationMs,
        hasSchedule,
      ];
}
