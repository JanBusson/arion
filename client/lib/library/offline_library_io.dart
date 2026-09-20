import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../configuration/api_base_url.dart';
import '../configuration/resource_identity.dart';
import '../playback/offline_audio_resolver.dart';
import '../playback/playback_audio_cache.dart';
import '../playback/playback_audio_cache_io.dart';
import 'catalog_api.dart';
import 'offline_library.dart';
import 'track.dart';

typedef OfflineRootProvider = Future<Directory> Function();

Future<Directory> defaultOfflineRoot() async {
  final base = await getApplicationSupportDirectory();
  return Directory(_child(base.path, 'arion_offline_library'));
}

abstract interface class OfflinePreferenceStore {
  Future<bool> isEnabled(String normalizedServerUrl);
  Future<void> enable(String normalizedServerUrl);
  Future<void> disable(String normalizedServerUrl);
}

final class SharedPreferencesOfflinePreferenceStore
    implements OfflinePreferenceStore {
  SharedPreferencesOfflinePreferenceStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const _key = 'arion.offlineServer';
  final SharedPreferencesAsync _preferences;

  @override
  Future<bool> isEnabled(String normalizedServerUrl) async =>
      await _preferences.getString(_key) == normalizedServerUrl;

  @override
  Future<void> enable(String normalizedServerUrl) =>
      _preferences.setString(_key, normalizedServerUrl);

  @override
  Future<void> disable(String normalizedServerUrl) async {
    if (await isEnabled(normalizedServerUrl)) await _preferences.remove(_key);
  }
}

final class OfflineEntryPaths {
  const OfflineEntryPaths({
    required this.directory,
    required this.media,
    required this.partial,
    required this.length,
  });

  final Directory directory;
  final File media;
  final File partial;
  final File length;
}

final class OfflineLibraryFileStore implements OfflineCatalogSnapshotStore {
  OfflineLibraryFileStore({
    required this.baseUrl,
    this.rootProvider = defaultOfflineRoot,
  });

  final ApiBaseUrl baseUrl;
  final OfflineRootProvider rootProvider;

  String get normalizedServerUrl =>
      normalizeResourceUri(baseUrl.uri).toString();
  String get serverKey => resourceKey(baseUrl.uri);

  Future<Directory> get _serverDirectory async {
    final root = await rootProvider();
    return Directory(_child(root.path, serverKey));
  }

  Future<File> get _catalogFile async =>
      File(_child((await _serverDirectory).path, 'catalog.json'));

  Uri audioUri(String trackId) =>
      baseUrl.endpoint('/api/v1/tracks/$trackId/audio');

  Future<OfflineEntryPaths> pathsFor(Uri uri) async {
    final server = await _serverDirectory;
    final directory = Directory(
      _child(_child(server.path, 'tracks'), resourceKey(uri)),
    );
    return OfflineEntryPaths(
      directory: directory,
      media: File(_child(directory.path, 'audio.bin')),
      partial: File(_child(directory.path, 'audio.bin.part')),
      length: File(_child(directory.path, 'audio.length')),
    );
  }

  @override
  Future<OfflineCatalogSnapshot?> loadSnapshot() async {
    try {
      final file = await _catalogFile;
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final snapshot = OfflineCatalogSnapshot.fromJson(
        Map<String, Object?>.from(decoded),
      );
      if (snapshot.serverUrl != normalizedServerUrl ||
          snapshot.tracks.map((track) => track.id).toSet().length !=
              snapshot.tracks.length) {
        return null;
      }
      return snapshot;
    } on Object {
      return null;
    }
  }

  Future<void> commitSnapshot(OfflineCatalogSnapshot snapshot) async {
    if (snapshot.serverUrl != normalizedServerUrl) {
      throw ArgumentError('Snapshot belongs to a different server.');
    }
    final file = await _catalogFile;
    await _writeAtomic(file, jsonEncode(snapshot.toJson()));
  }

  Future<OfflineAudioFile?> verifiedAudio(Uri uri) async {
    try {
      final paths = await pathsFor(uri);
      if (!await paths.media.exists() || !await paths.length.exists()) {
        return null;
      }
      final expected = int.tryParse((await paths.length.readAsString()).trim());
      if (expected == null || expected <= 0) return null;
      final actual = await paths.media.length();
      if (actual != expected) return null;
      return OfflineAudioFile(
        key: resourceKey(uri),
        path: paths.media.path,
        length: actual,
      );
    } on Object {
      return null;
    }
  }

  Future<int> partialLength(Uri uri) async {
    final paths = await pathsFor(uri);
    if (!await paths.partial.exists()) return 0;
    return paths.partial.length();
  }

  Future<void> resetPartial(Uri uri) async {
    final paths = await pathsFor(uri);
    if (await paths.partial.exists()) await paths.partial.delete();
  }

  Future<void> publishPartial(Uri uri, int expectedLength) async {
    final paths = await pathsFor(uri);
    if (expectedLength <= 0 ||
        !await paths.partial.exists() ||
        await paths.partial.length() != expectedLength) {
      throw const FileSystemException('Incomplete offline audio.');
    }
    await paths.directory.create(recursive: true);
    if (await paths.media.exists()) await paths.media.delete();
    if (await paths.length.exists()) await paths.length.delete();
    await paths.partial.rename(paths.media.path);
    await _writeAtomic(paths.length, '$expectedLength');
  }

  Future<void> removeEntry(Uri uri) async {
    final paths = await pathsFor(uri);
    if (await paths.directory.exists()) {
      await paths.directory.delete(recursive: true);
    }
  }

  Future<void> retainTracks(Iterable<Track> tracks) async {
    final server = await _serverDirectory;
    final tracksDirectory = Directory(_child(server.path, 'tracks'));
    if (!await tracksDirectory.exists()) return;
    final retained = tracks
        .map((track) => resourceKey(audioUri(track.id)))
        .toSet();
    await for (final entity in tracksDirectory.list(followLinks: false)) {
      if (entity is! Directory || !retained.contains(_basename(entity.path))) {
        await entity.delete(recursive: true);
      }
    }
  }

  Future<Set<String>> inspectReady(Iterable<Track> tracks) async {
    final ready = <String>{};
    for (final track in tracks) {
      if (await verifiedAudio(audioUri(track.id)) != null) ready.add(track.id);
    }
    return ready;
  }

  Future<void> clear() async {
    final directory = await _serverDirectory;
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

final class AndroidOfflineAudioResolver implements OfflineAudioResolver {
  AndroidOfflineAudioResolver({this.rootProvider = defaultOfflineRoot});

  final OfflineRootProvider rootProvider;

  @override
  Future<OfflineAudioFile?> resolve(Uri uri) async {
    final baseUrl = _baseUrlFromAudioUri(uri);
    if (baseUrl == null) return null;
    return OfflineLibraryFileStore(
      baseUrl: baseUrl,
      rootProvider: rootProvider,
    ).verifiedAudio(uri);
  }

  @override
  Future<void> invalidate(Uri uri) async {
    final baseUrl = _baseUrlFromAudioUri(uri);
    if (baseUrl == null) return;
    await OfflineLibraryFileStore(
      baseUrl: baseUrl,
      rootProvider: rootProvider,
    ).removeEntry(uri);
  }

  @override
  Future<void> dispose() async {}
}

final class AndroidOfflineLibraryController extends OfflineLibraryController {
  AndroidOfflineLibraryController({
    required this.baseUrl,
    required this.catalogApi,
    required this.downloadClient,
    OfflineLibraryFileStore? store,
    OfflinePreferenceStore? preferences,
    PlaybackAudioCache? playbackCache,
    this.requestTimeout = const Duration(seconds: 30),
    this.workerCount = 2,
  }) : _store = store ?? OfflineLibraryFileStore(baseUrl: baseUrl),
       _preferences = preferences ?? SharedPreferencesOfflinePreferenceStore(),
       _playbackCache = playbackCache ?? createAndroidPlaybackCache();

  final ApiBaseUrl baseUrl;
  final CatalogApi catalogApi;
  final http.Client downloadClient;
  final OfflineLibraryFileStore _store;
  final OfflinePreferenceStore _preferences;
  final PlaybackAudioCache _playbackCache;
  final Duration requestTimeout;
  final int workerCount;

  bool _enabled = false;
  OfflineLibraryPhase _phase = OfflineLibraryPhase.disabled;
  int _completed = 0;
  int _total = 0;
  int _active = 0;
  String? _error;
  Set<String> _ready = {};
  OfflineCatalogSnapshot? _snapshot;
  Future<void>? _synchronizing;
  int _generation = 0;
  bool _disposed = false;

  @override
  bool get isSupported => true;
  @override
  bool get isEnabled => _enabled;
  @override
  OfflineLibraryPhase get phase => _phase;
  @override
  int get completedCount => _completed;
  @override
  int get totalCount => _total;
  @override
  int get activeCount => _active;
  @override
  String? get error => _error;
  @override
  Set<String> get readyTrackIds => Set.unmodifiable(_ready);

  @override
  Future<void> initialize() async {
    _snapshot = await _store.loadSnapshot();
    if (_snapshot case final snapshot?) {
      await _store.retainTracks(snapshot.tracks);
    }
    _enabled = await _preferences.isEnabled(_store.normalizedServerUrl);
    await _refreshReady();
    _phase = !_enabled
        ? OfflineLibraryPhase.disabled
        : _total > 0 && _completed == _total
        ? OfflineLibraryPhase.ready
        : OfflineLibraryPhase.preparing;
    _notify();
    if (_enabled) unawaited(synchronize());
  }

  @override
  Future<OfflineCatalogSnapshot?> loadSnapshot() async =>
      _snapshot ??= await _store.loadSnapshot();

  @override
  Future<void> enable() async {
    if (_enabled || _disposed) return;
    await _preferences.enable(_store.normalizedServerUrl);
    _enabled = true;
    _phase = OfflineLibraryPhase.preparing;
    _error = null;
    _notify();
    await synchronize();
  }

  @override
  Future<void> disable() async {
    if (_disposed) return;
    _enabled = false;
    _generation += 1;
    final active = _synchronizing;
    if (active != null) {
      try {
        await active;
      } on Object {
        // Cancellation intentionally wins over an obsolete transfer failure.
      }
    }
    await _preferences.disable(_store.normalizedServerUrl);
    await _store.clear();
    _snapshot = null;
    _ready = {};
    _completed = 0;
    _total = 0;
    _active = 0;
    _error = null;
    _phase = OfflineLibraryPhase.disabled;
    _notify();
  }

  @override
  Future<void> retry() => synchronize();

  @override
  Future<void> synchronize() {
    if (!_enabled || _disposed) return Future.value();
    final active = _synchronizing;
    if (active != null) return active;
    late final Future<void> run;
    run = _runSynchronization().whenComplete(() {
      if (identical(_synchronizing, run)) _synchronizing = null;
    });
    _synchronizing = run;
    return run;
  }

  Future<void> _runSynchronization() async {
    final generation = ++_generation;
    _phase = OfflineLibraryPhase.preparing;
    _error = null;
    _notify();
    try {
      final tracks = await _fetchCompleteCatalog(generation);
      _ensureCurrent(generation);
      final snapshot = OfflineCatalogSnapshot(
        serverUrl: _store.normalizedServerUrl,
        savedAt: DateTime.now().toUtc(),
        tracks: tracks,
      );
      await _store.commitSnapshot(snapshot);
      _ensureCurrent(generation);
      _snapshot = snapshot;
      await _store.retainTracks(tracks);
      await _refreshReady();
      _ensureCurrent(generation);
      final missing = tracks
          .where((track) => !_ready.contains(track.id))
          .toList();
      var next = 0;
      Future<void> worker() async {
        while (true) {
          _ensureCurrent(generation);
          if (next >= missing.length) return;
          final track = missing[next++];
          _active += 1;
          _notify();
          try {
            await _download(track, generation);
            _ensureCurrent(generation);
            _ready = {..._ready, track.id};
            _completed = _ready.length;
          } finally {
            _active -= 1;
            _notify();
          }
        }
      }

      await Future.wait(
        List.generate(workerCount.clamp(1, 2), (_) => worker()),
      );
      _ensureCurrent(generation);
      _phase = _completed == _total
          ? OfflineLibraryPhase.ready
          : OfflineLibraryPhase.failed;
    } on CatalogException catch (exception) {
      if (_isCurrent(generation)) {
        _phase = OfflineLibraryPhase.unavailable;
        _error = exception.message;
      }
    } on _SynchronizationCancelled {
      return;
    } on Object catch (exception) {
      if (_isCurrent(generation)) {
        _phase = OfflineLibraryPhase.failed;
        _error = _safeDownloadError(exception);
      }
    } finally {
      if (_isCurrent(generation)) _notify();
    }
  }

  Future<List<Track>> _fetchCompleteCatalog(int generation) async {
    final tracks = <Track>[];
    final ids = <String>{};
    var offset = 0;
    int? total;
    while (total == null || offset < total) {
      _ensureCurrent(generation);
      final page = await catalogApi.fetchTracks(limit: 100, offset: offset);
      _ensureCurrent(generation);
      total ??= page.total;
      if (page.offset != offset || page.total != total) {
        throw const CatalogException('The server catalog changed during sync.');
      }
      if (page.items.isEmpty && offset < total) {
        throw const CatalogException(
          'The server returned an incomplete catalog.',
        );
      }
      for (final track in page.items) {
        if (!ids.add(track.id)) {
          throw const CatalogException('The server returned duplicate tracks.');
        }
        tracks.add(track);
      }
      offset += page.items.length;
      if (tracks.length > total) {
        throw const CatalogException('The server returned an invalid catalog.');
      }
    }
    if (tracks.length != total) {
      throw const CatalogException(
        'The server returned an incomplete catalog.',
      );
    }
    return tracks;
  }

  Future<void> _download(Track track, int generation) async {
    final uri = _store.audioUri(track.id);
    final paths = await _store.pathsFor(uri);
    await paths.directory.create(recursive: true);
    final copied = await _playbackCache.exportComplete(uri, paths.partial.path);
    if (copied != null && copied > 0) {
      await _store.publishPartial(uri, copied);
      return;
    }

    var offset = await _store.partialLength(uri);
    for (var requestAttempt = 0; requestAttempt < 2; requestAttempt += 1) {
      final request = http.Request('GET', uri);
      if (offset > 0) request.headers['Range'] = 'bytes=$offset-';
      final response = await downloadClient
          .send(request)
          .timeout(requestTimeout);
      _ensureCurrent(generation);

      late final int expected;
      var append = false;
      if (response.statusCode == HttpStatus.partialContent) {
        final range = _parseContentRange(response.headers['content-range']);
        if (range == null || range.start != offset || range.total <= offset) {
          await _store.resetPartial(uri);
          offset = 0;
          if (requestAttempt == 0) continue;
          throw const HttpException('Incompatible audio range response.');
        }
        expected = range.total;
        append = offset > 0;
      } else if (response.statusCode == HttpStatus.ok) {
        if (offset > 0) await _store.resetPartial(uri);
        offset = 0;
        final length = response.contentLength;
        if (length == null || length <= 0) {
          throw const HttpException('Audio response has no valid length.');
        }
        expected = length;
      } else if (offset > 0 && requestAttempt == 0) {
        await _store.resetPartial(uri);
        offset = 0;
        continue;
      } else {
        throw HttpException('Audio download failed (${response.statusCode}).');
      }

      final sink = paths.partial.openWrite(
        mode: append ? FileMode.append : FileMode.write,
      );
      var received = offset;
      try {
        await for (final chunk in response.stream.timeout(requestTimeout)) {
          _ensureCurrent(generation);
          received += chunk.length;
          if (received > expected) {
            throw const HttpException(
              'Audio response exceeded expected length.',
            );
          }
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (received != expected || await paths.partial.length() != expected) {
        throw const HttpException('Audio response ended before completion.');
      }
      await _store.publishPartial(uri, expected);
      return;
    }
  }

  Future<void> _refreshReady() async {
    final tracks = _snapshot?.tracks ?? const <Track>[];
    _ready = await _store.inspectReady(tracks);
    _completed = _ready.length;
    _total = tracks.length;
  }

  bool _isCurrent(int generation) =>
      !_disposed && _enabled && generation == _generation;

  void _ensureCurrent(int generation) {
    if (!_isCurrent(generation)) throw const _SynchronizationCancelled();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation += 1;
    catalogApi.close();
    downloadClient.close();
    unawaited(_playbackCache.dispose());
    super.dispose();
  }
}

final class _SynchronizationCancelled implements Exception {
  const _SynchronizationCancelled();
}

({int start, int end, int total})? _parseContentRange(String? value) {
  if (value == null) return null;
  final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(value.trim());
  if (match == null) return null;
  final start = int.tryParse(match.group(1)!);
  final end = int.tryParse(match.group(2)!);
  final total = int.tryParse(match.group(3)!);
  if (start == null ||
      end == null ||
      total == null ||
      end < start ||
      end >= total) {
    return null;
  }
  return (start: start, end: end, total: total);
}

ApiBaseUrl? _baseUrlFromAudioUri(Uri uri) {
  final marker = '/api/v1/tracks/';
  final index = uri.path.indexOf(marker);
  if (index < 0) return null;
  try {
    return ApiBaseUrl.parse(
      uri
          .replace(
            path: uri.path.substring(0, index),
            query: null,
            fragment: null,
          )
          .toString(),
    );
  } on FormatException {
    return null;
  }
}

String _safeDownloadError(Object error) => switch (error) {
  FileSystemException _ => 'Offline storage is unavailable.',
  TimeoutException _ => 'The audio download timed out.',
  _ => 'One or more tracks could not be downloaded.',
};

Future<void> _writeAtomic(File file, String contents) async {
  await file.parent.create(recursive: true);
  final temporary = File('${file.path}.tmp');
  if (await temporary.exists()) await temporary.delete();
  final sink = temporary.openWrite(mode: FileMode.write);
  try {
    sink.write(contents);
    await sink.flush();
  } finally {
    await sink.close();
  }
  if (await file.exists()) await file.delete();
  await temporary.rename(file.path);
}

String _child(String parent, String child) =>
    '$parent${Platform.pathSeparator}$child';

String _basename(String path) =>
    path.substring(path.lastIndexOf(Platform.pathSeparator) + 1);
