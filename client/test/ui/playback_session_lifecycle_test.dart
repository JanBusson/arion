import 'package:arion_client/app.dart';
import 'package:arion_client/library/track.dart';
import 'package:arion_client/playback/playback_controller.dart';
import 'package:arion_client/playback/playback_session_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  testWidgets('activity widget detachment does not dispose external playback', (
    tester,
  ) async {
    final player = FakeAudioPlayer();
    final playbackSession = PlaybackSessionCoordinator(
      createAudioPlayer: () => player,
    );
    await playbackSession.initialize();

    await tester.pumpWidget(
      ArionApp(
        settingsStore: FakeSettingsStore(value: 'http://arion.test:8000'),
        catalogApiFactory: (_) => FakeCatalogApi(
          handler: (limit, offset, query) async => TrackPage(
            items: [sampleTrack()],
            total: 1,
            limit: limit,
            offset: offset,
          ),
        ),
        audioPlayerFactory: () => player,
        playbackSession: playbackSession,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('Play First track'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final controller = playbackSession.controller!;
    controller.setRepeatMode(PlaybackRepeatMode.current);
    player.positions.add(const Duration(seconds: 17));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(player.disposed, isFalse);
    expect(playbackSession.controller, same(controller));
    expect(controller.queueEntries, hasLength(1));
    expect(controller.position, const Duration(seconds: 17));
    expect(controller.repeatMode, PlaybackRepeatMode.current);

    await tester.runAsync(playbackSession.close);
  });
}
