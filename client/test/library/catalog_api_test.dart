import 'dart:convert';

import 'package:arion_client/library/catalog_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../support/fakes.dart';

void main() {
  Map<String, Object?> trackJson() => {
    'id': '00000000-0000-0000-0000-000000000001',
    'title': 'Title',
    'artist': 'Artist',
    'album': 'Album',
    'duration_ms': 1000,
    'codec': 'flac',
    'bitrate_kbps': null,
    'sample_rate_hz': 44100,
    'original_filename': 'track.flac',
    'has_cover': false,
    'created_at': '2026-08-23T00:00:00Z',
    'updated_at': '2026-08-23T00:00:00Z',
  };

  test('encodes query and pagination and parses success', () async {
    late Uri requested;
    final api = ArionApi(
      baseUrl: sampleBaseUrl(),
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(
          jsonEncode({
            'items': [trackJson()],
            'total': 4,
            'limit': 2,
            'offset': 2,
          }),
          200,
        );
      }),
    );

    final page = await api.fetchTracks(
      limit: 2,
      offset: 2,
      query: 'AC/DC live',
    );

    expect(requested.path, '/api/v1/tracks');
    expect(requested.queryParameters, {
      'limit': '2',
      'offset': '2',
      'q': 'AC/DC live',
    });
    expect(page.items.single.title, 'Title');
    expect(page.total, 4);
    expect(api.coverUri('abc').path, '/api/v1/tracks/abc/cover');
    expect(api.audioUri('abc').path, '/api/v1/tracks/abc/audio');
  });

  test('maps non-success response to a safe failure', () async {
    final api = ArionApi(
      baseUrl: sampleBaseUrl(),
      client: MockClient((_) async => http.Response('private details', 500)),
    );

    await expectLater(api.fetchTracks(), throwsA(isA<CatalogException>()));
  });

  test('maps malformed JSON to a safe failure', () async {
    final api = ArionApi(
      baseUrl: sampleBaseUrl(),
      client: MockClient((_) async => http.Response('{bad json', 200)),
    );

    await expectLater(
      api.fetchTracks(),
      throwsA(
        isA<CatalogException>().having(
          (error) => error.message,
          'message',
          contains('invalid'),
        ),
      ),
    );
  });

  test('applies a bounded request timeout', () async {
    final api = ArionApi(
      baseUrl: sampleBaseUrl(),
      timeout: const Duration(milliseconds: 1),
      client: MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      api.fetchTracks(),
      throwsA(
        isA<CatalogException>().having(
          (error) => error.message,
          'message',
          contains('too long'),
        ),
      ),
    );
  });
}
