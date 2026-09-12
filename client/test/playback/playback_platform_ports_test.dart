import 'package:arion_client/playback/audio_interruption_port.dart';
import 'package:arion_client/playback/audio_player_port.dart';
import 'package:arion_client/playback/system_media_port.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  test('recording media port observes state and injects commands', () async {
    final port = RecordingSystemMediaPort();
    final commands = <SystemMediaCommand>[];
    final subscription = port.commands.listen(commands.add);
    final queue = <SystemMediaItem>[
      const SystemMediaItem(
        id: 'entry-1',
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        duration: Duration(minutes: 2),
      ),
    ];

    await port.publish(
      SystemMediaSnapshot(
        queue: queue,
        currentIndex: 0,
        processingState: AudioProcessingState.ready,
        playing: true,
        position: const Duration(seconds: 4),
        repeatMode: SystemMediaRepeatMode.all,
        canGoPrevious: true,
        canGoNext: false,
        canPlay: false,
        canPause: true,
        canSeek: true,
      ),
    );
    queue.clear();
    port.send(
      const SystemMediaCommand(
        SystemMediaCommandType.seek,
        position: Duration(seconds: 30),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(port.published.single.queue, hasLength(1));
    expect(port.published.single.currentItem?.id, 'entry-1');
    expect(commands.single.type, SystemMediaCommandType.seek);
    expect(commands.single.position, const Duration(seconds: 30));

    await subscription.cancel();
    await port.dispose();
  });

  test('interruption fake injects focus and noisy events', () async {
    final port = FakeAudioInterruptionPort();
    final interruptions = <AudioInterruptionKind>[];
    var noisyEvents = 0;
    final interruptionSubscription = port.interruptions.listen(
      interruptions.add,
    );
    final noisySubscription = port.becomingNoisy.listen((_) => noisyEvents++);

    await port.configureForMusic();
    port.sendInterruption(AudioInterruptionKind.transientLoss);
    port.sendInterruption(AudioInterruptionKind.transientGain);
    port.sendBecomingNoisy();
    await Future<void>.delayed(Duration.zero);

    expect(port.configureCalls, 1);
    expect(interruptions, [
      AudioInterruptionKind.transientLoss,
      AudioInterruptionKind.transientGain,
    ]);
    expect(noisyEvents, 1);

    await interruptionSubscription.cancel();
    await noisySubscription.cancel();
    await port.dispose();
  });
}
