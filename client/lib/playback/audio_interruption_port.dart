enum AudioInterruptionKind { transientLoss, transientGain, permanentLoss }

abstract interface class AudioInterruptionPort {
  Stream<AudioInterruptionKind> get interruptions;
  Stream<void> get becomingNoisy;

  Future<void> configureForMusic();
  Future<void> dispose();
}

final class NoopAudioInterruptionPort implements AudioInterruptionPort {
  const NoopAudioInterruptionPort();

  @override
  Stream<AudioInterruptionKind> get interruptions => const Stream.empty();

  @override
  Stream<void> get becomingNoisy => const Stream.empty();

  @override
  Future<void> configureForMusic() async {}

  @override
  Future<void> dispose() async {}
}
