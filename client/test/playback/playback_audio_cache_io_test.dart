import 'dart:io';

import 'package:arion_client/playback/playback_audio_cache_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  late Directory sandbox;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('arion-cache-test-');
  });

  tearDown(() async {
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  PlaybackCacheManager manager({
    int maxBytes = arionPlaybackCacheMaxBytes,
    DateTime Function()? clock,
  }) => PlaybackCacheManager(
    rootDirectory: () async => sandbox,
    maxBytes: maxBytes,
    clock: clock,
  );

  test('builds stable normalized keys isolated by server and track', () {
    final normalized = PlaybackCacheManager.keyFor(
      Uri.parse('HTTP://ARION.TEST:80/api/../api/tracks/one/audio#ignored'),
    );
    expect(
      normalized,
      PlaybackCacheManager.keyFor(
        Uri.parse('http://arion.test/api/tracks/one/audio'),
      ),
    );
    expect(
      normalized,
      isNot(
        PlaybackCacheManager.keyFor(
          Uri.parse('http://other.test/api/tracks/one/audio'),
        ),
      ),
    );
    expect(
      normalized,
      isNot(
        PlaybackCacheManager.keyFor(
          Uri.parse('http://arion.test/api/tracks/two/audio'),
        ),
      ),
    );
  });

  test('returns only a non-empty final file as a complete cache hit', () async {
    final cache = manager();
    addTearDown(cache.dispose);
    final uri = Uri.parse('http://arion.test/api/tracks/one/audio');
    final paths = await cache.pathsFor(uri);
    await paths.directory.create(recursive: true);
    await paths.mediaFile.writeAsBytes([1, 2, 3]);

    final hit = await cache.prepare(uri);

    expect(hit, isNotNull);
    expect(hit!.fromCompleteCache, isTrue);
    expect(hit.source, isA<UriAudioSource>());
    expect((hit.source as UriAudioSource).uri, Uri.file(paths.mediaFile.path));
  });

  test('does not treat a partial file as a complete cache hit', () async {
    final cache = manager();
    addTearDown(cache.dispose);
    final uri = Uri.parse('http://arion.test/api/tracks/one/audio');
    final paths = await cache.pathsFor(uri);
    await paths.directory.create(recursive: true);
    await paths.partialFile.writeAsBytes([1, 2, 3]);

    final miss = await cache.prepare(uri);

    expect(miss, isNotNull);
    expect(miss!.fromCompleteCache, isFalse);
    // ignore: experimental_member_use
    expect(miss.source, isA<LockCachingAudioSource>());
    expect(await paths.mediaFile.exists(), isFalse);
  });

  test('reuses a complete entry through a later manager instance', () async {
    final uri = Uri.parse('http://arion.test/api/tracks/one/audio');
    final first = manager();
    final paths = await first.pathsFor(uri);
    await paths.directory.create(recursive: true);
    await paths.mediaFile.writeAsBytes([1, 2, 3]);
    await first.dispose();

    final later = manager();
    addTearDown(later.dispose);
    final hit = await later.prepare(uri);

    expect(hit, isNotNull);
    expect(hit!.fromCompleteCache, isTrue);
  });

  test('exports a complete entry without moving the cache copy', () async {
    final cache = manager();
    addTearDown(cache.dispose);
    final uri = Uri.parse('http://arion.test/api/tracks/one/audio');
    final paths = await cache.pathsFor(uri);
    await paths.directory.create(recursive: true);
    await paths.mediaFile.writeAsBytes([1, 2, 3]);
    final destination = File(
      '${sandbox.path}${Platform.pathSeparator}offline${Platform.pathSeparator}audio.part',
    );

    expect(await cache.exportComplete(uri, destination.path), 3);
    expect(await destination.readAsBytes(), [1, 2, 3]);
    expect(await paths.mediaFile.readAsBytes(), [1, 2, 3]);

    expect(
      await cache.exportComplete(
        Uri.parse('http://arion.test/api/tracks/missing/audio'),
        '${destination.path}.missing',
      ),
      isNull,
    );
  });

  test('prunes least-recently-used complete entries as whole groups', () async {
    final cache = manager(maxBytes: 8);
    addTearDown(cache.dispose);
    final oldest = await cache.pathsFor(
      Uri.parse('http://arion.test/api/tracks/oldest/audio'),
    );
    final newest = await cache.pathsFor(
      Uri.parse('http://arion.test/api/tracks/newest/audio'),
    );
    await oldest.directory.create(recursive: true);
    await newest.directory.create(recursive: true);
    await oldest.mediaFile.writeAsBytes([1, 2, 3, 4]);
    await oldest.mimeFile.writeAsString('x');
    await newest.mediaFile.writeAsBytes([5, 6, 7, 8]);
    await newest.mimeFile.writeAsString('y');
    await oldest.mediaFile.setLastModified(DateTime.utc(2025));
    await newest.mediaFile.setLastModified(DateTime.utc(2026));

    await cache.maintain();

    expect(await oldest.directory.exists(), isFalse);
    expect(await newest.directory.exists(), isTrue);
  });

  test('protects the active entry and removes it after release', () async {
    final cache = manager(maxBytes: 4);
    addTearDown(cache.dispose);
    final activeUri = Uri.parse('http://arion.test/api/tracks/active/audio');
    final active = await cache.pathsFor(activeUri);
    final old = await cache.pathsFor(
      Uri.parse('http://arion.test/api/tracks/old/audio'),
    );
    await active.directory.create(recursive: true);
    await old.directory.create(recursive: true);
    await active.mediaFile.writeAsBytes([1, 2, 3, 4, 5, 6]);
    await old.mediaFile.writeAsBytes([7, 8]);
    await old.mediaFile.setLastModified(DateTime.utc(2025));

    final hit = await cache.prepare(activeUri);

    expect(hit!.fromCompleteCache, isTrue);
    expect(await active.directory.exists(), isTrue);
    expect(await old.directory.exists(), isFalse);

    await cache.release();

    expect(await active.directory.exists(), isFalse);
  });

  test(
    'removes orphan state and invalidates companion files together',
    () async {
      final cache = manager();
      addTearDown(cache.dispose);
      final orphan = await cache.pathsFor(
        Uri.parse('http://arion.test/api/tracks/orphan/audio'),
      );
      await orphan.directory.create(recursive: true);
      await orphan.partialFile.writeAsBytes([1]);
      await orphan.mimeFile.writeAsString('audio/mpeg');

      await cache.maintain();

      expect(await orphan.directory.exists(), isFalse);

      final uri = Uri.parse('http://arion.test/api/tracks/complete/audio');
      final complete = await cache.pathsFor(uri);
      await complete.directory.create(recursive: true);
      await complete.mediaFile.writeAsBytes([1]);
      await complete.mimeFile.writeAsString('audio/mpeg');
      await cache.invalidate(complete.key);
      expect(await complete.directory.exists(), isFalse);
    },
  );

  test('fails open when the cache root cannot be created', () async {
    final file = File('${sandbox.path}${Platform.pathSeparator}not-a-dir');
    await file.writeAsString('occupied');
    final cache = PlaybackCacheManager(
      rootDirectory: () async => Directory(file.path),
    );
    addTearDown(cache.dispose);

    final source = await cache.prepare(
      Uri.parse('http://arion.test/api/tracks/one/audio'),
    );
    await cache.maintain();
    await cache.release();

    expect(source, isNull);
  });

  test('fails open when the cache directory provider throws', () async {
    final cache = PlaybackCacheManager(
      rootDirectory: () => Future.error(StateError('no storage')),
    );
    addTearDown(cache.dispose);

    expect(
      await cache.prepare(Uri.parse('http://arion.test/api/tracks/one/audio')),
      isNull,
    );
    await cache.maintain();
  });

  test('fails open when touching a complete entry fails', () async {
    final cache = manager(clock: () => throw StateError('clock failed'));
    addTearDown(cache.dispose);
    final uri = Uri.parse('http://arion.test/api/tracks/one/audio');
    final paths = await cache.pathsFor(uri);
    await paths.directory.create(recursive: true);
    await paths.mediaFile.writeAsBytes([1, 2, 3]);

    final source = await cache.prepare(uri);

    expect(source, isNull);
  });
}
