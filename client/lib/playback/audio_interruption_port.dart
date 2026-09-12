enum AudioInterruptionKind { transientLoss, transientGain, permanentLoss }

abstract interface class AudioInterruptionPort {
  Stream<AudioInterruptionKind> get interruptions;
  Stream<void> get becomingNoisy;

  Future<void> configureForMusic();
  Future<void> dispose();
}
