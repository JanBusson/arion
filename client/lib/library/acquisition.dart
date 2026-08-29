enum YouTubeDiscoveryMode {
  music('music'),
  all('all');

  const YouTubeDiscoveryMode(this.wireValue);

  final String wireValue;

  static YouTubeDiscoveryMode parse(Object? value) => switch (value) {
    'music' => YouTubeDiscoveryMode.music,
    'all' => YouTubeDiscoveryMode.all,
    _ => throw const FormatException('Invalid YouTube discovery mode.'),
  };
}

final class YouTubeCandidate {
  const YouTubeCandidate({
    required this.candidateId,
    required this.discoveryMode,
    required this.videoId,
    required this.title,
    required this.channel,
    required this.durationSeconds,
    required this.thumbnailUrl,
    required this.pageUrl,
  });

  factory YouTubeCandidate.fromJson(Map<String, Object?> json) =>
      YouTubeCandidate(
        candidateId: _requiredString(json, 'candidate_id'),
        discoveryMode: YouTubeDiscoveryMode.parse(json['discovery_mode']),
        videoId: _requiredString(json, 'video_id'),
        title: _requiredString(json, 'title'),
        channel: _requiredString(json, 'channel'),
        durationSeconds: _optionalInt(json, 'duration_seconds'),
        thumbnailUrl: _optionalUri(json, 'thumbnail_url'),
        pageUrl: _requiredHttpsUri(json, 'page_url'),
      );

  final String candidateId;
  final YouTubeDiscoveryMode? discoveryMode;
  final String videoId;
  final String title;
  final String channel;
  final int? durationSeconds;
  final Uri? thumbnailUrl;
  final Uri pageUrl;

  String get formattedDuration {
    final value = durationSeconds;
    if (value == null) return 'Unknown duration';
    final minutes = value ~/ 60;
    final seconds = value % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

final class AcquisitionJob {
  const AcquisitionJob({
    required this.id,
    required this.state,
    required this.phase,
    required this.progressPercent,
    required this.attempts,
    required this.candidate,
    required this.trackId,
    required this.failureCode,
    required this.failureMessage,
  });

  factory AcquisitionJob.fromJson(Map<String, Object?> json) {
    final candidate = json['candidate'];
    if (candidate is! Map<String, Object?>) {
      throw const FormatException('Job candidate must be an object.');
    }
    return AcquisitionJob(
      id: _requiredString(json, 'id'),
      state: _requiredString(json, 'state'),
      phase: _requiredString(json, 'phase'),
      progressPercent: _requiredInt(json, 'progress_percent'),
      attempts: _requiredInt(json, 'attempts'),
      candidate: YouTubeCandidate(
        candidateId: '',
        discoveryMode: null,
        videoId: _requiredString(candidate, 'video_id'),
        title: _requiredString(candidate, 'title'),
        channel: _requiredString(candidate, 'channel'),
        durationSeconds: _optionalInt(candidate, 'duration_seconds'),
        thumbnailUrl: _optionalUri(candidate, 'thumbnail_url'),
        pageUrl: _requiredHttpsUri(candidate, 'page_url'),
      ),
      trackId: _optionalString(json, 'track_id'),
      failureCode: _optionalString(json, 'failure_code'),
      failureMessage: _optionalString(json, 'failure_message'),
    );
  }

  final String id;
  final String state;
  final String phase;
  final int progressPercent;
  final int attempts;
  final YouTubeCandidate candidate;
  final String? trackId;
  final String? failureCode;
  final String? failureMessage;

  bool get isActive =>
      const {'queued', 'downloading', 'processing'}.contains(state);
  bool get isCompleted => state == 'completed';
  bool get isFailed => state == 'failed' || state == 'cancelled';
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw FormatException('$key must be null or a non-empty string.');
  }
  return value;
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('$key must be an integer.');
  return value;
}

int? _optionalInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! int) throw FormatException('$key must be null or an integer.');
  return value;
}

Uri _requiredHttpsUri(Map<String, Object?> json, String key) {
  final value = Uri.tryParse(_requiredString(json, key));
  if (value == null || value.scheme != 'https' || value.host.isEmpty) {
    throw FormatException('$key must be an HTTPS URL.');
  }
  return value;
}

Uri? _optionalUri(Map<String, Object?> json, String key) {
  if (json[key] == null) return null;
  return _requiredHttpsUri(json, key);
}
