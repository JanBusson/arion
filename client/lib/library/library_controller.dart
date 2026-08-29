import 'dart:async';

import 'package:flutter/foundation.dart';

import 'acquisition.dart';
import 'acquisition_job_store.dart';
import 'catalog_api.dart';
import 'track.dart';

final class LibraryController extends ChangeNotifier {
  LibraryController(
    this._api, {
    this.pageSize = 30,
    AcquisitionJobStore? jobStore,
    this.jobPollInterval = const Duration(seconds: 2),
  }) : _jobStore = jobStore ?? MemoryAcquisitionJobStore();

  final CatalogApi _api;
  final AcquisitionJobStore _jobStore;
  final int pageSize;
  final Duration jobPollInterval;

  final List<Track> _items = [];
  String _query = '';
  int _total = 0;
  int _generation = 0;
  bool _isInitialLoading = false;
  bool _isLoadingMore = false;
  String? _error;
  final List<YouTubeCandidate> _candidates = [];
  bool _isDiscovering = false;
  String? _acquisitionError;
  AcquisitionJob? _activeJob;
  int _acquisitionGeneration = 0;
  int _discoveryGeneration = 0;
  YouTubeDiscoveryMode _discoveryMode = YouTubeDiscoveryMode.music;
  bool _resumeStarted = false;
  bool _disposed = false;

  List<Track> get items => List.unmodifiable(_items);
  String get query => _query;
  int get total => _total;
  bool get isInitialLoading => _isInitialLoading;
  bool get isLoadingMore => _isLoadingMore;
  String? get error => _error;
  bool get hasMore => _items.length < _total;
  bool get isEmpty => !_isInitialLoading && _error == null && _items.isEmpty;
  CatalogApi get api => _api;
  List<YouTubeCandidate> get candidates => List.unmodifiable(_candidates);
  bool get isDiscovering => _isDiscovering;
  String? get acquisitionError => _acquisitionError;
  AcquisitionJob? get activeJob => _activeJob;
  YouTubeDiscoveryMode get discoveryMode => _discoveryMode;
  String get discoveryActionLabel => switch (_discoveryMode) {
    YouTubeDiscoveryMode.music => 'Search YouTube Music',
    YouTubeDiscoveryMode.all => 'Search all YouTube',
  };
  String get discoveryRetryLabel => switch (_discoveryMode) {
    YouTubeDiscoveryMode.music => 'Retry YouTube Music search',
    YouTubeDiscoveryMode.all => 'Retry all YouTube search',
  };
  bool get canSearchYouTube =>
      _query.isNotEmpty &&
      isEmpty &&
      !_isDiscovering &&
      _activeJob?.isActive != true;

  Future<void> loadInitial() async {
    final load = _resetAndLoad(_query);
    if (!_resumeStarted) {
      _resumeStarted = true;
      unawaited(_resumeRememberedJob());
    }
    await load;
  }

  Future<void> submitSearch(String value) => _resetAndLoad(value.trim());

  Future<void> clearSearch() => _resetAndLoad('');

  Future<void> retry() => _resetAndLoad(_query);

  void setDiscoveryMode(YouTubeDiscoveryMode mode) {
    if (mode == _discoveryMode) return;
    _discoveryMode = mode;
    _discoveryGeneration += 1;
    _candidates.clear();
    _acquisitionError = null;
    _isDiscovering = false;
    notifyListeners();
  }

  Future<void> _resetAndLoad(String query) async {
    final generation = ++_generation;
    _discoveryGeneration += 1;
    _query = query;
    _items.clear();
    _total = 0;
    _error = null;
    _candidates.clear();
    _acquisitionError = null;
    if (_activeJob?.isActive != true) {
      _activeJob = null;
    }
    _isInitialLoading = true;
    _isLoadingMore = false;
    notifyListeners();
    try {
      final page = await _api.fetchTracks(
        limit: pageSize,
        query: query.isEmpty ? null : query,
      );
      if (generation != _generation || query != _query) {
        return;
      }
      _items.addAll(_unique(page.items));
      _total = page.total;
    } on CatalogException catch (error) {
      if (generation == _generation) {
        _error = error.message;
      }
    } on Object {
      if (generation == _generation) {
        _error = 'The library could not be loaded.';
      }
    } finally {
      if (generation == _generation) {
        _isInitialLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> discoverYouTube() async {
    if (!canSearchYouTube) return;
    final generation = ++_discoveryGeneration;
    final query = _query;
    final mode = _discoveryMode;
    _candidates.clear();
    _acquisitionError = null;
    _isDiscovering = true;
    notifyListeners();
    try {
      final candidates = await _api.discoverYouTube(query, mode);
      if (generation != _discoveryGeneration ||
          query != _query ||
          mode != _discoveryMode ||
          !isEmpty) {
        return;
      }
      _candidates.addAll(candidates);
    } on CatalogException catch (error) {
      if (generation == _discoveryGeneration && mode == _discoveryMode) {
        _acquisitionError = error.code == 'youtube_acquisition_disabled'
            ? 'YouTube acquisition is disabled on this server.'
            : error.message;
      }
    } on Object {
      if (generation == _discoveryGeneration && mode == _discoveryMode) {
        _acquisitionError = 'YouTube candidates could not be loaded.';
      }
    } finally {
      if (generation == _discoveryGeneration && mode == _discoveryMode) {
        _isDiscovering = false;
        notifyListeners();
      }
    }
  }

  Future<void> startAcquisition(YouTubeCandidate candidate) async {
    if (_activeJob?.isActive == true) return;
    final generation = ++_acquisitionGeneration;
    _acquisitionError = null;
    notifyListeners();
    try {
      final job = await _api.createAcquisitionJob(candidate.candidateId);
      if (generation != _acquisitionGeneration) return;
      _activeJob = job;
      _candidates.clear();
      if (job.isActive) {
        await _jobStore.writeActiveJobId(job.id);
        unawaited(_pollJob(job.id, generation));
      } else {
        await _finishJob(job, generation);
      }
    } on CatalogException catch (error) {
      if (generation == _acquisitionGeneration) {
        _acquisitionError = error.message;
      }
    } on Object {
      if (generation == _acquisitionGeneration) {
        _acquisitionError = 'The acquisition job could not be created.';
      }
    } finally {
      if (generation == _acquisitionGeneration) notifyListeners();
    }
  }

  Future<void> _resumeRememberedJob() async {
    try {
      final jobId = await _jobStore.readActiveJobId();
      if (jobId == null || _disposed) return;
      final generation = ++_acquisitionGeneration;
      final job = await _api.fetchAcquisitionJob(jobId);
      if (_disposed || generation != _acquisitionGeneration) return;
      _activeJob = job;
      _acquisitionError = null;
      notifyListeners();
      if (job.isActive) {
        unawaited(_pollJob(job.id, generation));
      } else {
        await _finishJob(job, generation);
      }
    } on Object {
      await _jobStore.clearActiveJobId();
    }
  }

  Future<void> _pollJob(String jobId, int generation) async {
    while (!_disposed && generation == _acquisitionGeneration) {
      await Future<void>.delayed(jobPollInterval);
      if (_disposed || generation != _acquisitionGeneration) return;
      try {
        final job = await _api.fetchAcquisitionJob(jobId);
        if (_disposed || generation != _acquisitionGeneration) return;
        _activeJob = job;
        _acquisitionError = null;
        notifyListeners();
        if (!job.isActive) {
          await _finishJob(job, generation);
          return;
        }
      } on CatalogException catch (error) {
        if (generation == _acquisitionGeneration) {
          _acquisitionError = error.message;
          notifyListeners();
        }
      } on Object {
        if (generation == _acquisitionGeneration) {
          _acquisitionError = 'Job progress could not be refreshed.';
          notifyListeners();
        }
      }
    }
  }

  Future<void> _finishJob(AcquisitionJob job, int generation) async {
    if (generation != _acquisitionGeneration) return;
    _activeJob = job;
    await _jobStore.clearActiveJobId();
    if (job.isCompleted && job.trackId != null) {
      try {
        final track = await _api.fetchTrack(job.trackId!);
        if (generation != _acquisitionGeneration) return;
        _query = '';
        _items
          ..clear()
          ..add(track);
        _total = 1;
        _error = null;
      } on CatalogException catch (error) {
        _acquisitionError = error.message;
      }
    } else if (job.isFailed) {
      _acquisitionError =
          job.failureMessage ?? 'The acquisition could not be completed.';
    }
    notifyListeners();
  }

  void dismissAcquisitionResult() {
    if (_activeJob?.isActive == true) return;
    _activeJob = null;
    _acquisitionError = null;
    _candidates.clear();
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (_isInitialLoading || _isLoadingMore || !hasMore) {
      return;
    }
    final generation = _generation;
    final query = _query;
    _isLoadingMore = true;
    _error = null;
    notifyListeners();
    try {
      final page = await _api.fetchTracks(
        limit: pageSize,
        offset: _items.length,
        query: query.isEmpty ? null : query,
      );
      if (generation != _generation || query != _query) {
        return;
      }
      final knownIds = _items.map((track) => track.id).toSet();
      _items.addAll(page.items.where((track) => knownIds.add(track.id)));
      _total = page.total;
    } on CatalogException catch (error) {
      if (generation == _generation) {
        _error = error.message;
      }
    } on Object {
      if (generation == _generation) {
        _error = 'More tracks could not be loaded.';
      }
    } finally {
      if (generation == _generation) {
        _isLoadingMore = false;
        notifyListeners();
      }
    }
  }

  Iterable<Track> _unique(Iterable<Track> values) sync* {
    final ids = <String>{};
    for (final track in values) {
      if (ids.add(track.id)) {
        yield track;
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _acquisitionGeneration += 1;
    _discoveryGeneration += 1;
    _api.close();
    super.dispose();
  }
}
