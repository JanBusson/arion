import 'package:arion_client/playback/audio_interruption_port.dart';
import 'package:arion_client/playback/audio_player_port.dart';
import 'package:arion_client/playback/audio_service_system_media_port.dart';
import 'package:arion_client/playback/audio_session_interruption_port.dart';
import 'package:arion_client/playback/system_media_port.dart';
import 'package:audio_service/audio_service.dart' as audio_service;
import 'package:audio_session/audio_session.dart' as audio_session;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('audio service adapter maps every processing state', () async {
    final port = AudioServiceSystemMediaPort();
    final expected = {
      AudioProcessingState.idle: audio_service.AudioProcessingState.idle,
      AudioProcessingState.loading: audio_service.AudioProcessingState.loading,
      AudioProcessingState.buffering:
          audio_service.AudioProcessingState.buffering,
      AudioProcessingState.ready: audio_service.AudioProcessingState.ready,
      AudioProcessingState.completed:
          audio_service.AudioProcessingState.completed,
    };

    for (final entry in expected.entries) {
      await port.publish(
        SystemMediaSnapshot(
          queue: const [],
          currentIndex: null,
          processingState: entry.key,
          playing: false,
          position: Duration.zero,
          repeatMode: SystemMediaRepeatMode.none,
          canGoPrevious: false,
          canGoNext: false,
          canPlay: false,
          canPause: false,
          canSeek: false,
        ),
      );
      expect(port.playbackState.value.processingState, entry.value);
      expect(port.playbackState.value.controls, isEmpty);
      expect(port.playbackState.value.queueIndex, isNull);
    }
    await port.dispose();
  });

  test(
    'audio service adapter publishes queue, controls, and repeat state',
    () async {
      final port = AudioServiceSystemMediaPort();
      await port.publish(
        SystemMediaSnapshot(
          queue: [
            SystemMediaItem(
              id: 'arion-entry-1',
              title: 'Song',
              artist: 'Artist',
              album: 'Album',
              duration: const Duration(minutes: 3),
              artworkUri: Uri.parse('http://server/cover/1'),
            ),
          ],
          currentIndex: 0,
          processingState: AudioProcessingState.buffering,
          playing: true,
          position: const Duration(seconds: 12),
          repeatMode: SystemMediaRepeatMode.one,
          canGoPrevious: true,
          canGoNext: false,
          canPlay: false,
          canPause: true,
          canSeek: true,
        ),
      );

      expect(port.queue.value.single.id, 'arion-entry-1');
      expect(port.mediaItem.value?.title, 'Song');
      expect(
        port.playbackState.value.processingState,
        audio_service.AudioProcessingState.buffering,
      );
      expect(port.playbackState.value.playing, isTrue);
      expect(
        port.playbackState.value.updatePosition,
        const Duration(seconds: 12),
      );
      expect(
        port.playbackState.value.repeatMode,
        audio_service.AudioServiceRepeatMode.one,
      );
      expect(port.playbackState.value.controls, [
        audio_service.MediaControl.skipToPrevious,
        audio_service.MediaControl.pause,
      ]);
      expect(
        port.playbackState.value.systemActions,
        containsAll([
          audio_service.MediaAction.seek,
          audio_service.MediaAction.seekForward,
          audio_service.MediaAction.seekBackward,
          audio_service.MediaAction.setRepeatMode,
        ]),
      );

      await port.clear();
      expect(port.queue.value, isEmpty);
      expect(port.mediaItem.value, isNull);
      expect(
        port.playbackState.value.processingState,
        audio_service.AudioProcessingState.idle,
      );
      await port.dispose();
    },
  );

  test('audio service callbacks become platform-neutral commands', () async {
    final port = AudioServiceSystemMediaPort();
    final commands = <SystemMediaCommand>[];
    final subscription = port.commands.listen(commands.add);

    await port.play();
    await port.pause();
    await port.seek(const Duration(seconds: 8));
    await port.fastForward();
    await port.rewind();
    await port.skipToPrevious();
    await port.skipToNext();
    await port.setRepeatMode(audio_service.AudioServiceRepeatMode.all);
    await Future<void>.delayed(Duration.zero);

    expect(commands.map((command) => command.type), [
      SystemMediaCommandType.play,
      SystemMediaCommandType.pause,
      SystemMediaCommandType.seek,
      SystemMediaCommandType.seekForward,
      SystemMediaCommandType.seekBackward,
      SystemMediaCommandType.previous,
      SystemMediaCommandType.next,
      SystemMediaCommandType.setRepeat,
    ]);
    expect(commands[2].position, const Duration(seconds: 8));
    expect(commands.last.repeatMode, SystemMediaRepeatMode.all);

    await subscription.cancel();
    await port.dispose();
  });

  test('audio session interruption mapping distinguishes resume safety', () {
    expect(
      mapAudioSessionInterruption(
        audio_session.AudioInterruptionEvent(
          true,
          audio_session.AudioInterruptionType.pause,
        ),
      ),
      AudioInterruptionKind.transientLoss,
    );
    expect(
      mapAudioSessionInterruption(
        audio_session.AudioInterruptionEvent(
          false,
          audio_session.AudioInterruptionType.duck,
        ),
      ),
      AudioInterruptionKind.transientGain,
    );
    expect(
      mapAudioSessionInterruption(
        audio_session.AudioInterruptionEvent(
          true,
          audio_session.AudioInterruptionType.unknown,
        ),
      ),
      AudioInterruptionKind.permanentLoss,
    );
    expect(
      mapAudioSessionInterruption(
        audio_session.AudioInterruptionEvent(
          false,
          audio_session.AudioInterruptionType.unknown,
        ),
      ),
      isNull,
    );
  });
}
