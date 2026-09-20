import 'package:arion_client/app.dart';
import 'package:arion_client/library/track.dart';
import 'package:arion_client/library/offline_library.dart';
import 'package:arion_client/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  testWidgets(
    'missing configuration blocks requests and shows first-run form',
    (tester) async {
      final api = FakeCatalogApi();
      await tester.pumpWidget(
        ArionApp(
          settingsStore: FakeSettingsStore(),
          catalogApiFactory: (_) => api,
          audioPlayerFactory: FakeAudioPlayer.new,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Connect to Arion'), findsOneWidget);
      expect(find.byKey(const Key('server-url-field')), findsOneWidget);
      expect(api.calls, isEmpty);
    },
  );

  testWidgets('invalid submission explains the problem and does not persist', (
    tester,
  ) async {
    final store = FakeSettingsStore();
    await tester.pumpWidget(
      ArionApp(
        settingsStore: store,
        catalogApiFactory: (_) => FakeCatalogApi(),
        audioPlayerFactory: FakeAudioPlayer.new,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('server-url-field')),
      '/relative',
    );
    await tester.tap(find.byKey(const Key('save-server-button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('absolute HTTP or HTTPS'), findsOneWidget);
    expect(store.value, isNull);
  });

  testWidgets('persisted configuration opens the library', (tester) async {
    await tester.pumpWidget(
      ArionApp(
        settingsStore: FakeSettingsStore(value: 'http://arion.test:8000'),
        catalogApiFactory: (_) => FakeCatalogApi(),
        audioPlayerFactory: FakeAudioPlayer.new,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your library is empty.'), findsOneWidget);
    expect(find.text('Connect to Arion'), findsNothing);
  });

  testWidgets('settings can edit and save a different server', (tester) async {
    final store = FakeSettingsStore(value: 'http://old.test');
    final seenUrls = <String>[];
    await tester.pumpWidget(
      ArionApp(
        settingsStore: store,
        catalogApiFactory: (baseUrl) {
          seenUrls.add(baseUrl.toString());
          return FakeCatalogApi();
        },
        audioPlayerFactory: FakeAudioPlayer.new,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Server settings'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('server-url-field')),
      'https://new.test/',
    );
    await tester.tap(find.byKey(const Key('save-server-button')));
    await tester.pumpAndSettle();

    expect(store.value, 'https://new.test');
    expect(seenUrls, ['http://old.test', 'https://new.test']);
    expect(find.text('Server settings'), findsNothing);
  });

  testWidgets('changing server disposes the queued playback session', (
    tester,
  ) async {
    final store = FakeSettingsStore(value: 'http://old.test');
    final players = <FakeAudioPlayer>[];
    await tester.pumpWidget(
      ArionApp(
        settingsStore: store,
        catalogApiFactory: (baseUrl) => FakeCatalogApi(
          handler: (limit, offset, query) async => TrackPage(
            items: baseUrl.toString() == 'http://old.test'
                ? [sampleTrack()]
                : const [],
            total: baseUrl.toString() == 'http://old.test' ? 1 : 0,
            limit: limit,
            offset: offset,
          ),
        ),
        audioPlayerFactory: () {
          final player = FakeAudioPlayer();
          players.add(player);
          return player;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Play First track'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('playback-repeat')));
    await tester.pump();
    expect(find.byTooltip('Repeat all'), findsOneWidget);

    await tester.tap(find.byTooltip('Server settings'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('server-url-field')),
      'https://new.test',
    );
    await tester.tap(find.byKey(const Key('save-server-button')));
    await tester.pumpAndSettle();

    expect(players, hasLength(2));
    expect(players.first.disposed, isTrue);
    expect(find.text('Your library is empty.'), findsOneWidget);
    expect(find.text('Select a track to start listening.'), findsOneWidget);
    expect(find.byKey(const Key('playback-repeat')), findsNothing);
  });

  testWidgets('offline setting enables and requires confirmation to remove', (
    tester,
  ) async {
    final offline = FakeOfflineLibraryController(total: 1);
    await tester.pumpWidget(
      ArionApp(
        settingsStore: FakeSettingsStore(value: 'http://arion.test:8000'),
        catalogApiFactory: (_) => FakeCatalogApi(),
        audioPlayerFactory: FakeAudioPlayer.new,
        offlineLibraryFactory: (_) => offline,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Server settings'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('keep-library-offline')), findsOneWidget);
    expect(find.textContaining('current connection'), findsOneWidget);
    await tester.tap(find.byKey(const Key('keep-library-offline')));
    await tester.pumpAndSettle();
    expect(offline.enableCalls, 1);
    expect(find.textContaining('Preparing 0/1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('keep-library-offline')));
    await tester.pumpAndSettle();
    expect(find.text('Remove offline library?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(offline.disableCalls, 0);

    await tester.tap(find.byKey(const Key('keep-library-offline')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-disable-offline')));
    await tester.pumpAndSettle();
    expect(offline.disableCalls, 1);
  });

  testWidgets('changing server disables and disposes old offline session', (
    tester,
  ) async {
    final controllers = <FakeOfflineLibraryController>[];
    await tester.pumpWidget(
      ArionApp(
        settingsStore: FakeSettingsStore(value: 'http://old.test'),
        catalogApiFactory: (_) => FakeCatalogApi(),
        audioPlayerFactory: FakeAudioPlayer.new,
        offlineLibraryFactory: (_) {
          final value = FakeOfflineLibraryController(enabledValue: true);
          controllers.add(value);
          return value;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Server settings'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('server-url-field')),
      'https://new.test',
    );
    await tester.tap(find.byKey(const Key('save-server-button')));
    await tester.pumpAndSettle();

    expect(controllers, hasLength(2));
    expect(controllers.first.disableCalls, 1);
    expect(controllers.first.disposed, isTrue);
    expect(controllers.last.initializeCalls, 1);
  });

  testWidgets('offline settings distinguish readiness and failure states', (
    tester,
  ) async {
    final offline = FakeOfflineLibraryController(
      enabledValue: true,
      phaseValue: OfflineLibraryPhase.preparing,
      total: 2,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: OfflineLibrarySettings(controller: offline)),
      ),
    );
    expect(find.textContaining('Preparing 0/2'), findsOneWidget);

    offline.setPhase(OfflineLibraryPhase.ready, readyTrackIds: {'1', '2'});
    await tester.pump();
    expect(find.text('Ready offline: 2/2'), findsOneWidget);

    offline.setPhase(OfflineLibraryPhase.unavailable);
    await tester.pump();
    expect(find.textContaining('Server unavailable.'), findsOneWidget);
    expect(find.byKey(const Key('retry-offline-sync')), findsOneWidget);

    offline.setPhase(OfflineLibraryPhase.failed);
    await tester.pump();
    expect(find.textContaining('failed'), findsOneWidget);
    await tester.tap(find.byKey(const Key('retry-offline-sync')));
    expect(offline.retryCalls, 1);
  });
}
