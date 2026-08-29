import 'dart:async';

import 'package:arion_client/playback/audio_player_port.dart';
import 'package:arion_client/playback/just_audio_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recreates the engine and disposes the previous source', () async {
    final first = FakeAudioPlayerEngine(const Duration(minutes: 1));
    final second = FakeAudioPlayerEngine(const Duration(minutes: 2));
    final adapter = JustAudioAdapter(
      engine: first,
      engineFactory: () => second,
      recreateOnSourceChange: true,
    );

    expect(
      await adapter.setUrl(Uri.parse('http://arion.test/audio/1')),
      const Duration(minutes: 1),
    );
    expect(
      await adapter.setUrl(Uri.parse('http://arion.test/audio/2')),
      const Duration(minutes: 2),
    );

    expect(first.stopCalls, 1);
    expect(first.disposed, isTrue);
    expect(second.currentUrl.toString(), 'http://arion.test/audio/2');
    await adapter.dispose();
    expect(second.disposed, isTrue);
  });

  test('forwards events only from the authoritative engine', () async {
    final first = FakeAudioPlayerEngine(const Duration(minutes: 1));
    final second = FakeAudioPlayerEngine(const Duration(minutes: 2));
    final adapter = JustAudioAdapter(
      engine: first,
      engineFactory: () => second,
      recreateOnSourceChange: true,
    );
    final positions = <Duration>[];
    final subscription = adapter.positionStream.listen(positions.add);

    await adapter.setUrl(Uri.parse('http://arion.test/audio/1'));
    first.positions.add(const Duration(seconds: 10));
    await Future<void>.delayed(Duration.zero);
    await adapter.setUrl(Uri.parse('http://arion.test/audio/2'));
    first.positions.add(const Duration(seconds: 55));
    second.positions.add(const Duration(seconds: 20));
    await Future<void>.delayed(Duration.zero);

    expect(positions, [
      const Duration(seconds: 10),
      const Duration(seconds: 20),
    ]);
    await subscription.cancel();
    await adapter.dispose();
  });

  test('a newer replacement supersedes an unfinished transition', () async {
    final firstLoad = Completer<Duration?>();
    final first = FakeAudioPlayerEngine(null)..load = firstLoad.future;
    final second = FakeAudioPlayerEngine(const Duration(minutes: 2));
    final engines = <FakeAudioPlayerEngine>[second];
    final adapter = JustAudioAdapter(
      engine: first,
      engineFactory: () => engines.removeAt(0),
      recreateOnSourceChange: true,
    );

    final obsolete = adapter.setUrl(Uri.parse('http://arion.test/audio/1'));
    final latest = adapter.setUrl(Uri.parse('http://arion.test/audio/2'));
    expect(await latest, const Duration(minutes: 2));
    firstLoad.complete(const Duration(minutes: 1));

    await expectLater(obsolete, throwsA(isA<AudioSourceSupersededException>()));
    expect(second.currentUrl.toString(), 'http://arion.test/audio/2');
    await adapter.dispose();
  });
}

final class FakeAudioPlayerEngine implements AudioPlayerEngine {
  FakeAudioPlayerEngine(this.duration);

  final Duration? duration;
  Future<Duration?>? load;
  final StreamController<bool> playing = StreamController.broadcast();
  final StreamController<AudioProcessingState> processing =
      StreamController.broadcast();
  final StreamController<Duration> positions = StreamController.broadcast();
  final StreamController<Duration?> durations = StreamController.broadcast();
  final StreamController<Object> errors = StreamController.broadcast();

  Uri? currentUrl;
  int stopCalls = 0;
  bool disposed = false;

  @override
  Stream<bool> get playingStream => playing.stream;

  @override
  Stream<AudioProcessingState> get processingStateStream => processing.stream;

  @override
  Stream<Duration> get positionStream => positions.stream;

  @override
  Stream<Duration?> get durationStream => durations.stream;

  @override
  Stream<Object> get errorStream => errors.stream;

  @override
  Future<Duration?> setUrl(Uri uri) async {
    currentUrl = uri;
    return load == null ? duration : await load;
  }

  @override
  Future<void> play() async => playing.add(true);

  @override
  Future<void> pause() async => playing.add(false);

  @override
  Future<void> stop() async {
    stopCalls += 1;
    playing.add(false);
  }

  @override
  Future<void> seek(Duration position) async => positions.add(position);

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
