import 'dart:async';
import 'dart:io';

import 'package:arion_client/library/offline_library.dart';
import 'package:arion_client/library/offline_library_io.dart';
import 'package:arion_client/library/catalog_api.dart';
import 'package:arion_client/library/track.dart';
import 'package:arion_client/playback/playback_audio_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fakes.dart';

void main() {
  late Directory sandbox;
  late OfflineLibraryFileStore store;
  late MemoryOfflinePreferences preferences;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('arion-sync-test-');
    store = OfflineLibraryFileStore(
      baseUrl: sampleBaseUrl(),
      rootProvider: () async => sandbox,
    );
    preferences = MemoryOfflinePreferences();
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  AndroidOfflineLibraryController controller({
    required FakeCatalogApi api,
    required http.Client client,
    PlaybackAudioCache? cache,
    int workers = 2,
    Duration timeout = const Duration(seconds: 30),
  }) => AndroidOfflineLibraryController(
    baseUrl: sampleBaseUrl(),
    catalogApi: api,
    downloadClient: client,
    store: store,
    preferences: preferences,
    playbackCache: cache ?? EmptyPlaybackCache(),
    workerCount: workers,
    requestTimeout: timeout,
  );

  test('pages the complete catalog and uses at most two workers', () async {
    final tracks = [
      sampleTrack(id: 'one'),
      sampleTrack(id: 'two'),
      sampleTrack(id: 'three'),
    ];
    final api = FakeCatalogApi(
      handler: (limit, offset, query) async => TrackPage(
        items: offset == 0 ? tracks.take(2).toList() : [tracks.last],
        total: 3,
        limit: limit,
        offset: offset,
      ),
    );
    var active = 0;
    var maximumActive = 0;
    var requests = 0;
    final client = MockClient((request) async {
      requests += 1;
      active += 1;
      if (active > maximumActive) maximumActive = active;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      active -= 1;
      return http.Response.bytes([1, 2, 3], 200);
    });
    final value = controller(api: api, client: client);
    addTearDown(value.dispose);
    await value.initialize();

    await value.enable();

    expect(api.calls.map((call) => call.offset), [0, 2]);
    expect(
      api.calls.every((call) => call.limit == 100 && call.query == null),
      isTrue,
    );
    expect(maximumActive, 2);
    expect(requests, 3);
    expect(value.phase, OfflineLibraryPhase.ready);
    expect(value.completedCount, 3);
    expect(value.readyTrackIds, {'one', 'two', 'three'});
    expect((await value.loadSnapshot())?.tracks.length, 3);

    await value.retry();
    expect(requests, 3, reason: 'verified files must not be downloaded again');
  });

  test('resumes a compatible partial response', () async {
    final track = sampleTrack(id: 'resume');
    final paths = await store.pathsFor(store.audioUri(track.id));
    await paths.directory.create(recursive: true);
    await paths.partial.writeAsBytes([1, 2]);
    String? range;
    final client = MockClient((request) async {
      range = request.headers['range'];
      return http.Response.bytes(
        [3, 4],
        206,
        headers: {'content-range': 'bytes 2-3/4'},
      );
    });
    final value = controller(
      api: _singleTrackApi(track),
      client: client,
      workers: 1,
    );
    addTearDown(value.dispose);
    await value.initialize();

    await value.enable();

    expect(range, 'bytes=2-');
    expect((await store.verifiedAudio(store.audioUri(track.id)))?.length, 4);
  });

  test('restarts safely after an incompatible resume response', () async {
    final track = sampleTrack(id: 'restart');
    final uri = store.audioUri(track.id);
    final paths = await store.pathsFor(uri);
    await paths.directory.create(recursive: true);
    await paths.partial.writeAsBytes([1, 2]);
    final ranges = <String?>[];
    final client = MockClient((request) async {
      ranges.add(request.headers['range']);
      if (ranges.length == 1) {
        return http.Response.bytes(
          [9],
          206,
          headers: {'content-range': 'bytes 1-1/2'},
        );
      }
      return http.Response.bytes([5, 6, 7], 200);
    });
    final value = controller(
      api: _singleTrackApi(track),
      client: client,
      workers: 1,
    );
    addTearDown(value.dispose);
    await value.initialize();

    await value.enable();

    expect(ranges, ['bytes=2-', null]);
    expect((await store.verifiedAudio(uri))?.length, 3);
  });

  test('retains a truncated partial and resumes it on retry', () async {
    final track = sampleTrack(id: 'truncated');
    var attempt = 0;
    final ranges = <String?>[];
    final client = SequenceClient((request) async {
      attempt += 1;
      ranges.add(request.headers['range']);
      if (attempt == 1) {
        return http.StreamedResponse(
          Stream.value([1, 2]),
          200,
          contentLength: 4,
        );
      }
      return http.StreamedResponse(
        Stream.value([3, 4]),
        206,
        contentLength: 2,
        headers: {'content-range': 'bytes 2-3/4'},
      );
    });
    final value = controller(
      api: _singleTrackApi(track),
      client: client,
      workers: 1,
    );
    addTearDown(value.dispose);
    await value.initialize();

    await value.enable();
    expect(value.phase, OfflineLibraryPhase.failed);
    expect(await store.partialLength(store.audioUri(track.id)), 2);

    await value.retry();
    expect(ranges, [null, 'bytes=2-']);
    expect(value.phase, OfflineLibraryPhase.ready);
  });

  test('failed pagination preserves the prior complete snapshot', () async {
    final old = sampleTrack(id: 'old');
    await store.commitSnapshot(
      OfflineCatalogSnapshot(
        serverUrl: store.normalizedServerUrl,
        savedAt: DateTime.utc(2025),
        tracks: [old],
      ),
    );
    final api = FakeCatalogApi(
      handler: (limit, offset, query) async {
        if (offset > 0) throw const CatalogException('offline');
        return TrackPage(
          items: [sampleTrack(id: 'new')],
          total: 2,
          limit: limit,
          offset: offset,
        );
      },
    );
    final value = controller(
      api: api,
      client: MockClient((_) async => http.Response.bytes([1], 200)),
    );
    addTearDown(value.dispose);
    await value.initialize();

    await value.enable();

    expect(value.phase, OfflineLibraryPhase.unavailable);
    expect((await store.loadSnapshot())?.tracks.single.id, 'old');
  });

  test('rejects duplicate pagination without replacing its snapshot', () async {
    final old = sampleTrack(id: 'old');
    await store.commitSnapshot(
      OfflineCatalogSnapshot(
        serverUrl: store.normalizedServerUrl,
        savedAt: DateTime.utc(2025),
        tracks: [old],
      ),
    );
    final duplicate = sampleTrack(id: 'duplicate');
    final value = controller(
      api: FakeCatalogApi(
        handler: (limit, offset, query) async => TrackPage(
          items: offset == 0 ? [duplicate] : [duplicate],
          total: 2,
          limit: limit,
          offset: offset,
        ),
      ),
      client: MockClient((_) async => http.Response.bytes([1], 200)),
    );
    addTearDown(value.dispose);
    await value.initialize();

    await value.enable();

    expect(value.phase, OfflineLibraryPhase.unavailable);
    expect((await store.loadSnapshot())?.tracks.single.id, 'old');
  });

  test('bounds a stalled audio response with a timeout', () async {
    final value = controller(
      api: _singleTrackApi(sampleTrack(id: 'timeout')),
      client: SequenceClient((_) => Completer<http.StreamedResponse>().future),
      timeout: const Duration(milliseconds: 1),
    );
    addTearDown(value.dispose);
    await value.initialize();

    await value.enable();

    expect(value.phase, OfflineLibraryPhase.failed);
    expect(value.error, 'The audio download timed out.');
  });

  test(
    'imports complete playback cache and confirmed disable clears state',
    () async {
      final track = sampleTrack(id: 'cached');
      var networkRequests = 0;
      final cache = ExportingPlaybackCache([7, 8, 9]);
      final value = controller(
        api: _singleTrackApi(track),
        client: MockClient((_) async {
          networkRequests += 1;
          return http.Response.bytes([1], 200);
        }),
        cache: cache,
      );
      addTearDown(value.dispose);
      await value.initialize();

      await value.enable();
      expect(networkRequests, 0);
      expect(value.phase, OfflineLibraryPhase.ready);
      expect(await preferences.isEnabled(store.normalizedServerUrl), isTrue);

      await value.disable();
      expect(value.phase, OfflineLibraryPhase.disabled);
      expect(await preferences.isEnabled(store.normalizedServerUrl), isFalse);
      expect(await store.loadSnapshot(), isNull);
    },
  );

  test(
    'reconciles metadata, additions, and removals after a complete snapshot',
    () async {
      final retained = sampleTrack(id: 'retained', title: 'Old title');
      final removed = sampleTrack(id: 'removed');
      var catalog = [retained, removed];
      final api = FakeCatalogApi(
        handler: (limit, offset, query) async => TrackPage(
          items: offset == 0 ? catalog : const [],
          total: catalog.length,
          limit: limit,
          offset: offset,
        ),
      );
      final requestedIds = <String>[];
      final value = controller(
        api: api,
        client: MockClient((request) async {
          requestedIds.add(
            request.url.pathSegments[request.url.pathSegments.length - 2],
          );
          return http.Response.bytes([1, 2], 200);
        }),
        workers: 1,
      );
      addTearDown(value.dispose);
      await value.initialize();
      await value.enable();
      final removedPaths = await store.pathsFor(store.audioUri(removed.id));

      catalog = [
        sampleTrack(id: 'retained', title: 'Updated title'),
        sampleTrack(id: 'added'),
      ];
      await value.retry();

      expect(requestedIds, ['retained', 'removed', 'added']);
      expect(await removedPaths.directory.exists(), isFalse);
      expect((await store.loadSnapshot())?.tracks.first.title, 'Updated title');
      expect(value.readyTrackIds, {'retained', 'added'});
    },
  );

  test(
    'disable waits for cancellation before deleting transfer state',
    () async {
      final track = sampleTrack(id: 'cancelled');
      final stream = StreamController<List<int>>.broadcast();
      final requested = Completer<void>();
      final value = controller(
        api: _singleTrackApi(track),
        client: SequenceClient((_) async {
          requested.complete();
          return http.StreamedResponse(stream.stream, 200, contentLength: 2);
        }),
        workers: 1,
      );
      addTearDown(value.dispose);
      await value.initialize();
      final enabling = value.enable();
      await requested.future;

      final disabling = value.disable();
      stream.add([1]);
      await stream.close();
      await disabling;
      await enabling;

      expect(value.phase, OfflineLibraryPhase.disabled);
      expect(await store.loadSnapshot(), isNull);
      expect(
        await (await store.pathsFor(
          store.audioUri(track.id),
        )).directory.exists(),
        isFalse,
      );
    },
  );

  test('dispose prevents a stale catalog generation from publishing', () async {
    final pending = Completer<TrackPage>();
    await preferences.enable(store.normalizedServerUrl);
    final api = FakeCatalogApi(handler: (_, _, _) => pending.future);
    final value = controller(
      api: api,
      client: MockClient((_) async => http.Response.bytes([1], 200)),
    );
    await value.initialize();
    expect(api.calls, hasLength(1));

    value.dispose();
    pending.complete(
      TrackPage(
        items: [sampleTrack(id: 'late')],
        total: 1,
        limit: 100,
        offset: 0,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(api.closed, isTrue);
    expect(await store.loadSnapshot(), isNull);
  });
}

FakeCatalogApi _singleTrackApi(Track track) => FakeCatalogApi(
  handler: (limit, offset, query) async => TrackPage(
    items: offset == 0 ? [track] : const [],
    total: 1,
    limit: limit,
    offset: offset,
  ),
);

final class MemoryOfflinePreferences implements OfflinePreferenceStore {
  String? enabledServer;

  @override
  Future<void> disable(String normalizedServerUrl) async {
    if (enabledServer == normalizedServerUrl) enabledServer = null;
  }

  @override
  Future<void> enable(String normalizedServerUrl) async {
    enabledServer = normalizedServerUrl;
  }

  @override
  Future<bool> isEnabled(String normalizedServerUrl) async =>
      enabledServer == normalizedServerUrl;
}

class EmptyPlaybackCache implements PlaybackAudioCache {
  @override
  Future<int?> exportComplete(Uri uri, String destinationPath) async => null;

  @override
  Future<void> complete(String key) async {}
  @override
  Future<void> dispose() async {}
  @override
  Future<void> invalidate(String key) async {}
  @override
  Future<void> maintain() async {}
  @override
  Future<PlaybackCacheSource?> prepare(
    Uri uri, {
    bool bypassCompleteCache = false,
  }) async => null;
  @override
  Future<void> release() async {}
}

final class ExportingPlaybackCache extends EmptyPlaybackCache {
  ExportingPlaybackCache(this.bytes);
  final List<int> bytes;

  @override
  Future<int?> exportComplete(Uri uri, String destinationPath) async {
    final destination = File(destinationPath);
    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(bytes);
    return bytes.length;
  }
}

final class SequenceClient extends http.BaseClient {
  SequenceClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}
