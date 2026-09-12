import 'dart:async';

import 'package:audio_session/audio_session.dart' as audio_session;

import 'audio_interruption_port.dart';

final class AudioSessionInterruptionPort implements AudioInterruptionPort {
  final StreamController<AudioInterruptionKind> _interruptions =
      StreamController.broadcast();
  final StreamController<void> _becomingNoisy = StreamController.broadcast();
  StreamSubscription<audio_session.AudioInterruptionEvent>?
  _interruptionSubscription;
  StreamSubscription<void>? _noisySubscription;

  @override
  Stream<AudioInterruptionKind> get interruptions => _interruptions.stream;

  @override
  Stream<void> get becomingNoisy => _becomingNoisy.stream;

  @override
  Future<void> configureForMusic() async {
    final session = await audio_session.AudioSession.instance;
    await session.configure(
      const audio_session.AudioSessionConfiguration.music(),
    );
    await _interruptionSubscription?.cancel();
    await _noisySubscription?.cancel();
    _interruptionSubscription = session.interruptionEventStream.listen((event) {
      final mapped = mapAudioSessionInterruption(event);
      if (mapped != null) _interruptions.add(mapped);
    });
    _noisySubscription = session.becomingNoisyEventStream.listen(
      (_) => _becomingNoisy.add(null),
    );
  }

  @override
  Future<void> dispose() async {
    await _interruptionSubscription?.cancel();
    await _noisySubscription?.cancel();
    await _interruptions.close();
    await _becomingNoisy.close();
  }
}

AudioInterruptionKind? mapAudioSessionInterruption(
  audio_session.AudioInterruptionEvent event,
) {
  if (event.begin) {
    return event.type == audio_session.AudioInterruptionType.unknown
        ? AudioInterruptionKind.permanentLoss
        : AudioInterruptionKind.transientLoss;
  }
  return event.type == audio_session.AudioInterruptionType.unknown
      ? null
      : AudioInterruptionKind.transientGain;
}
