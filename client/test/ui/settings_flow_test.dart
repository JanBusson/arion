import 'package:arion_client/app.dart';
import 'package:arion_client/library/track.dart';
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
}
