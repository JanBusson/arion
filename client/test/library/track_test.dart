import 'package:arion_client/library/track.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object?> completeJson() => {
    'id': '00000000-0000-0000-0000-000000000001',
    'title': 'Title',
    'artist': 'Artist',
    'album': 'Album',
    'duration_ms': 3723000,
    'codec': 'flac',
    'bitrate_kbps': 700,
    'sample_rate_hz': 44100,
    'original_filename': 'track.flac',
    'has_cover': true,
    'created_at': '2026-08-23T00:00:00Z',
    'updated_at': '2026-08-23T00:00:00Z',
  };

  test('parses complete API values and formats duration', () {
    final track = Track.fromJson(completeJson());

    expect(track.title, 'Title');
    expect(track.hasCover, isTrue);
    expect(track.formattedDuration, '1:02:03');
    expect(formatDuration(const Duration(seconds: 65)), '1:05');
  });

  test('rejects a missing required field', () {
    final json = completeJson()..remove('artist');

    expect(() => Track.fromJson(json), throwsFormatException);
  });

  test('rejects an incorrectly typed field', () {
    final json = completeJson()..['duration_ms'] = '3723000';

    expect(() => Track.fromJson(json), throwsFormatException);
  });

  test('page parser rejects a non-list items value', () {
    expect(
      () => TrackPage.fromJson({
        'items': <String, Object?>{},
        'total': 0,
        'limit': 30,
        'offset': 0,
      }),
      throwsFormatException,
    );
  });
}
