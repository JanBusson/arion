import 'dart:io';

import 'package:arion_client/configuration/api_base_url.dart';
import 'package:arion_client/configuration/resource_identity.dart';
import 'package:arion_client/library/offline_library.dart';
import 'package:arion_client/library/offline_library_io.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late Directory sandbox;
  late ApiBaseUrl baseUrl;
  late OfflineLibraryFileStore store;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('arion-offline-test-');
    baseUrl = ApiBaseUrl.parse('http://ARION.test:80/music/');
    store = OfflineLibraryFileStore(
      baseUrl: baseUrl,
      rootProvider: () async => sandbox,
    );
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test('normalizes identities and isolates server and track', () {
    expect(
      resourceKey(Uri.parse('HTTP://ARION.TEST:80/a/../track#fragment')),
      resourceKey(Uri.parse('http://arion.test/track')),
    );
    expect(
      resourceKey(Uri.parse('http://arion.test/track')),
      isNot(resourceKey(Uri.parse('http://other.test/track'))),
    );
    expect(
      resourceKey(Uri.parse('http://arion.test/track')),
      isNot(resourceKey(Uri.parse('http://arion.test/other'))),
    );
  });

  test('atomically restores only a matching versioned snapshot', () async {
    final snapshot = OfflineCatalogSnapshot(
      serverUrl: store.normalizedServerUrl,
      savedAt: DateTime.utc(2026),
      tracks: [sampleTrack()],
    );
    await store.commitSnapshot(snapshot);

    final restored = await store.loadSnapshot();

    expect(restored?.tracks.single.id, snapshot.tracks.single.id);
    final catalog = File(
      '${sandbox.path}${Platform.pathSeparator}${store.serverKey}'
      '${Platform.pathSeparator}catalog.json',
    );
    await catalog.writeAsString('{"version":99}');
    expect(await store.loadSnapshot(), isNull);
  });

  test('publishes only exact non-empty media lengths', () async {
    final uri = store.audioUri(sampleTrack().id);
    final paths = await store.pathsFor(uri);
    await paths.directory.create(recursive: true);
    await paths.partial.writeAsBytes([1, 2, 3]);

    await expectLater(
      store.publishPartial(uri, 4),
      throwsA(isA<FileSystemException>()),
    );
    expect(await store.verifiedAudio(uri), isNull);

    await store.publishPartial(uri, 3);
    final verified = await store.verifiedAudio(uri);
    expect(verified?.length, 3);
    await paths.length.writeAsString('2');
    expect(await store.verifiedAudio(uri), isNull);
  });

  test('retains exact snapshot tracks and removes orphan state', () async {
    final retained = sampleTrack(id: 'retained');
    final removed = sampleTrack(id: 'removed');
    for (final track in [retained, removed]) {
      final paths = await store.pathsFor(store.audioUri(track.id));
      await paths.directory.create(recursive: true);
      await paths.partial.writeAsBytes([1]);
    }

    await store.retainTracks([retained]);

    expect(
      await (await store.pathsFor(
        store.audioUri(retained.id),
      )).directory.exists(),
      isTrue,
    );
    expect(
      await (await store.pathsFor(
        store.audioUri(removed.id),
      )).directory.exists(),
      isFalse,
    );
  });

  test('server cleanup cannot remove another server directory', () async {
    final other = OfflineLibraryFileStore(
      baseUrl: ApiBaseUrl.parse('http://other.test'),
      rootProvider: () async => sandbox,
    );
    await store.commitSnapshot(
      OfflineCatalogSnapshot(
        serverUrl: store.normalizedServerUrl,
        savedAt: DateTime.utc(2026),
        tracks: const [],
      ),
    );
    await other.commitSnapshot(
      OfflineCatalogSnapshot(
        serverUrl: other.normalizedServerUrl,
        savedAt: DateTime.utc(2026),
        tracks: const [],
      ),
    );

    await store.clear();

    expect(await store.loadSnapshot(), isNull);
    expect(await other.loadSnapshot(), isNotNull);
  });

  test(
    'resolver finds and invalidates app-private audio by request URI',
    () async {
      final uri = store.audioUri(sampleTrack().id);
      final paths = await store.pathsFor(uri);
      await paths.directory.create(recursive: true);
      await paths.partial.writeAsBytes([1, 2]);
      await store.publishPartial(uri, 2);
      final resolver = AndroidOfflineAudioResolver(
        rootProvider: () async => sandbox,
      );

      expect((await resolver.resolve(uri))?.length, 2);
      await resolver.invalidate(uri);
      expect(await resolver.resolve(uri), isNull);
    },
  );
}
