import 'audio_player_port.dart';

enum SystemMediaRepeatMode { none, all, one }

enum SystemMediaCommandType {
  play,
  pause,
  seek,
  seekForward,
  seekBackward,
  previous,
  next,
  setRepeat,
}

final class SystemMediaCommand {
  const SystemMediaCommand(this.type, {this.position, this.repeatMode});

  final SystemMediaCommandType type;
  final Duration? position;
  final SystemMediaRepeatMode? repeatMode;
}

final class SystemMediaItem {
  const SystemMediaItem({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    this.artworkUri,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final Uri? artworkUri;
}

final class SystemMediaSnapshot {
  SystemMediaSnapshot({
    required List<SystemMediaItem> queue,
    required this.currentIndex,
    required this.processingState,
    required this.playing,
    required this.position,
    required this.repeatMode,
    required this.canGoPrevious,
    required this.canGoNext,
    required this.canPlay,
    required this.canPause,
    required this.canSeek,
  }) : queue = List<SystemMediaItem>.unmodifiable(queue);

  final List<SystemMediaItem> queue;
  final int? currentIndex;
  final AudioProcessingState processingState;
  final bool playing;
  final Duration position;
  final SystemMediaRepeatMode repeatMode;
  final bool canGoPrevious;
  final bool canGoNext;
  final bool canPlay;
  final bool canPause;
  final bool canSeek;

  SystemMediaItem? get currentItem =>
      currentIndex == null || currentIndex! < 0 || currentIndex! >= queue.length
      ? null
      : queue[currentIndex!];
}

abstract interface class SystemMediaPort {
  Stream<SystemMediaCommand> get commands;

  Future<void> publish(SystemMediaSnapshot snapshot);
  Future<void> clear();
  Future<void> dispose();
}

final class NoopSystemMediaPort implements SystemMediaPort {
  const NoopSystemMediaPort();

  @override
  Stream<SystemMediaCommand> get commands => const Stream.empty();

  @override
  Future<void> publish(SystemMediaSnapshot snapshot) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<void> dispose() async {}
}
