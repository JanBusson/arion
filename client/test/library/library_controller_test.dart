import 'dart:async';

import 'package:arion_client/library/catalog_api.dart';
import 'package:arion_client/library/library_controller.dart';
import 'package:arion_client/library/track.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
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
}
