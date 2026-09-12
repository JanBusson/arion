import 'dart:async';

import 'package:arion_client/playback/audio_player_port.dart';
import 'package:arion_client/playback/playback_controller.dart';
import 'package:arion_client/playback/playback_recovery_policy.dart';
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
    final player = FakeAudioPlayer(emulateJustAudioCompletionState: true);
    final controller = PlaybackController(player);
    await controller.selectAndPlay(
      sampleTrack(),
      Uri.parse('http://arion.test/audio/1'),
    );
    player.processing.add(AudioProcessingState.completed);
    await Future<void>.delayed(Duration.zero);

    await controller.togglePlayback();
    await Future<void>.delayed(Duration.zero);

    expect(player.lastSeek, Duration.zero);
    expect(player.playCalls, 2);
    expect(player.playbackStarts, 2);
    expect(player.transportCommands, ['play', 'pause', 'seek:0', 'play']);
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
    expect(player.setUrlCalls, 2);
  });

  test('keeps owner playback intent separate from engine output', () async {
    final player = FakeAudioPlayer();
    final controller = PlaybackController(
      player,
      recoveryPolicy: const PlaybackRecoveryPolicy(
        retryDelays: [Duration.zero],
        attemptTimeout: Duration(seconds: 1),
      ),
    );

    await controller.selectAndPlay(
      sampleTrack(),
      Uri.parse('http://arion.test/audio/1'),
    );
    await Future<void>.delayed(Duration.zero);
    player.playing.add(false);
    await Future<void>.delayed(Duration.zero);

    expect(controller.isPlaying, isFalse);
    expect(controller.isPlaybackRequested, isTrue);

    await controller.pause();
    expect(controller.isPlaybackRequested, isFalse);
    expect(player.pauseCalls, 1);
  });

  test(
    'recovers the same queue entry at its last confirmed position',
    () async {
      final player = FakeAudioPlayer();
      final delays = <Duration>[];
      final controller = PlaybackController(
        player,
        recoveryPolicy: const PlaybackRecoveryPolicy(
          retryDelays: [Duration.zero],
          attemptTimeout: Duration(seconds: 1),
        ),
        recoveryDelay: (delay) async => delays.add(delay),
      );
      final first = sampleTrack(id: '1');
      await controller.playNow(first, Uri.parse('http://arion.test/audio/1'));
      await controller.addToQueue(
        sampleTrack(id: '2'),
        Uri.parse('http://arion.test/audio/2'),
      );
      controller.setRepeatMode(PlaybackRepeatMode.current);
      player.positions.add(const Duration(seconds: 42));
      await Future<void>.delayed(Duration.zero);

      player.errors.add(StateError('network lost'));
      await _waitUntil(
        () => player.setUrlCalls == 2 && !controller.isReconnecting,
      );

      expect(delays, [Duration.zero]);
      expect(controller.currentEntry!.track, same(first));
      expect(controller.queueEntries, hasLength(2));
      expect(controller.repeatMode, PlaybackRepeatMode.current);
      expect(controller.position, const Duration(seconds: 42));
      expect(player.lastSeek, const Duration(seconds: 42));
      expect(player.requestedUrls, [
        Uri.parse('http://arion.test/audio/1'),
        Uri.parse('http://arion.test/audio/1'),
      ]);
      expect(player.playbackStarts, 2);
      expect(controller.error, isNull);
    },
  );

  test(
    'pause cancels delayed recovery and prevents automatic resume',
    () async {
      final delay = Completer<void>();
      final player = FakeAudioPlayer();
      final controller = PlaybackController(
        player,
        recoveryPolicy: const PlaybackRecoveryPolicy(
          retryDelays: [Duration(seconds: 1)],
          attemptTimeout: Duration(seconds: 1),
        ),
        recoveryDelay: (_) => delay.future,
      );
      await controller.playNow(
        sampleTrack(),
        Uri.parse('http://arion.test/audio/1'),
      );
      await Future<void>.delayed(Duration.zero);

      player.errors.add(StateError('network lost'));
      await Future<void>.delayed(Duration.zero);
      expect(controller.isReconnecting, isTrue);
      expect(controller.isPlaying, isTrue);

      await controller.pause();
      delay.complete();
      await Future<void>.delayed(Duration.zero);

      expect(controller.isReconnecting, isFalse);
      expect(controller.isPlaybackRequested, isFalse);
      expect(player.setUrlCalls, 1);
      expect(player.playbackStarts, 1);
    },
  );

  test('in-flight recovery cannot replace a newer selection', () async {
    final recoveryLoad = Completer<Duration?>();
    final player = FakeAudioPlayer()
      ..setUrlHandler = (uri, call) {
        if (call == 2) return recoveryLoad.future;
        return Future<Duration?>.value(const Duration(minutes: 3));
      };
    final controller = PlaybackController(
      player,
      recoveryPolicy: const PlaybackRecoveryPolicy(
        retryDelays: [Duration.zero],
        attemptTimeout: Duration(seconds: 1),
      ),
      recoveryDelay: (_) async {},
    );
    await controller.playNow(
      sampleTrack(id: '1'),
      Uri.parse('http://arion.test/audio/1'),
    );
    player.positions.add(const Duration(seconds: 25));
    await Future<void>.delayed(Duration.zero);
    player.errors.add(StateError('network lost'));
    await _waitUntil(() => player.setUrlCalls == 2);

    final second = sampleTrack(id: '2', title: 'Second');
    await controller.playNow(second, Uri.parse('http://arion.test/audio/2'));
    recoveryLoad.complete(const Duration(minutes: 3));
    await Future<void>.delayed(Duration.zero);

    expect(controller.track, same(second));
    expect(controller.currentEntry!.track, same(second));
    expect(controller.position, Duration.zero);
    expect(player.currentUrl, Uri.parse('http://arion.test/audio/2'));
    expect(player.lastSeek, isNull);
    expect(player.playbackStarts, 2);
  });

  test('manual retry supersedes an in-flight automatic recovery', () async {
    final recoveryLoad = Completer<Duration?>();
    final player = FakeAudioPlayer()
      ..setUrlHandler = (_, call) {
        if (call == 2) return recoveryLoad.future;
        return Future<Duration?>.value(const Duration(minutes: 3));
      };
    final controller = PlaybackController(
      player,
      recoveryPolicy: const PlaybackRecoveryPolicy(
        retryDelays: [Duration.zero],
        attemptTimeout: Duration(seconds: 1),
      ),
      recoveryDelay: (_) async {},
    );
    await controller.playNow(
      sampleTrack(),
      Uri.parse('http://arion.test/audio/1'),
    );
    player.errors.add(StateError('network lost'));
    await _waitUntil(() => player.setUrlCalls == 2);

    await controller.retry();
    recoveryLoad.complete(const Duration(minutes: 3));
    await Future<void>.delayed(Duration.zero);

    expect(player.setUrlCalls, 3);
    expect(player.playbackStarts, 2);
    expect(controller.isReconnecting, isFalse);
    expect(controller.error, isNull);
  });

  test('dispose cancels a delayed automatic recovery', () async {
    final delay = Completer<void>();
    final player = FakeAudioPlayer();
    final controller = PlaybackController(
      player,
      recoveryPolicy: const PlaybackRecoveryPolicy(
        retryDelays: [Duration(seconds: 1)],
        attemptTimeout: Duration(seconds: 1),
      ),
      recoveryDelay: (_) => delay.future,
    );
    await controller.playNow(
      sampleTrack(),
      Uri.parse('http://arion.test/audio/1'),
    );
    player.errors.add(StateError('network lost'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.isReconnecting, isTrue);

    controller.dispose();
    delay.complete();
    await Future<void>.delayed(Duration.zero);

    expect(player.setUrlCalls, 1);
    expect(player.disposed, isTrue);
  });

  test(
    'exhausts bounded recovery then supports a fresh manual retry',
    () async {
      var failRecovery = true;
      final player = FakeAudioPlayer()
        ..setUrlHandler = (_, call) async {
          if (call > 1 && failRecovery) throw StateError('offline');
          return const Duration(minutes: 3);
        };
      final controller = PlaybackController(
        player,
        recoveryPolicy: const PlaybackRecoveryPolicy(
          retryDelays: [Duration.zero, Duration(seconds: 1)],
          attemptTimeout: Duration(seconds: 1),
        ),
        recoveryDelay: (_) async {},
      );
      await controller.playNow(
        sampleTrack(),
        Uri.parse('http://arion.test/audio/1'),
      );
      player.errors.add(StateError('network lost'));
      await _waitUntil(() => controller.error != null);

      expect(player.setUrlCalls, 3);
      expect(controller.isReconnecting, isFalse);
      expect(controller.error, 'This track could not be played.');

      failRecovery = false;
      await controller.retry();
      await Future<void>.delayed(Duration.zero);
      expect(player.setUrlCalls, 4);
      expect(controller.error, isNull);
      expect(controller.isPlaybackRequested, isTrue);
      expect(player.playbackStarts, 2);
    },
  );

  test('bounds each stalled recovery attempt with a timeout', () async {
    final stalledLoads = <Completer<Duration?>>[];
    final player = FakeAudioPlayer()
      ..setUrlHandler = (_, call) {
        if (call == 1) {
          return Future<Duration?>.value(const Duration(minutes: 3));
        }
        final stalled = Completer<Duration?>();
        stalledLoads.add(stalled);
        return stalled.future;
      };
    final controller = PlaybackController(
      player,
      recoveryPolicy: const PlaybackRecoveryPolicy(
        retryDelays: [Duration.zero, Duration.zero],
        attemptTimeout: Duration(milliseconds: 5),
      ),
      recoveryDelay: (_) async {},
    );
    await controller.playNow(
      sampleTrack(),
      Uri.parse('http://arion.test/audio/1'),
    );
    player.errors.add(StateError('network lost'));
    await _waitUntil(() => controller.error != null);

    expect(stalledLoads, hasLength(2));
    expect(player.setUrlCalls, 3);
    expect(controller.isReconnecting, isFalse);
    expect(controller.error, 'This track could not be played.');
  });
}

Future<void> _waitUntil(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!predicate() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(predicate(), isTrue);
}
