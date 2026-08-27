import 'package:arion_client/library/catalog_api.dart';
import 'package:arion_client/library/library_controller.dart';
import 'package:arion_client/library/track.dart';
import 'package:arion_client/playback/audio_player_port.dart';
import 'package:arion_client/playback/playback_controller.dart';
import 'package:arion_client/ui/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  Future<void> pumpLibrary(
    WidgetTester tester, {
    required FakeCatalogApi api,
    required FakeAudioPlayer player,
    Size size = const Size(400, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          library: LibraryController(api),
          playback: PlaybackController(player),
          api: api,
          onOpenSettings: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(360, 760), const Size(1280, 900)]) {
    testWidgets('populated library fits ${size.width.toInt()}px width', (
      tester,
    ) async {
      final tracks = [
        sampleTrack(hasCover: false),
        sampleTrack(
          id: '2',
          title: 'A very long title that must remain usable',
        ),
      ];
      final api = FakeCatalogApi(
        handler: (limit, offset, query) async => TrackPage(
          items: tracks,
          total: tracks.length,
          limit: limit,
          offset: offset,
        ),
      );

      await pumpLibrary(
        tester,
        api: api,
        player: FakeAudioPlayer(),
        size: size,
      );

      expect(find.text('First track'), findsOneWidget);
      expect(find.byIcon(Icons.music_note), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('shows loading then an empty search state', (tester) async {
    final api = FakeCatalogApi();
    await pumpLibrary(tester, api: api, player: FakeAudioPlayer());

    await tester.enterText(
      find.byKey(const Key('library-search-field')),
      'missing',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('No tracks match “missing”.'), findsOneWidget);
  });

  testWidgets('shows request failure and retries', (tester) async {
    var fails = true;
    final api = FakeCatalogApi(
      handler: (limit, offset, query) async {
        if (fails) {
          throw const CatalogException('Server unavailable');
        }
        return TrackPage(
          items: const [],
          total: 0,
          limit: limit,
          offset: offset,
        );
      },
    );
    await pumpLibrary(tester, api: api, player: FakeAudioPlayer());

    expect(find.text('Server unavailable'), findsOneWidget);
    fails = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Your library is empty.'), findsOneWidget);
  });

  testWidgets('loads another page from the paging control', (tester) async {
    final api = FakeCatalogApi(
      handler: (limit, offset, query) async => TrackPage(
        items: offset == 0
            ? [sampleTrack()]
            : [sampleTrack(id: '2', title: 'Second')],
        total: 2,
        limit: limit,
        offset: offset,
      ),
    );
    await pumpLibrary(tester, api: api, player: FakeAudioPlayer());

    await tester.tap(find.byKey(const Key('load-more-button')));
    await tester.pumpAndSettle();

    expect(find.text('Second'), findsOneWidget);
  });

  testWidgets('reviews multiple candidates without preselecting one', (
    tester,
  ) async {
    final candidates = [
      sampleCandidate(title: 'First candidate'),
      sampleCandidate(
        candidateId: 'another-signed-token',
        videoId: 'lmnopqrstuv',
        title: 'Second candidate',
      ),
    ];
    final api = FakeCatalogApi(discoveryHandler: (_) async => candidates);
    await pumpLibrary(tester, api: api, player: FakeAudioPlayer());
    await tester.enterText(
      find.byKey(const Key('library-search-field')),
      'missing',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Search YouTube'), findsOneWidget);
    expect(api.discoveryCalls, isEmpty);
    await tester.tap(find.text('Search YouTube'));
    await tester.pumpAndSettle();

    expect(find.text('First candidate'), findsOneWidget);
    expect(find.text('Second candidate'), findsOneWidget);
    expect(find.textContaining('correct', findRichText: true), findsNothing);
    expect(api.createdCandidates, isEmpty);
  });

  testWidgets('requires selection and authorization before creating a job', (
    tester,
  ) async {
    final player = FakeAudioPlayer();
    final api = FakeCatalogApi(
      discoveryHandler: (_) async => [sampleCandidate()],
      createJobHandler: (_) async => sampleAcquisitionJob(
        state: 'completed',
        phase: 'completed',
        progressPercent: 100,
        trackId: 'downloaded-track',
      ),
    );
    await pumpLibrary(tester, api: api, player: player);
    await tester.enterText(
      find.byKey(const Key('library-search-field')),
      'missing',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search YouTube'));
    await tester.pumpAndSettle();

    expect(api.createdCandidates, isEmpty);
    await tester.tap(find.byKey(const Key('select-candidate-abcdefghijk')));
    await tester.pumpAndSettle();
    final acquire = tester.widget<FilledButton>(
      find.byKey(const Key('confirm-acquisition-button')),
    );
    expect(acquire.onPressed, isNull);
    expect(api.createdCandidates, isEmpty);

    await tester.tap(
      find.byKey(const Key('acquisition-authorization-checkbox')),
    );
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('confirm-acquisition-button')),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('confirm-acquisition-button')));
    await tester.pumpAndSettle();

    expect(api.createdCandidates, ['signed-candidate-token']);
    expect(find.text('First track'), findsOneWidget);
    expect(player.playCalls, 0);
  });

  testWidgets('shows active progress and terminal failure safely', (
    tester,
  ) async {
    final api = FakeCatalogApi(
      discoveryHandler: (_) async => [sampleCandidate()],
      createJobHandler: (_) async => sampleAcquisitionJob(),
      fetchJobHandler: (_) async => sampleAcquisitionJob(
        state: 'failed',
        phase: 'failed',
        failureMessage: 'This item could not be acquired.',
      ),
    );
    final controller = LibraryController(
      api,
      jobPollInterval: const Duration(milliseconds: 1),
    );
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: LibraryScreen(
          library: controller,
          playback: PlaybackController(FakeAudioPlayer()),
          api: api,
          onOpenSettings: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('library-search-field')),
      'missing',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search YouTube'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('select-candidate-abcdefghijk')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('acquisition-authorization-checkbox')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-acquisition-button')));
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('This item could not be acquired.'), findsOneWidget);
  });

  testWidgets(
    'player UI supports selection, seeking, replacement and recovery',
    (tester) async {
      final tracks = [sampleTrack(), sampleTrack(id: '2', title: 'Second')];
      final api = FakeCatalogApi(
        handler: (limit, offset, query) async =>
            TrackPage(items: tracks, total: 2, limit: limit, offset: offset),
      );
      final player = FakeAudioPlayer();
      await pumpLibrary(tester, api: api, player: player);

      await tester.tap(find.byTooltip('Play First track'));
      await tester.pumpAndSettle();
      expect(player.currentUrl.toString(), contains('/audio/'));
      expect(find.byKey(const Key('playback-toggle')), findsOneWidget);

      player.positions.add(const Duration(seconds: 30));
      await tester.pump();
      final slider = tester.widget<Slider>(
        find.byKey(const Key('playback-seek')),
      );
      slider.onChanged!(60 * 1000);
      await tester.pump();
      expect(player.lastSeek, const Duration(minutes: 1));

      await tester.tap(find.byTooltip('Play Second'));
      await tester.pumpAndSettle();
      expect(find.text('Second'), findsWidgets);

      player.processing.add(AudioProcessingState.completed);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Replay'), findsOneWidget);

      player.errors.add(StateError('private'));
      await tester.pumpAndSettle();
      expect(find.text('This track could not be played.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('playback-retry')));
      await tester.pumpAndSettle();
      expect(find.text('This track could not be played.'), findsNothing);
    },
  );
}
