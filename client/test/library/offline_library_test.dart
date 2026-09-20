import 'package:arion_client/library/offline_library.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  test('catalog snapshot round-trips losslessly', () {
    final snapshot = OfflineCatalogSnapshot(
      serverUrl: 'http://arion.test',
      savedAt: DateTime.utc(2026, 9, 13),
      tracks: [sampleTrack()],
    );

    final restored = OfflineCatalogSnapshot.fromJson(snapshot.toJson());

    expect(restored.version, offlineCatalogVersion);
    expect(restored.serverUrl, snapshot.serverUrl);
    expect(restored.savedAt, snapshot.savedAt);
    expect(restored.tracks.single.toJson(), snapshot.tracks.single.toJson());
  });

  test('rejects malformed and unsupported catalog snapshots', () {
    expect(
      () => OfflineCatalogSnapshot.fromJson({'version': 99}),
      throwsFormatException,
    );
    expect(
      () => OfflineCatalogSnapshot.fromJson({
        'version': offlineCatalogVersion,
        'server_url': 'http://arion.test',
        'saved_at': 'invalid',
        'tracks': const [],
      }),
      throwsFormatException,
    );
  });

  test('noop controller keeps web/default state inert', () async {
    final controller = NoopOfflineLibraryController();
    await controller.initialize();
    await controller.enable();
    await controller.synchronize();

    expect(controller.isSupported, isFalse);
    expect(controller.isEnabled, isFalse);
    expect(controller.phase, OfflineLibraryPhase.disabled);
    expect(await controller.loadSnapshot(), isNull);
  });
}
