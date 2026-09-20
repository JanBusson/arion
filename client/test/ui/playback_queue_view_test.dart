import 'package:arion_client/playback/playback_controller.dart';
import 'package:arion_client/ui/now_playing_panel.dart';
import 'package:arion_client/ui/playback_queue_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  Future<PlaybackController> pumpPlayer(
    WidgetTester tester, {
    required Size size,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = PlaybackController(FakeAudioPlayer());
    final first = sampleTrack(id: '1', title: 'First');
    final duplicate = sampleTrack(id: '2', title: 'Duplicate');
    await controller.playNow(first, Uri.parse('http://arion.test/audio/1'));
    await controller.addToQueue(
      duplicate,
      Uri.parse('http://arion.test/audio/2'),
    );
    await controller.addToQueue(
      duplicate,
      Uri.parse('http://arion.test/audio/2'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox()),
              NowPlayingPanel(controller: controller),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('shows an empty queue state', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaybackQueueView(
            controller: PlaybackController(FakeAudioPlayer()),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('queue-empty-state')), findsOneWidget);
  });

  testWidgets('narrow queue surface reorders and removes duplicate entries', (
    tester,
  ) async {
    final controller = await pumpPlayer(tester, size: const Size(360, 760));
    final firstDuplicateId = controller.upcomingEntries.first.id;
    final secondDuplicateId = controller.upcomingEntries.last.id;

    await tester.tap(find.byKey(const Key('open-playback-queue')));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byKey(const Key('upcoming-queue-list')), findsOneWidget);
    expect(find.byIcon(Icons.drag_handle), findsNWidgets(2));
    final list = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    list.onReorderItem!(1, 0);
    await tester.pump();
    expect(controller.upcomingEntries.first.id, secondDuplicateId);

    await tester.tap(find.byKey(Key('remove-queue-entry-$firstDuplicateId')));
    await tester.pump();
    expect(controller.upcomingEntries, hasLength(1));
    expect(controller.upcomingEntries.single.id, secondDuplicateId);
    expect(controller.currentEntry!.track.title, 'First');
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide queue surface uses a constrained dialog', (tester) async {
    await pumpPlayer(tester, size: const Size(1280, 900));

    await tester.tap(find.byKey(const Key('open-playback-queue')));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Playback queue'), findsOneWidget);
    expect(find.byTooltip('Close queue'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
