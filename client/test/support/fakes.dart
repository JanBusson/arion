import 'dart:async';

import 'package:arion_client/configuration/api_base_url.dart';
import 'package:arion_client/configuration/settings_store.dart';
import 'package:arion_client/library/catalog_api.dart';
import 'package:arion_client/library/acquisition.dart';
import 'package:arion_client/library/acquisition_job_store.dart';
import 'package:arion_client/library/track.dart';
import 'package:arion_client/playback/audio_player_port.dart';

final class FakeSettingsStore implements SettingsStore {
  FakeSettingsStore({this.value, this.readError, this.writeError});

  String? value;
  Object? readError;
  Object? writeError;

  @override
  Future<String?> readBaseUrl() async {
    if (readError != null) {
      throw readError!;
    }
    return value;
  }

  @override
  Future<void> writeBaseUrl(String value) async {
    if (writeError != null) {
      throw writeError!;
    }
    this.value = value;
  }
}

typedef FetchHandler =
    Future<TrackPage> Function(int limit, int offset, String? query);
typedef DiscoveryHandler =
    Future<List<YouTubeCandidate>> Function(
      String query,
      YouTubeDiscoveryMode mode,
    );
typedef CreateJobHandler = Future<AcquisitionJob> Function(String candidateId);
typedef FetchJobHandler = Future<AcquisitionJob> Function(String jobId);

final class FakeCatalogApi implements CatalogApi {
  FakeCatalogApi({
    FetchHandler? handler,
    DiscoveryHandler? discoveryHandler,
    CreateJobHandler? createJobHandler,
    FetchJobHandler? fetchJobHandler,
  }) : handler =
           handler ??
           ((limit, offset, query) async => TrackPage(
             items: const [],
             total: 0,
             limit: limit,
             offset: offset,
           )),
       discoveryHandler = discoveryHandler ?? ((_, _) async => const []),
       createJobHandler =
           createJobHandler ?? ((_) async => sampleAcquisitionJob()),
       fetchJobHandler =
           fetchJobHandler ?? ((_) async => sampleAcquisitionJob());

  FetchHandler handler;
  DiscoveryHandler discoveryHandler;
  CreateJobHandler createJobHandler;
  FetchJobHandler fetchJobHandler;
  final List<({int limit, int offset, String? query})> calls = [];
  final List<({String query, YouTubeDiscoveryMode mode})> discoveryCalls = [];
  final List<String> createdCandidates = [];
  final List<String> fetchedJobs = [];
  bool closed = false;

  @override
  Future<TrackPage> fetchTracks({
    int limit = 30,
    int offset = 0,
    String? query,
  }) {
    calls.add((limit: limit, offset: offset, query: query));
    return handler(limit, offset, query);
  }

  @override
  Future<Track> fetchTrack(String trackId) async => sampleTrack(id: trackId);

  @override
  Future<List<YouTubeCandidate>> discoverYouTube(
    String query,
    YouTubeDiscoveryMode mode,
  ) {
    discoveryCalls.add((query: query, mode: mode));
    return discoveryHandler(query, mode);
  }

  @override
  Future<AcquisitionJob> createAcquisitionJob(String candidateId) {
    createdCandidates.add(candidateId);
    return createJobHandler(candidateId);
  }

  @override
  Future<AcquisitionJob> fetchAcquisitionJob(String jobId) {
    fetchedJobs.add(jobId);
    return fetchJobHandler(jobId);
  }

  @override
  Uri audioUri(String trackId) => Uri.parse('http://arion.test/audio/$trackId');

  @override
  Uri coverUri(String trackId) => Uri.parse('http://arion.test/cover/$trackId');

  @override
  void close() => closed = true;
}

final class FakeAcquisitionJobStore implements AcquisitionJobStore {
  String? value;

  @override
  Future<String?> readActiveJobId() async => value;

  @override
  Future<void> writeActiveJobId(String jobId) async => value = jobId;

  @override
  Future<void> clearActiveJobId() async => value = null;
}

final class FakeAudioPlayer implements AudioPlayerPort {
  final StreamController<bool> playing = StreamController.broadcast();
  final StreamController<AudioProcessingState> processing =
      StreamController.broadcast();
  final StreamController<Duration> positions = StreamController.broadcast();
  final StreamController<Duration?> durations = StreamController.broadcast();
  final StreamController<Object> errors = StreamController.broadcast();

  Duration? sourceDuration = const Duration(minutes: 3);
  Object? setUrlError;
  Object? playError;
  Uri? currentUrl;
  Duration? lastSeek;
  int playCalls = 0;
  int pauseCalls = 0;
  bool disposed = false;

  @override
  Stream<bool> get playingStream => playing.stream;

  @override
  Stream<AudioProcessingState> get processingStateStream => processing.stream;

  @override
  Stream<Duration> get positionStream => positions.stream;

  @override
  Stream<Duration?> get durationStream => durations.stream;

  @override
  Stream<Object> get errorStream => errors.stream;

  @override
  Future<Duration?> setUrl(Uri uri) async {
    if (setUrlError != null) {
      throw setUrlError!;
    }
    currentUrl = uri;
    processing.add(AudioProcessingState.ready);
    return sourceDuration;
  }

  @override
  Future<void> play() async {
    playCalls += 1;
    if (playError != null) {
      throw playError!;
    }
    playing.add(true);
  }

  @override
  Future<void> pause() async {
    pauseCalls += 1;
    playing.add(false);
  }

  @override
  Future<void> seek(Duration position) async {
    lastSeek = position;
    positions.add(position);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await playing.close();
    await processing.close();
    await positions.close();
    await durations.close();
    await errors.close();
  }
}

Track sampleTrack({
  String id = '00000000-0000-0000-0000-000000000001',
  String title = 'First track',
  bool hasCover = false,
  int durationMs = 125000,
}) => Track(
  id: id,
  title: title,
  artist: 'Example Artist',
  album: 'Example Album',
  durationMs: durationMs,
  codec: 'flac',
  bitrateKbps: 700,
  sampleRateHz: 44100,
  originalFilename: '$title.flac',
  hasCover: hasCover,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

ApiBaseUrl sampleBaseUrl() => ApiBaseUrl.parse('http://arion.test:8000');

YouTubeCandidate sampleCandidate({
  String candidateId = 'signed-candidate-token',
  String videoId = 'abcdefghijk',
  String title = 'Candidate song',
  YouTubeDiscoveryMode discoveryMode = YouTubeDiscoveryMode.music,
}) => YouTubeCandidate(
  candidateId: candidateId,
  discoveryMode: discoveryMode,
  videoId: videoId,
  title: title,
  channel: 'Candidate artist',
  durationSeconds: 125,
  thumbnailUrl: Uri.parse('https://i.ytimg.com/vi/$videoId/default.jpg'),
  pageUrl: Uri.parse('https://www.youtube.com/watch?v=$videoId'),
);

AcquisitionJob sampleAcquisitionJob({
  String id = '10000000-0000-0000-0000-000000000001',
  String state = 'queued',
  String phase = 'queued',
  int progressPercent = 0,
  String? trackId,
  String? failureCode,
  String? failureMessage,
}) => AcquisitionJob(
  id: id,
  state: state,
  phase: phase,
  progressPercent: progressPercent,
  attempts: 0,
  candidate: sampleCandidate(),
  trackId: trackId,
  failureCode: failureCode,
  failureMessage: failureMessage,
);
