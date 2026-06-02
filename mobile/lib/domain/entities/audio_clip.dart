import 'package:equatable/equatable.dart';

enum ClipSource { recorded, imported }

class AudioClip extends Equatable {
  const AudioClip({
    required this.id,
    required this.title,
    required this.filePath,
    required this.durationMs,
    required this.createdAt,
    required this.source,
  });

  final String id;
  final String title;
  final String filePath;
  final int durationMs;
  final DateTime createdAt;
  final ClipSource source;

  String get durationLabel {
    final totalSec = durationMs ~/ 1000;
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    return '${m.toString().padLeft(1, '0')}:${s.toString().padLeft(2, '0')}';
  }

  AudioClip copyWith({
    String? title,
    String? filePath,
    int? durationMs,
  }) {
    return AudioClip(
      id: id,
      title: title ?? this.title,
      filePath: filePath ?? this.filePath,
      durationMs: durationMs ?? this.durationMs,
      createdAt: createdAt,
      source: source,
    );
  }

  @override
  List<Object?> get props =>
      [id, title, filePath, durationMs, createdAt, source];
}
