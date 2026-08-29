import 'dart:convert';

import 'package:arion_client/library/catalog_api.dart';
import 'package:arion_client/library/acquisition.dart';
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

  Map<String, Object?> candidateJson({
    String videoId = 'abcdefghijk',
    String mode = 'music',
  }) => {
    'candidate_id': 'signed-candidate-token',
    'discovery_mode': mode,
    'video_id': videoId,
    'title': 'Candidate song',
    'channel': 'Candidate artist',
    'duration_seconds': 125,
    'thumbnail_url': 'https://i.ytimg.com/vi/$videoId/default.jpg',
    'page_url': 'https://www.youtube.com/watch?v=$videoId',
  };

  Map<String, Object?> jobJson({String state = 'queued'}) => {
    'id': '10000000-0000-0000-0000-000000000001',
    'state': state,
    'phase': state,
    'progress_percent': state == 'completed' ? 100 : 0,
    'attempts': 0,
    'candidate': {...candidateJson()}
      ..remove('candidate_id')
      ..remove('discovery_mode'),
    'track_id': state == 'completed'
        ? '00000000-0000-0000-0000-000000000001'
        : null,
    'failure_code': null,
    'failure_message': null,
    'created_at': '2026-08-24T00:00:00Z',
    'updated_at': '2026-08-24T00:00:00Z',
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

  test('discovers candidates using a trimmed encoded query', () async {
    late Uri requested;
    final api = ArionApi(
      baseUrl: sampleBaseUrl(),
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(
          jsonEncode({
            'items': [candidateJson()],
          }),
          200,
        );
      }),
    );

    final candidates = await api.discoverYouTube(
      '  AC/DC live  ',
      YouTubeDiscoveryMode.music,
    );

    expect(requested.path, '/api/v1/acquisition/youtube/candidates');
    expect(requested.queryParameters, {'q': 'AC/DC live', 'mode': 'music'});
    expect(candidates.single.title, 'Candidate song');
    expect(candidates.single.discoveryMode, YouTubeDiscoveryMode.music);
    expect(candidates.single.pageUrl.scheme, 'https');
  });

  test(
    'creates a job with only candidate and acknowledgement fields',
    () async {
      late http.Request sent;
      final api = ArionApi(
        baseUrl: sampleBaseUrl(),
        client: MockClient((request) async {
          sent = request;
          return http.Response(jsonEncode(jobJson()), 202);
        }),
      );

      final job = await api.createAcquisitionJob('signed-candidate-token');

      expect(sent.url.path, '/api/v1/acquisition/jobs');
      expect(sent.method, 'POST');
      expect(sent.headers['content-type'], 'application/json');
      expect(jsonDecode(sent.body), {
        'candidate_id': 'signed-candidate-token',
        'authorization_acknowledged': true,
      });
      expect(job.state, 'queued');
    },
  );

  test('polls a job and fetches its resulting track', () async {
    final paths = <String>[];
    final api = ArionApi(
      baseUrl: sampleBaseUrl(),
      client: MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path.startsWith('/api/v1/acquisition/jobs/')) {
          return http.Response(jsonEncode(jobJson(state: 'completed')), 200);
        }
        return http.Response(jsonEncode(trackJson()), 200);
      }),
    );

    final job = await api.fetchAcquisitionJob('job-id');
    final track = await api.fetchTrack(job.trackId!);

    expect(job.isCompleted, isTrue);
    expect(track.title, 'Title');
    expect(paths, [
      '/api/v1/acquisition/jobs/job-id',
      '/api/v1/tracks/00000000-0000-0000-0000-000000000001',
    ]);
  });

  test('preserves stable sanitized acquisition errors', () async {
    final api = ArionApi(
      baseUrl: sampleBaseUrl(),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'detail': {
              'code': 'youtube_acquisition_disabled',
              'message': 'YouTube acquisition is disabled.',
            },
          }),
          503,
        ),
      ),
    );

    await expectLater(
      api.discoverYouTube('missing', YouTubeDiscoveryMode.music),
      throwsA(
        isA<CatalogException>()
            .having(
              (error) => error.code,
              'code',
              'youtube_acquisition_disabled',
            )
            .having(
              (error) => error.message,
              'message',
              'YouTube acquisition is disabled.',
            ),
      ),
    );
  });

  test('rejects unsafe candidate URLs and malformed job data', () async {
    var call = 0;
    final api = ArionApi(
      baseUrl: sampleBaseUrl(),
      client: MockClient((_) async {
        call += 1;
        return call == 1
            ? http.Response(
                jsonEncode({
                  'items': [
                    {...candidateJson(), 'page_url': 'javascript:alert(1)'},
                  ],
                }),
                200,
              )
            : http.Response(
                jsonEncode({...jobJson(), 'attempts': 'zero'}),
                200,
              );
      }),
    );

    await expectLater(
      api.discoverYouTube('missing', YouTubeDiscoveryMode.music),
      throwsA(isA<CatalogException>()),
    );
    await expectLater(
      api.fetchAcquisitionJob('job-id'),
      throwsA(isA<CatalogException>()),
    );
  });

  test('rejects candidate responses from another discovery mode', () async {
    final api = ArionApi(
      baseUrl: sampleBaseUrl(),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'items': [candidateJson(mode: 'all')],
          }),
          200,
        ),
      ),
    );

    await expectLater(
      api.discoverYouTube('song', YouTubeDiscoveryMode.music),
      throwsA(isA<CatalogException>()),
    );
  });
}
