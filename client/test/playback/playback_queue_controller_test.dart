import 'dart:async';

import 'package:arion_client/playback/audio_player_port.dart';
import 'package:arion_client/playback/playback_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

Uri audioUri(String id) => Uri.parse('http://arion.test/audio/$id');

Future<void> flushEvents() => Future<void>.delayed(Duration.zero);

void main() {
  test('builds an ordered queue with independent duplicate entries', () async {
    final player = FakeAudioPlayer();
    final controller = PlaybackController(player);
    final first = sampleTrack(id: '1', title: 'First');
    final second = sampleTrack(id: '2', title: 'Second');
    final third = sampleTrack(id: '3', title: 'Third');

    expect(controller.queueEntries, isEmpty);
    expect(controller.currentEntry, isNull);
    expect(controller.currentIndex, -1);
    expect(controller.repeatMode, PlaybackRepeatMode.off);

    await controller.playNow(first, audioUri('1'));
    await controller.addToQueue(third, audioUri('3'));
    await controller.playNext(second, audioUri('2'));
    await controller.addToQueue(first, audioUri('1'));

    expect(controller.queueEntries.map((entry) => entry.track.title), [
      'First',
      'Second',
      'Third',
      'First',
    ]);
    expect(
      controller.queueEntries.map((entry) => entry.id).toSet(),
      hasLength(4),
    );
    expect(controller.currentEntry!.track, same(first));
    expect(controller.upcomingEntries, hasLength(3));
    expect(player.setUrlCalls, 1);
  });

  test(
    'play-now replaces the queue and empty queue actions start playback',
    () async {
      final player = FakeAudioPlayer();
      final controller = PlaybackController(player);
      final first = sampleTrack(id: '1', title: 'First');
      final second = sampleTrack(id: '2', title: 'Second');

      await controller.addToQueue(first, audioUri('1'));
      expect(controller.currentEntry!.track, same(first));
      expect(player.playCalls, 1);

      await controller.addToQueue(second, audioUri('2'));
      await controller.playNow(second, audioUri('2'));
      expect(controller.queueEntries, hasLength(1));
      expect(controller.currentEntry!.track, same(second));
      expect(player.currentUrl, audioUri('2'));
    },
  );

  test('moves and removes upcoming occurrences by entry identity', () async {
    final player = FakeAudioPlayer();
    final controller = PlaybackController(player);
    final first = sampleTrack(id: '1', title: 'First');
    final duplicate = sampleTrack(id: '2', title: 'Duplicate');
    final last = sampleTrack(id: '3', title: 'Last');

    await controller.playNow(first, audioUri('1'));
    await controller.addToQueue(duplicate, audioUri('2'));
    await controller.addToQueue(duplicate, audioUri('2'));
    await controller.addToQueue(last, audioUri('3'));
    final currentId = controller.currentEntry!.id;
    final firstDuplicateId = controller.upcomingEntries[0].id;
    final secondDuplicateId = controller.upcomingEntries[1].id;
    final lastId = controller.upcomingEntries[2].id;

    expect(controller.moveUpcoming(lastId, 0), isTrue);
    expect(controller.upcomingEntries.map((entry) => entry.id), [
      lastId,
      firstDuplicateId,
      secondDuplicateId,
    ]);
    expect(controller.removeUpcoming(secondDuplicateId), isTrue);
    expect(controller.removeUpcoming(currentId), isFalse);
    expect(controller.moveUpcoming(currentId, 0), isFalse);
    expect(controller.upcomingEntries.map((entry) => entry.id), [
      lastId,
      firstDuplicateId,
    ]);
    expect(player.setUrlCalls, 1);
  });

  test(
    'previous uses the three-second threshold and retained history',
    () async {
      final player = FakeAudioPlayer();
      final controller = PlaybackController(player);
      final first = sampleTrack(id: '1', title: 'First');
      final second = sampleTrack(id: '2', title: 'Second');

      await controller.playNow(first, audioUri('1'));
      await controller.addToQueue(second, audioUri('2'));
      expect(controller.canGoPrevious, isFalse);

      await controller.skipToNext();
      player.positions.add(const Duration(seconds: 3));
      await flushEvents();
      await controller.skipToPrevious();
      expect(controller.currentEntry!.track, same(first));

      await controller.skipToNext();
      player.positions.add(const Duration(milliseconds: 3001));
      await flushEvents();
      await controller.skipToPrevious();
      expect(controller.currentEntry!.track, same(second));
      expect(player.lastSeek, Duration.zero);
    },
  );

  test('manual navigation wraps only for repeat-all', () async {
    final player = FakeAudioPlayer();
    final controller = PlaybackController(player);
    final first = sampleTrack(id: '1', title: 'First');
    final second = sampleTrack(id: '2', title: 'Second');

    await controller.playNow(first, audioUri('1'));
    await controller.addToQueue(second, audioUri('2'));
    controller.setRepeatMode(PlaybackRepeatMode.all);

    await controller.skipToPrevious();
    expect(controller.currentEntry!.track, same(second));
    await controller.skipToNext();
    expect(controller.currentEntry!.track, same(first));

    controller.setRepeatMode(PlaybackRepeatMode.current);
    await controller.skipToNext();
    expect(controller.currentEntry!.track, same(second));
    expect(controller.canGoNext, isFalse);
  });

  test('repeat-off advances then leaves the final entry completed', () async {
    final player = FakeAudioPlayer();
    final controller = PlaybackController(player);
    final first = sampleTrack(id: '1', title: 'First');
    final second = sampleTrack(id: '2', title: 'Second');

    await controller.playNow(first, audioUri('1'));
    await controller.addToQueue(second, audioUri('2'));
    player.processing.add(AudioProcessingState.completed);
    await flushEvents();
    expect(controller.currentEntry!.track, same(second));
    expect(player.currentUrl, audioUri('2'));

    player.processing.add(AudioProcessingState.completed);
    await flushEvents();
    expect(controller.currentEntry!.track, same(second));
    expect(controller.isCompleted, isTrue);
    expect(controller.isPlaying, isFalse);
  });

  test('repeat-all advances and wraps after completion', () async {
    final player = FakeAudioPlayer();
    final controller = PlaybackController(player);
    final first = sampleTrack(id: '1', title: 'First');
    final second = sampleTrack(id: '2', title: 'Second');

    await controller.playNow(first, audioUri('1'));
    await controller.addToQueue(second, audioUri('2'));
    controller.setRepeatMode(PlaybackRepeatMode.all);

    player.processing.add(AudioProcessingState.completed);
    await flushEvents();
    expect(controller.currentEntry!.track, same(second));
    player.processing.add(AudioProcessingState.completed);
    await flushEvents();
    expect(controller.currentEntry!.track, same(first));
  });

  test(
    'repeat-current seeks without reloading and ignores duplicate completion',
    () async {
      final player = FakeAudioPlayer();
      final controller = PlaybackController(player);
      final track = sampleTrack(id: '1', title: 'First');
      await controller.playNow(track, audioUri('1'));
      controller.setRepeatMode(PlaybackRepeatMode.current);
      final playCallsBeforeCompletion = player.playCalls;

      player.processing.add(AudioProcessingState.completed);
      player.processing.add(AudioProcessingState.completed);
      await flushEvents();

      expect(controller.currentEntry!.track, same(track));
      expect(player.lastSeek, Duration.zero);
      expect(player.setUrlCalls, 1);
      expect(player.playCalls, playCallsBeforeCompletion + 1);

      player.positions.add(const Duration(seconds: 1));
      await flushEvents();
      player.processing.add(AudioProcessingState.completed);
      await flushEvents();
      expect(player.playCalls, playCallsBeforeCompletion + 2);
    },
  );

  test('repeat mode changes without interrupting playback', () async {
    final player = FakeAudioPlayer();
    final controller = PlaybackController(player);
    await controller.playNow(sampleTrack(), audioUri('1'));
    player.positions.add(const Duration(seconds: 30));
    await flushEvents();
    final setUrlCalls = player.setUrlCalls;
    final playCalls = player.playCalls;

    controller.cycleRepeatMode();
    expect(controller.repeatMode, PlaybackRepeatMode.all);
    controller.cycleRepeatMode();
    expect(controller.repeatMode, PlaybackRepeatMode.current);
    controller.cycleRepeatMode();
    expect(controller.repeatMode, PlaybackRepeatMode.off);
    expect(controller.position, const Duration(seconds: 30));
    expect(player.setUrlCalls, setUrlCalls);
    expect(player.playCalls, playCalls);
  });

  test(
    'failed automatic advancement preserves the queue and can be skipped',
    () async {
      var secondFails = true;
      final player = FakeAudioPlayer()
        ..setUrlHandler = (uri, _) async {
          if (uri.pathSegments.last == '2' && secondFails) {
            throw StateError('private');
          }
          return const Duration(minutes: 3);
        };
      final controller = PlaybackController(player);
      final first = sampleTrack(id: '1', title: 'First');
      final second = sampleTrack(id: '2', title: 'Second');
      final third = sampleTrack(id: '3', title: 'Third');
      await controller.playNow(first, audioUri('1'));
      await controller.addToQueue(second, audioUri('2'));
      await controller.addToQueue(third, audioUri('3'));

      player.processing.add(AudioProcessingState.completed);
      await flushEvents();
      expect(controller.currentEntry!.track, same(second));
      expect(controller.error, 'This track could not be played.');
      expect(controller.upcomingEntries.single.track, same(third));

      secondFails = false;
      await controller.retry();
      expect(controller.track, same(second));
      expect(controller.upcomingEntries.single.track, same(third));

      secondFails = true;
      player.errors.add(StateError('private'));
      await flushEvents();
      await controller.skipToNext();
      expect(controller.currentEntry!.track, same(third));
      expect(controller.error, isNull);
    },
  );

  test(
    'rapid play-now selections keep only the newest queue and source',
    () async {
      final loads = <String, Completer<Duration?>>{
        for (final id in ['1', '2', '3']) id: Completer<Duration?>(),
      };
      final player = FakeAudioPlayer()
        ..setUrlHandler = (uri, _) => loads[uri.pathSegments.last]!.future;
      final controller = PlaybackController(player);

      final first = controller.playNow(
        sampleTrack(id: '1', title: 'First'),
        audioUri('1'),
      );
      final second = controller.playNow(
        sampleTrack(id: '2', title: 'Second'),
        audioUri('2'),
      );
      final third = controller.playNow(
        sampleTrack(id: '3', title: 'Third'),
        audioUri('3'),
      );
      loads['3']!.complete(const Duration(minutes: 3));
      await third;
      loads['1']!.complete(const Duration(minutes: 1));
      loads['2']!.complete(const Duration(minutes: 2));
      await Future.wait([first, second]);

      expect(controller.queueEntries, hasLength(1));
      expect(controller.currentEntry!.track.title, 'Third');
      expect(controller.track!.title, 'Third');
      expect(player.currentUrl, audioUri('3'));
    },
  );

  test(
    'rapid queue navigation keeps the newest requested occurrence current',
    () async {
      final loads = <String, Completer<Duration?>>{
        '2': Completer<Duration?>(),
        '3': Completer<Duration?>(),
      };
      final player = FakeAudioPlayer();
      final controller = PlaybackController(player);
      await controller.playNow(
        sampleTrack(id: '1', title: 'First'),
        audioUri('1'),
      );
      await controller.addToQueue(
        sampleTrack(id: '2', title: 'Second'),
        audioUri('2'),
      );
      await controller.addToQueue(
        sampleTrack(id: '3', title: 'Third'),
        audioUri('3'),
      );
      player.setUrlHandler = (uri, _) => loads[uri.pathSegments.last]!.future;

      final second = controller.skipToNext();
      final third = controller.skipToNext();
      loads['3']!.complete(const Duration(minutes: 3));
      await third;
      loads['2']!.complete(const Duration(minutes: 2));
      await second;

      expect(controller.currentIndex, 2);
      expect(controller.currentEntry!.track.title, 'Third');
      expect(controller.track!.title, 'Third');
      expect(player.currentUrl, audioUri('3'));
      expect(player.playCalls, 2);
    },
  );
}
