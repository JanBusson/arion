import 'dart:async';

import 'package:arion_client/playback/audio_player_port.dart';
import 'package:arion_client/playback/playback_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  test('does not publish a track before its source finishes loading', () async {
    final load = Completer<Duration?>();
    final player = FakeAudioPlayer()..setUrlHandler = (_, _) => load.future;
    final controller = PlaybackController(player);
    final track = sampleTrack();

    final selection = controller.selectAndPlay(
      track,
      Uri.parse('http://arion.test/audio/1'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.track, isNull);
    expect(controller.isBuffering, isTrue);

    load.complete(const Duration(minutes: 2));
    await selection;
    expect(controller.track, same(track));
  });

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

  test('replaces a paused source without resuming the old track', () async {
    final player = FakeAudioPlayer();
    final controller = PlaybackController(player);
    await controller.selectAndPlay(
      sampleTrack(),
      Uri.parse('http://arion.test/audio/1'),
    );
    await Future<void>.delayed(Duration.zero);
    await controller.togglePlayback();

    final next = sampleTrack(id: '2', title: 'Second', durationMs: 240000);
    player.sourceDuration = const Duration(minutes: 4);
    await controller.selectAndPlay(
      next,
      Uri.parse('http://arion.test/audio/2'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.track, same(next));
    expect(controller.effectiveDuration, const Duration(minutes: 4));
    expect(player.currentUrl.toString(), 'http://arion.test/audio/2');
    expect(player.playCalls, 2);
  });

  test('only the newest rapid selection can become active', () async {
    final loads = <String, Completer<Duration?>>{
      for (final id in ['1', '2', '3']) id: Completer<Duration?>(),
    };
    final player = FakeAudioPlayer()
      ..setUrlHandler = (uri, _) => loads[uri.pathSegments.last]!.future;
    final controller = PlaybackController(player);
    final first = sampleTrack(id: '1', title: 'First');
    final second = sampleTrack(id: '2', title: 'Second');
    final third = sampleTrack(id: '3', title: 'Third');

    final selectFirst = controller.selectAndPlay(
      first,
      Uri.parse('http://arion.test/audio/1'),
    );
    final selectSecond = controller.selectAndPlay(
      second,
      Uri.parse('http://arion.test/audio/2'),
    );
    final selectThird = controller.selectAndPlay(
      third,
      Uri.parse('http://arion.test/audio/3'),
    );

    expect(controller.track, isNull);
    expect(controller.requestedTrack, same(third));
    loads['3']!.complete(const Duration(minutes: 3));
    await selectThird;
    loads['1']!.complete(const Duration(minutes: 1));
    loads['2']!.complete(const Duration(minutes: 2));
    await Future.wait([selectFirst, selectSecond]);
    await Future<void>.delayed(Duration.zero);

    expect(controller.track, same(third));
    expect(controller.effectiveDuration, const Duration(minutes: 3));
    expect(player.currentUrl.toString(), 'http://arion.test/audio/3');
    expect(player.playCalls, 1);
  });

  test('ignores old player events while a replacement is loading', () async {
    final replacement = Completer<Duration?>();
    final player = FakeAudioPlayer();
    final controller = PlaybackController(player);
    await controller.selectAndPlay(
      sampleTrack(),
      Uri.parse('http://arion.test/audio/1'),
    );
    player.setUrlHandler = (_, _) => replacement.future;

    final selection = controller.selectAndPlay(
      sampleTrack(id: '2', title: 'Second'),
      Uri.parse('http://arion.test/audio/2'),
    );
    player.positions.add(const Duration(seconds: 99));
    player.durations.add(const Duration(minutes: 9));
    player.processing.add(AudioProcessingState.completed);
    await Future<void>.delayed(Duration.zero);

    expect(controller.position, Duration.zero);
    expect(controller.effectiveDuration, Duration.zero);
    expect(controller.isCompleted, isFalse);

    replacement.complete(const Duration(minutes: 2));
    await selection;
    expect(controller.effectiveDuration, const Duration(minutes: 2));
  });

  test('times out a stalled load and retries with a fresh request', () async {
    final stalled = Completer<Duration?>();
    final player = FakeAudioPlayer()
      ..setUrlHandler = (_, call) => call == 1
          ? stalled.future
          : Future<Duration?>.value(const Duration(minutes: 4));
    final controller = PlaybackController(
      player,
      sourceLoadTimeout: const Duration(milliseconds: 5),
    );
    final track = sampleTrack();

    await controller.selectAndPlay(
      track,
      Uri.parse('http://arion.test/audio/1'),
    );
    expect(controller.track, isNull);
    expect(controller.requestedTrack, same(track));
    expect(controller.error, 'This track could not be played.');

    await controller.retry();
    await Future<void>.delayed(Duration.zero);
    expect(controller.track, same(track));
    expect(controller.requestedTrack, isNull);
    expect(controller.error, isNull);
    expect(player.setUrlCalls, 2);
  });

  test('preserves selection on failure and retries', () async {
    final player = FakeAudioPlayer()..setUrlError = StateError('private');
    final controller = PlaybackController(player);
    final track = sampleTrack();

    await controller.selectAndPlay(
      track,
      Uri.parse('http://arion.test/audio/1'),
    );
    expect(controller.track, isNull);
    expect(controller.requestedTrack, same(track));
    expect(controller.error, 'This track could not be played.');

    player.setUrlError = null;
    await controller.retry();
    expect(controller.error, isNull);
    expect(player.playCalls, 1);
  });
}
