enum AudioProcessingState { idle, loading, buffering, ready, completed }

abstract interface class AudioPlayerPort {
  Stream<bool> get playingStream;
  Stream<AudioProcessingState> get processingStateStream;
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<Object> get errorStream;

  Future<Duration?> setUrl(Uri uri);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> dispose();
}
