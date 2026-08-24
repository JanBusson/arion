final class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.codec,
    required this.bitrateKbps,
    required this.sampleRateHz,
    required this.originalFilename,
    required this.hasCover,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Track.fromJson(Map<String, Object?> json) {
    return Track(
      id: _required<String>(json, 'id'),
      title: _required<String>(json, 'title'),
      artist: _required<String>(json, 'artist'),
      album: _required<String>(json, 'album'),
      durationMs: _required<int>(json, 'duration_ms'),
      codec: _required<String>(json, 'codec'),
      bitrateKbps: _nullable<int>(json, 'bitrate_kbps'),
      sampleRateHz: _required<int>(json, 'sample_rate_hz'),
      originalFilename: _required<String>(json, 'original_filename'),
      hasCover: _required<bool>(json, 'has_cover'),
      createdAt: _dateTime(json, 'created_at'),
      updatedAt: _dateTime(json, 'updated_at'),
    );
  }

  final String id;
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final String codec;
  final int? bitrateKbps;
  final int sampleRateHz;
  final String originalFilename;
  final bool hasCover;
  final DateTime createdAt;
  final DateTime updatedAt;

  Duration get duration => Duration(milliseconds: durationMs);
  String get formattedDuration => formatDuration(duration);
}

final class TrackPage {
  const TrackPage({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
  });

  factory TrackPage.fromJson(Map<String, Object?> json) {
    final rawItems = _required<List<Object?>>(json, 'items');
    return TrackPage(
      items: rawItems
          .map((item) {
            if (item is! Map<String, Object?>) {
              throw const FormatException('Track item must be an object.');
            }
            return Track.fromJson(item);
          })
          .toList(growable: false),
      total: _required<int>(json, 'total'),
      limit: _required<int>(json, 'limit'),
      offset: _required<int>(json, 'offset'),
    );
  }

  final List<Track> items;
  final int total;
  final int limit;
  final int offset;
}

T _required<T>(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! T) {
    throw FormatException('Field "$key" is missing or has the wrong type.');
  }
  return value;
}

T? _nullable<T>(Map<String, Object?> json, String key) {
  if (!json.containsKey(key)) {
    throw FormatException('Field "$key" is missing.');
  }
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! T) {
    throw FormatException('Field "$key" has the wrong type.');
  }
  return value as T;
}

DateTime _dateTime(Map<String, Object?> json, String key) {
  final value = _required<String>(json, key);
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('Field "$key" is not a timestamp.');
  }
  return parsed;
}

String formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds.clamp(0, 359999);
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  final minutes = ((totalSeconds ~/ 60) % 60).toString().padLeft(2, '0');
  final hours = totalSeconds ~/ 3600;
  return hours > 0
      ? '$hours:$minutes:$seconds'
      : '${totalSeconds ~/ 60}:$seconds';
}
