import 'dart:async';

import 'package:arion_client/library/catalog_api.dart';
import 'package:arion_client/library/acquisition.dart';
import 'package:arion_client/library/library_controller.dart';
import 'package:arion_client/library/offline_library.dart';
import 'package:arion_client/library/track.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  test('falls back to a saved snapshot and searches it locally', () async {
    final api = FakeCatalogApi(
      handler: (_, _, _) => Future.error(
        const CatalogException('The server could not be reached.'),
      ),
    );
    final snapshot = OfflineCatalogSnapshot(
      serverUrl: 'http://arion.test:8000',
      savedAt: DateTime.utc(2026),
      tracks: [
        sampleTrack(id: 'one', title: 'Alpha'),
        Track(
          id: 'two',
          title: 'Beta',
          artist: 'Local Artist',
          album: 'Offline Album',
          durationMs: 1000,
          codec: 'mp3',
          bitrateKbps: 128,
          sampleRateHz: 44100,
          originalFilename: 'beta.mp3',
          hasCover: false,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      ],
    );
    final controller = LibraryController(
      api,
      snapshotStore: MemorySnapshotStore(snapshot),
    );

    await controller.loadInitial();
    expect(controller.isOfflineSnapshot, isTrue);
    expect(controller.error, isNull);
    expect(controller.items, hasLength(2));

    await controller.submitSearch('local artist');
    expect(controller.items.single.id, 'two');
    expect(api.calls, hasLength(1), reason: 'offline search must stay local');

    await controller.clearSearch();
    expect(controller.items, hasLength(2));
    expect(controller.hasMore, isFalse);
  });

  test('keeps the existing retryable error when no snapshot exists', () async {
    final controller = LibraryController(
      FakeCatalogApi(
        handler: (_, _, _) => Future.error(const CatalogException('offline')),
      ),
      snapshotStore: MemorySnapshotStore(null),
    );

    await controller.loadInitial();

    expect(controller.isOfflineSnapshot, isFalse);
    expect(controller.error, 'offline');
  });

  test(
    'triggers synchronization only for unfiltered catalog changes',
    () async {
      var refreshes = 0;
      final controller = LibraryController(
        FakeCatalogApi(),
        onUnfilteredCatalogChanged: () => refreshes += 1,
      );

      await controller.loadInitial();
      await controller.submitSearch('query');
      await controller.clearSearch();

      expect(refreshes, 2);
    },
  );

  test('completed acquisition triggers offline reconciliation', () async {
    var refreshes = 0;
    final controller = LibraryController(
      FakeCatalogApi(
        createJobHandler: (_) async => sampleAcquisitionJob(
          state: 'completed',
          phase: 'completed',
          progressPercent: 100,
          trackId: 'imported',
        ),
      ),
      onUnfilteredCatalogChanged: () => refreshes += 1,
    );

    await controller.startAcquisition(sampleCandidate());

    expect(controller.items.single.id, 'imported');
    expect(refreshes, 1);
  });

  test('loads populated and empty libraries', () async {
    final api = FakeCatalogApi(
      handler: (limit, offset, query) async => TrackPage(
        items: [sampleTrack()],
        total: 1,
        limit: limit,
        offset: offset,
      ),
    );
    final controller = LibraryController(api);

    await controller.loadInitial();
    expect(controller.items, hasLength(1));
    expect(controller.isEmpty, isFalse);

    api.handler = (limit, offset, query) async =>
        TrackPage(items: const [], total: 0, limit: limit, offset: offset);
    await controller.loadInitial();
    expect(controller.isEmpty, isTrue);
  });

  test('surfaces failure and retries', () async {
    var fail = true;
    final api = FakeCatalogApi(
      handler: (limit, offset, query) async {
        if (fail) {
          throw const CatalogException('Unavailable');
        }
        return TrackPage(
          items: [sampleTrack()],
          total: 1,
          limit: limit,
          offset: offset,
        );
      },
    );
    final controller = LibraryController(api);

    await controller.loadInitial();
    expect(controller.error, 'Unavailable');
    fail = false;
    await controller.retry();
    expect(controller.items, hasLength(1));
    expect(controller.error, isNull);
  });

  test('loads additional pages once and removes duplicate tracks', () async {
    final first = sampleTrack();
    final second = sampleTrack(id: '2', title: 'Second');
    final blocker = Completer<TrackPage>();
    final api = FakeCatalogApi(
      handler: (limit, offset, query) {
        if (offset == 0) {
          return Future.value(
            TrackPage(items: [first], total: 2, limit: limit, offset: 0),
          );
        }
        return blocker.future;
      },
    );
    final controller = LibraryController(api);
    await controller.loadInitial();

    final firstCall = controller.loadMore();
    final guardedCall = controller.loadMore();
    blocker.complete(
      TrackPage(items: [first, second], total: 2, limit: 30, offset: 1),
    );
    await Future.wait([firstCall, guardedCall]);

    expect(api.calls.where((call) => call.offset == 1), hasLength(1));
    expect(controller.items.map((track) => track.id), [first.id, second.id]);
  });

  test('clearing search reloads the unfiltered first page', () async {
    final api = FakeCatalogApi();
    final controller = LibraryController(api);

    await controller.submitSearch('artist');
    await controller.clearSearch();

    expect(api.calls.last.query, isNull);
    expect(api.calls.last.offset, 0);
  });

  test('ignores an older response after a newer search', () async {
    final oldResponse = Completer<TrackPage>();
    final newResponse = Completer<TrackPage>();
    final api = FakeCatalogApi(
      handler: (limit, offset, query) =>
          query == 'old' ? oldResponse.future : newResponse.future,
    );
    final controller = LibraryController(api);

    final oldCall = controller.submitSearch('old');
    final newCall = controller.submitSearch('new');
    newResponse.complete(
      TrackPage(
        items: [sampleTrack(id: 'new', title: 'New')],
        total: 1,
        limit: 30,
        offset: 0,
      ),
    );
    await newCall;
    oldResponse.complete(
      TrackPage(
        items: [sampleTrack(id: 'old', title: 'Old')],
        total: 1,
        limit: 30,
        offset: 0,
      ),
    );
    await oldCall;

    expect(controller.query, 'new');
    expect(controller.items.single.title, 'New');
  });

  test('offers discovery only after an explicit empty local search', () async {
    final api = FakeCatalogApi(
      discoveryHandler: (_, _) async => [sampleCandidate()],
    );
    final controller = LibraryController(api);

    expect(controller.canSearchYouTube, isFalse);
    await controller.submitSearch('missing song');
    expect(controller.canSearchYouTube, isTrue);
    expect(api.discoveryCalls, isEmpty);

    await controller.discoverYouTube();
    expect(api.discoveryCalls, [
      (query: 'missing song', mode: YouTubeDiscoveryMode.music),
    ]);
    expect(controller.candidates.single.videoId, 'abcdefghijk');
  });

  test('defaults to music and changing mode does not search', () async {
    final api = FakeCatalogApi();
    final controller = LibraryController(api);

    expect(controller.discoveryMode, YouTubeDiscoveryMode.music);
    await controller.submitSearch('missing song');
    controller.setDiscoveryMode(YouTubeDiscoveryMode.all);

    expect(controller.discoveryMode, YouTubeDiscoveryMode.all);
    expect(api.discoveryCalls, isEmpty);
    expect(controller.candidates, isEmpty);
  });

  test('clears candidates and errors when changing mode', () async {
    var fail = false;
    final api = FakeCatalogApi(
      discoveryHandler: (_, mode) async {
        if (fail) throw const CatalogException('Discovery failed');
        return [sampleCandidate(discoveryMode: mode)];
      },
    );
    final controller = LibraryController(api);
    await controller.submitSearch('missing');
    await controller.discoverYouTube();
    expect(controller.candidates, isNotEmpty);

    controller.setDiscoveryMode(YouTubeDiscoveryMode.all);
    expect(controller.candidates, isEmpty);
    fail = true;
    await controller.discoverYouTube();
    expect(controller.acquisitionError, 'Discovery failed');

    controller.setDiscoveryMode(YouTubeDiscoveryMode.music);
    expect(controller.acquisitionError, isNull);
  });

  test('discards late results from the previous discovery mode', () async {
    final music = Completer<List<YouTubeCandidate>>();
    final all = Completer<List<YouTubeCandidate>>();
    final api = FakeCatalogApi(
      discoveryHandler: (_, mode) =>
          mode == YouTubeDiscoveryMode.music ? music.future : all.future,
    );
    final controller = LibraryController(api);
    await controller.submitSearch('missing');

    final oldSearch = controller.discoverYouTube();
    controller.setDiscoveryMode(YouTubeDiscoveryMode.all);
    final newSearch = controller.discoverYouTube();
    all.complete([
      sampleCandidate(
        title: 'All result',
        discoveryMode: YouTubeDiscoveryMode.all,
      ),
    ]);
    await newSearch;
    music.complete([sampleCandidate(title: 'Music result')]);
    await oldSearch;

    expect(controller.candidates.single.title, 'All result');
    expect(controller.discoveryMode, YouTubeDiscoveryMode.all);
  });

  test('does not offer discovery when the local search has results', () async {
    final api = FakeCatalogApi(
      handler: (limit, offset, query) async => TrackPage(
        items: [sampleTrack()],
        total: 1,
        limit: limit,
        offset: offset,
      ),
    );
    final controller = LibraryController(api);

    await controller.submitSearch('present song');
    await controller.discoverYouTube();

    expect(controller.canSearchYouTube, isFalse);
    expect(api.discoveryCalls, isEmpty);
  });

  test('ignores discovery results after a newer local search', () async {
    final discovery = Completer<List<YouTubeCandidate>>();
    final api = FakeCatalogApi(discoveryHandler: (_, _) => discovery.future);
    final controller = LibraryController(api);
    await controller.submitSearch('old missing song');

    final oldDiscovery = controller.discoverYouTube();
    await controller.submitSearch('new missing song');
    discovery.complete([sampleCandidate()]);
    await oldDiscovery;

    expect(controller.query, 'new missing song');
    expect(controller.candidates, isEmpty);
  });

  test('polls one job, remembers it, and reveals without autoplay', () async {
    final store = FakeAcquisitionJobStore();
    final responses = <AcquisitionJob>[
      sampleAcquisitionJob(state: 'downloading', phase: 'downloading'),
      sampleAcquisitionJob(
        state: 'completed',
        phase: 'completed',
        progressPercent: 100,
        trackId: 'downloaded-track',
      ),
    ];
    final api = FakeCatalogApi(
      discoveryHandler: (_, _) async => [sampleCandidate()],
      createJobHandler: (_) async => sampleAcquisitionJob(),
      fetchJobHandler: (_) async => responses.removeAt(0),
    );
    final controller = LibraryController(
      api,
      jobStore: store,
      jobPollInterval: Duration.zero,
    );
    await controller.submitSearch('missing');
    await controller.discoverYouTube();

    await controller.startAcquisition(controller.candidates.single);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(api.createdCandidates, ['signed-candidate-token']);
    expect(api.fetchedJobs, hasLength(2));
    expect(store.value, isNull);
    expect(controller.activeJob?.isCompleted, isTrue);
    expect(controller.items.single.id, 'downloaded-track');
    expect(controller.query, isEmpty);
  });

  test('resumes a remembered job and reports terminal failure', () async {
    final store = FakeAcquisitionJobStore()..value = 'remembered-job';
    final api = FakeCatalogApi(
      fetchJobHandler: (_) async => sampleAcquisitionJob(
        state: 'failed',
        phase: 'failed',
        failureCode: 'provider_unavailable',
        failureMessage: 'The provider is temporarily unavailable.',
      ),
    );
    final controller = LibraryController(api, jobStore: store);

    await controller.loadInitial();
    await Future<void>.delayed(Duration.zero);

    expect(api.fetchedJobs, ['remembered-job']);
    expect(store.value, isNull);
    expect(controller.activeJob?.isFailed, isTrue);
    expect(
      controller.acquisitionError,
      'The provider is temporarily unavailable.',
    );
  });

  test('prevents a duplicate submission while a job is active', () async {
    final api = FakeCatalogApi(
      discoveryHandler: (_, _) async => [sampleCandidate()],
      createJobHandler: (_) async => sampleAcquisitionJob(),
      fetchJobHandler: (_) => Completer<AcquisitionJob>().future,
    );
    final controller = LibraryController(
      api,
      jobPollInterval: const Duration(days: 1),
    );
    await controller.submitSearch('missing');
    await controller.discoverYouTube();
    final candidate = controller.candidates.single;

    await controller.startAcquisition(candidate);
    await controller.startAcquisition(candidate);

    final activeJob = controller.activeJob;
    controller.setDiscoveryMode(YouTubeDiscoveryMode.all);

    expect(api.createdCandidates, hasLength(1));
    expect(controller.activeJob, same(activeJob));
    controller.dispose();
  });

  test(
    'keeps polling after a reconnectable error and clears it on success',
    () async {
      var polls = 0;
      final api = FakeCatalogApi(
        discoveryHandler: (_, _) async => [sampleCandidate()],
        createJobHandler: (_) async => sampleAcquisitionJob(),
        fetchJobHandler: (_) async {
          polls += 1;
          if (polls == 1) {
            throw const CatalogException('Connection interrupted.');
          }
          return sampleAcquisitionJob(
            state: 'completed',
            phase: 'completed',
            progressPercent: 100,
            trackId: 'reconnected-track',
          );
        },
      );
      final controller = LibraryController(api, jobPollInterval: Duration.zero);
      await controller.submitSearch('missing');
      await controller.discoverYouTube();

      await controller.startAcquisition(controller.candidates.single);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(polls, 2);
      expect(controller.activeJob?.isCompleted, isTrue);
      expect(controller.acquisitionError, isNull);
      expect(controller.items.single.id, 'reconnected-track');
    },
  );
}

final class MemorySnapshotStore implements OfflineCatalogSnapshotStore {
  const MemorySnapshotStore(this.snapshot);

  final OfflineCatalogSnapshot? snapshot;

  @override
  Future<OfflineCatalogSnapshot?> loadSnapshot() async => snapshot;
}
