import 'dart:async';

import 'package:arion_client/playback/audio_player_port.dart';
import 'package:arion_client/playback/just_audio_adapter.dart';
import 'package:arion_client/playback/offline_audio_resolver.dart';
import 'package:arion_client/playback/playback_audio_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  test('uses the bounded Android forward-buffer configuration', () {
    expect(
      arionAndroidLoadControl.minBufferDuration,
      const Duration(seconds: 90),
    );
    expect(
      arionAndroidLoadControl.maxBufferDuration,
      const Duration(seconds: 180),
    );
    expect(
      arionAndroidLoadControl.bufferForPlaybackDuration,
      const Duration(milliseconds: 2500),
    );
    expect(
      arionAndroidLoadControl.bufferForPlaybackAfterRebufferDuration,
      const Duration(seconds: 5),
    );
    expect(arionAndroidLoadControl.prioritizeTimeOverSizeThresholds, isTrue);
  });

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
    final obsoleteExpectation = expectLater(
      obsolete,
      throwsA(isA<AudioSourceSupersededException>()),
    );
    final latest = adapter.setUrl(Uri.parse('http://arion.test/audio/2'));
    expect(await latest, const Duration(minutes: 2));
    firstLoad.complete(const Duration(minutes: 1));

    await obsoleteExpectation;
    expect(second.currentUrl.toString(), 'http://arion.test/audio/2');
    await adapter.dispose();
  });

  test('loads a prepared cache source instead of the direct URL', () async {
    final engine = FakeAudioPlayerEngine(const Duration(minutes: 2));
    final cache = FakePlaybackAudioCache()
      ..prepared.add(
        cacheSource(
          key: 'network-entry',
          source: AudioSource.uri(Uri.parse('http://cache.test/proxy')),
        ),
      );
    final adapter = JustAudioAdapter(engine: engine, playbackCache: cache);

    expect(
      await adapter.setUrl(Uri.parse('http://arion.test/audio/1')),
      const Duration(minutes: 2),
    );

    expect(engine.currentUrl, isNull);
    expect(engine.currentSource, isNotNull);
    expect(cache.prepareBypasses, [false]);
    await adapter.dispose();
    expect(cache.disposed, isTrue);
  });

  test('prefers verified offline audio before cache and network', () async {
    final engine = FakeAudioPlayerEngine(const Duration(minutes: 2));
    final resolver = FakeOfflineAudioResolver(
      OfflineAudioFile(key: 'offline', path: 'offline.bin', length: 10),
    );
    final cache = FakePlaybackAudioCache();
    final adapter = JustAudioAdapter(
      engine: engine,
      offlineAudioResolver: resolver,
      playbackCache: cache,
    );

    await adapter.setUrl(Uri.parse('http://arion.test/audio/1'));

    expect(engine.currentSource, isA<UriAudioSource>());
    expect(
      (engine.currentSource as UriAudioSource).uri,
      Uri.file('offline.bin'),
    );
    expect(engine.currentUrl, isNull);
    expect(cache.prepareBypasses, isEmpty);
    await adapter.dispose();
  });

  test('invalidates rejected offline audio and falls through once', () async {
    final engine = FakeAudioPlayerEngine(const Duration(minutes: 2));
    var calls = 0;
    engine.setAudioSourceHandler = (_) async {
      calls += 1;
      if (calls == 1) throw StateError('bad offline file');
      return const Duration(minutes: 2);
    };
    final resolver = FakeOfflineAudioResolver(
      OfflineAudioFile(key: 'offline', path: 'offline.bin', length: 10),
    );
    final cache = FakePlaybackAudioCache()
      ..prepared.add(cacheSource(key: 'network'));
    final adapter = JustAudioAdapter(
      engine: engine,
      offlineAudioResolver: resolver,
      playbackCache: cache,
    );
    final uri = Uri.parse('http://arion.test/audio/1');

    await adapter.setUrl(uri);

    expect(resolver.invalidated, [uri]);
    expect(cache.prepareBypasses, [false]);
    expect(calls, 2);
    await adapter.dispose();
  });

  test('asynchronous offline failure bypasses local file on reload', () async {
    final engine = FakeAudioPlayerEngine(const Duration(minutes: 2));
    final uri = Uri.parse('http://arion.test/audio/1');
    final resolver = FakeOfflineAudioResolver(
      OfflineAudioFile(key: 'offline', path: 'offline.bin', length: 10),
    );
    final cache = FakePlaybackAudioCache()
      ..prepared.add(cacheSource(key: 'network'));
    final adapter = JustAudioAdapter(
      engine: engine,
      offlineAudioResolver: resolver,
      playbackCache: cache,
    );
    await adapter.setUrl(uri);

    engine.errors.add(StateError('decode failed'));
    await Future<void>.delayed(Duration.zero);
    await adapter.setUrl(uri);

    expect(resolver.resolved, [uri]);
    expect(resolver.invalidated, [uri]);
    expect(cache.prepareBypasses, [false]);
    await adapter.dispose();
  });

  test(
    'publishes completion only for the authoritative cached source',
    () async {
      final engine = FakeAudioPlayerEngine(const Duration(minutes: 2));
      final firstCompletion = StreamController<void>.broadcast();
      final secondCompletion = StreamController<void>.broadcast();
      final cache = FakePlaybackAudioCache()
        ..prepared.add(
          cacheSource(key: 'first', completion: firstCompletion.stream),
        )
        ..prepared.add(
          cacheSource(key: 'second', completion: secondCompletion.stream),
        );
      final adapter = JustAudioAdapter(engine: engine, playbackCache: cache);

      await adapter.setUrl(Uri.parse('http://arion.test/audio/1'));
      await adapter.setUrl(Uri.parse('http://arion.test/audio/2'));
      firstCompletion.add(null);
      secondCompletion.add(null);
      await Future<void>.delayed(Duration.zero);

      expect(cache.completed, ['second']);
      await firstCompletion.close();
      await secondCompletion.close();
      await adapter.dispose();
    },
  );

  test(
    'invalidates a rejected local source and retries through cache',
    () async {
      final engine = FakeAudioPlayerEngine(const Duration(minutes: 2));
      var sourceLoads = 0;
      engine.setAudioSourceHandler = (_) async {
        sourceLoads += 1;
        if (sourceLoads == 1) throw StateError('corrupt local file');
        return const Duration(minutes: 2);
      };
      final cache = FakePlaybackAudioCache()
        ..prepared.add(
          cacheSource(
            key: 'local',
            fromCompleteCache: true,
            source: AudioSource.file('cached-audio.bin'),
          ),
        )
        ..prepared.add(cacheSource(key: 'network'));
      final adapter = JustAudioAdapter(engine: engine, playbackCache: cache);

      expect(
        await adapter.setUrl(Uri.parse('http://arion.test/audio/1')),
        const Duration(minutes: 2),
      );

      expect(cache.invalidated, ['local']);
      expect(cache.prepareBypasses, [false, true]);
      expect(engine.audioSourceCalls, 2);
      await adapter.dispose();
    },
  );

  test(
    'an asynchronous local error bypasses cache on recovery reload',
    () async {
      final engine = FakeAudioPlayerEngine(const Duration(minutes: 2));
      final cache = FakePlaybackAudioCache()
        ..prepared.add(
          cacheSource(
            key: 'local',
            fromCompleteCache: true,
            source: AudioSource.file('cached-audio.bin'),
          ),
        )
        ..prepared.add(cacheSource(key: 'network'));
      final adapter = JustAudioAdapter(engine: engine, playbackCache: cache);
      final errors = <Object>[];
      final subscription = adapter.errorStream.listen(errors.add);
      final uri = Uri.parse('http://arion.test/audio/1');
      await adapter.setUrl(uri);

      engine.errors.add(StateError('local decode failed'));
      await Future<void>.delayed(Duration.zero);
      await adapter.setUrl(uri);

      expect(errors, hasLength(1));
      expect(cache.invalidated, ['local']);
      expect(cache.prepareBypasses, [false, true]);
      await subscription.cancel();
      await adapter.dispose();
    },
  );

  test('falls back to direct URL when cache preparation fails', () async {
    final engine = FakeAudioPlayerEngine(const Duration(minutes: 2));
    final cache = FakePlaybackAudioCache()..prepared.add(null);
    final adapter = JustAudioAdapter(engine: engine, playbackCache: cache);
    final uri = Uri.parse('http://arion.test/audio/1');

    expect(await adapter.setUrl(uri), const Duration(minutes: 2));

    expect(engine.currentUrl, uri);
    expect(engine.audioSourceCalls, 0);
    await adapter.dispose();
  });

  test(
    'surfaces failure when local and network cache sources both fail',
    () async {
      final engine = FakeAudioPlayerEngine(const Duration(minutes: 2))
        ..setAudioSourceHandler = (_) =>
            Future.error(StateError('unavailable'));
      final cache = FakePlaybackAudioCache()
        ..prepared.add(
          cacheSource(
            key: 'local',
            fromCompleteCache: true,
            source: AudioSource.file('cached-audio.bin'),
          ),
        )
        ..prepared.add(cacheSource(key: 'network'));
      final adapter = JustAudioAdapter(engine: engine, playbackCache: cache);

      await expectLater(
        adapter.setUrl(Uri.parse('http://arion.test/audio/1')),
        throwsA(isA<StateError>()),
      );

      expect(cache.invalidated, ['local']);
      expect(cache.prepareBypasses, [false, true]);
      await adapter.dispose();
    },
  );
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
  AudioSource? currentSource;
  Future<Duration?> Function(AudioSource source)? setAudioSourceHandler;
  int audioSourceCalls = 0;
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
  Future<Duration?> setAudioSource(AudioSource source) async {
    currentSource = source;
    audioSourceCalls += 1;
    return setAudioSourceHandler == null
        ? duration
        : await setAudioSourceHandler!(source);
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

PlaybackCacheSource cacheSource({
  required String key,
  AudioSource? source,
  bool fromCompleteCache = false,
  Stream<void> completion = const Stream<void>.empty(),
}) => PlaybackCacheSource(
  key: key,
  source: source ?? AudioSource.uri(Uri.parse('http://cache.test/$key')),
  fromCompleteCache: fromCompleteCache,
  completion: completion,
);

final class FakePlaybackAudioCache implements PlaybackAudioCache {
  final List<PlaybackCacheSource?> prepared = [];
  final List<bool> prepareBypasses = [];
  final List<String> completed = [];
  final List<String> invalidated = [];
  int releaseCalls = 0;
  int maintenanceCalls = 0;
  bool disposed = false;

  @override
  Future<PlaybackCacheSource?> prepare(
    Uri uri, {
    bool bypassCompleteCache = false,
  }) async {
    prepareBypasses.add(bypassCompleteCache);
    return prepared.removeAt(0);
  }

  @override
  Future<void> complete(String key) async => completed.add(key);

  @override
  Future<int?> exportComplete(Uri uri, String destinationPath) async => null;

  @override
  Future<void> invalidate(String key) async => invalidated.add(key);

  @override
  Future<void> maintain() async => maintenanceCalls += 1;

  @override
  Future<void> release() async => releaseCalls += 1;

  @override
  Future<void> dispose() async => disposed = true;
}

final class FakeOfflineAudioResolver implements OfflineAudioResolver {
  FakeOfflineAudioResolver(this.file);

  final OfflineAudioFile? file;
  final List<Uri> resolved = [];
  final List<Uri> invalidated = [];
  bool disposed = false;

  @override
  Future<OfflineAudioFile?> resolve(Uri uri) async {
    resolved.add(uri);
    return file;
  }

  @override
  Future<void> invalidate(Uri uri) async => invalidated.add(uri);

  @override
  Future<void> dispose() async => disposed = true;
}
