import 'package:just_audio/just_audio.dart';

final class PlaybackCacheSource {
  const PlaybackCacheSource({
    required this.key,
    required this.source,
    required this.fromCompleteCache,
    required this.completion,
  });

  final String key;
  final AudioSource source;
  final bool fromCompleteCache;
  final Stream<void> completion;
}

abstract interface class PlaybackAudioCache {
  Future<PlaybackCacheSource?> prepare(
    Uri uri, {
    bool bypassCompleteCache = false,
  });

  Future<void> complete(String key);
  Future<void> invalidate(String key);
  Future<void> maintain();
  Future<void> release();
  Future<void> dispose();
}
