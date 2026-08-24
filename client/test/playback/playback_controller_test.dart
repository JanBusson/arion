import 'package:arion_client/playback/audio_player_port.dart';
import 'package:arion_client/playback/playback_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  test('loads, starts, pauses, and resumes a selected track', () async {
    final player = FakeAudioPlayer();
    final controller = PlaybackController(player);
    final track = sampleTrack();

    await controller.selectAndPlay(
      track,
      Uri.parse('http://arion.test/audio/1'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.track, same(track));
    expect(player.currentUrl.toString(), 'http://arion.test/audio/1');
    expect(player.playCalls, 1);

    await controller.togglePlayback();
    await Future<void>.delayed(Duration.zero);
    expect(player.pauseCalls, 1);
    await controller.togglePlayback();
    expect(player.playCalls, 2);
  });

  test('reports buffering and clamps position and seeks', () async {
    final player = FakeAudioPlayer()
      ..sourceDuration = const Duration(seconds: 10);
    final controller = PlaybackController(player);
    await controller.selectAndPlay(
      sampleTrack(durationMs: 20000),
      Uri.parse('http://arion.test/audio/1'),
    );

    player.processing.add(AudioProcessingState.buffering);
    player.positions.add(const Duration(seconds: 12));
    await Future<void>.delayed(Duration.zero);
    expect(controller.isBuffering, isTrue);
    expect(controller.position, const Duration(seconds: 10));

    await controller.seek(const Duration(seconds: 30));
    expect(player.lastSeek, const Duration(seconds: 10));
  });

  test('replays completed audio from the beginning', () async {
    final player = FakeAudioPlayer();
    final controller = PlaybackController(player);
    await controller.selectAndPlay(
      sampleTrack(),
      Uri.parse('http://arion.test/audio/1'),
    );
    player.processing.add(AudioProcessingState.completed);
    await Future<void>.delayed(Duration.zero);

    await controller.togglePlayback();

    expect(player.lastSeek, Duration.zero);
    expect(player.playCalls, 2);
  });

  test('replaces the source and resets visible position', () async {
    final player = FakeAudioPlayer();
    final controller = PlaybackController(player);
    await controller.selectAndPlay(
      sampleTrack(),
      Uri.parse('http://arion.test/audio/1'),
    );
    player.positions.add(const Duration(seconds: 30));
    await Future<void>.delayed(Duration.zero);

    final next = sampleTrack(id: '2', title: 'Second');
    await controller.selectAndPlay(
      next,
      Uri.parse('http://arion.test/audio/2'),
    );

    expect(controller.track, same(next));
    expect(controller.position, Duration.zero);
    expect(player.currentUrl.toString(), 'http://arion.test/audio/2');
  });

  test('preserves selection on failure and retries', () async {
    final player = FakeAudioPlayer()..setUrlError = StateError('private');
    final controller = PlaybackController(player);
    final track = sampleTrack();

    await controller.selectAndPlay(
      track,
      Uri.parse('http://arion.test/audio/1'),
    );
    expect(controller.track, same(track));
    expect(controller.error, 'This track could not be played.');

    player.setUrlError = null;
    await controller.retry();
    expect(controller.error, isNull);
    expect(player.playCalls, 1);
  });
}
