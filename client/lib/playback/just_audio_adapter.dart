import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_player_port.dart';
import 'offline_audio_resolver.dart';
import 'playback_audio_cache.dart';

typedef AudioPlayerEngineFactory = AudioPlayerEngine Function();

const arionAndroidLoadControl = AndroidLoadControl(
  minBufferDuration: Duration(seconds: 90),
  maxBufferDuration: Duration(seconds: 180),
  bufferForPlaybackDuration: Duration(milliseconds: 2500),
  bufferForPlaybackAfterRebufferDuration: Duration(seconds: 5),
  prioritizeTimeOverSizeThresholds: true,
);

abstract interface class AudioPlayerEngine {
  Stream<bool> get playingStream;
  Stream<AudioProcessingState> get processingStateStream;
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<Object> get errorStream;

  Future<Duration?> setUrl(Uri uri);
  Future<Duration?> setAudioSource(AudioSource source);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> dispose();
}

final class JustAudioAdapter implements AudioPlayerPort {
  JustAudioAdapter({
    AudioPlayerEngine? engine,
    AudioPlayerEngineFactory? engineFactory,
    this.offlineAudioResolver,
    this.playbackCache,
    bool? recreateOnSourceChange,
  }) : _engineFactory = engineFactory ?? _JustAudioEngine.new,
       _recreateOnSourceChange = recreateOnSourceChange ?? kIsWeb,
       _engine = engine ?? (engineFactory ?? _JustAudioEngine.new)() {
    _bindEngine(_engine, _sourceGeneration);
  }

  final AudioPlayerEngineFactory _engineFactory;
  final OfflineAudioResolver? offlineAudioResolver;
  final PlaybackAudioCache? playbackCache;
  final bool _recreateOnSourceChange;
  AudioPlayerEngine _engine;

  final StreamController<bool> _playing = StreamController.broadcast();
  final StreamController<AudioProcessingState> _processing =
      StreamController.broadcast();
  final StreamController<Duration> _positions = StreamController.broadcast();
  final StreamController<Duration?> _durations = StreamController.broadcast();
  final StreamController<Object> _errors = StreamController.broadcast();

  List<StreamSubscription<Object?>> _engineSubscriptions = [];
  final Set<Future<void>> _retiringEngines = {};
  StreamSubscription<void>? _cacheCompletionSubscription;
  PlaybackCacheSource? _activeCacheSource;
  Uri? _activeOfflineUri;
  Uri? _activeUri;
  Uri? _pendingOfflineInvalidationUri;
  Uri? _pendingOfflineBypassUri;
  String? _pendingInvalidationKey;
  Uri? _pendingBypassUri;
  int? _localFailureGeneration;
  int _sourceGeneration = 0;
  bool _hasAttemptedSource = false;
  bool _disposed = false;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Stream<AudioProcessingState> get processingStateStream => _processing.stream;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Stream<Duration?> get durationStream => _durations.stream;

  @override
  Stream<Object> get errorStream => _errors.stream;

  @override
  Future<Duration?> setUrl(Uri uri) async {
    if (_disposed) {
      throw StateError('The audio player has been disposed.');
    }

    final generation = ++_sourceGeneration;
    await _cacheCompletionSubscription?.cancel();
    _cacheCompletionSubscription = null;
    _activeCacheSource = null;
    _activeOfflineUri = null;
    _activeUri = null;
    _localFailureGeneration = null;
    final replaceEngine = _recreateOnSourceChange && _hasAttemptedSource;
    _hasAttemptedSource = true;

    if (replaceEngine) {
      final oldEngine = _engine;
      final nextEngine = _engineFactory();
      _engine = nextEngine;
      _bindEngine(nextEngine, generation);
      await _stopEngine(oldEngine);
      _retireEngine(oldEngine);
    } else {
      _bindEngine(_engine, generation);
      if (generation > 1) {
        await _engine.stop();
      }
    }

    await _flushPendingOfflineInvalidation();
    await _flushPendingCacheInvalidation();

    if (generation != _sourceGeneration) {
      throw const AudioSourceSupersededException();
    }

    final selectedEngine = _engine;
    Duration? duration;
    try {
      duration = await _loadSource(selectedEngine, uri, generation);
    } on Object {
      if (generation != _sourceGeneration ||
          !identical(selectedEngine, _engine)) {
        throw const AudioSourceSupersededException();
      }
      rethrow;
    }
    if (generation != _sourceGeneration ||
        !identical(selectedEngine, _engine)) {
      throw const AudioSourceSupersededException();
    }
    return duration;
  }

  Future<Duration?> _loadSource(
    AudioPlayerEngine engine,
    Uri uri,
    int generation,
  ) async {
    final cache = playbackCache;
    final bypassCompleteCache = _pendingBypassUri == uri;
    _pendingBypassUri = null;
    _localFailureGeneration = null;
    _activeUri = uri;
    _activeCacheSource = null;
    _activeOfflineUri = null;
    final bypassOffline = _pendingOfflineBypassUri == uri;
    _pendingOfflineBypassUri = null;
    final offline = offlineAudioResolver;
    if (offline != null && !bypassOffline) {
      final local = await offline.resolve(uri);
      if (generation != _sourceGeneration || !identical(engine, _engine)) {
        throw const AudioSourceSupersededException();
      }
      if (local != null) {
        _activeOfflineUri = uri;
        try {
          return await engine.setAudioSource(AudioSource.file(local.path));
        } on Object {
          _activeOfflineUri = null;
          await offline.invalidate(uri);
          if (generation != _sourceGeneration || !identical(engine, _engine)) {
            throw const AudioSourceSupersededException();
          }
        }
      }
    }
    if (cache == null) return engine.setUrl(uri);

    var prepared = await cache.prepare(
      uri,
      bypassCompleteCache: bypassCompleteCache,
    );
    if (generation != _sourceGeneration || !identical(engine, _engine)) {
      throw const AudioSourceSupersededException();
    }
    if (prepared == null) return engine.setUrl(uri);

    _activeCacheSource = prepared;
    try {
      final duration = await engine.setAudioSource(prepared.source);
      _ensureCurrent(engine, generation);
      _listenForCacheCompletion(prepared, engine, generation);
      unawaited(cache.maintain());
      return duration;
    } on Object {
      if (!prepared.fromCompleteCache) rethrow;
      if (_pendingInvalidationKey == prepared.key) {
        _pendingInvalidationKey = null;
        _pendingBypassUri = null;
      }
      await cache.invalidate(prepared.key);
      if (generation != _sourceGeneration || !identical(engine, _engine)) {
        throw const AudioSourceSupersededException();
      }
      prepared = await cache.prepare(uri, bypassCompleteCache: true);
      if (generation != _sourceGeneration || !identical(engine, _engine)) {
        throw const AudioSourceSupersededException();
      }
      if (prepared == null) {
        _activeCacheSource = null;
        return engine.setUrl(uri);
      }
      _activeCacheSource = prepared;
      final duration = await engine.setAudioSource(prepared.source);
      _ensureCurrent(engine, generation);
      _listenForCacheCompletion(prepared, engine, generation);
      unawaited(cache.maintain());
      return duration;
    }
  }

  void _ensureCurrent(AudioPlayerEngine engine, int generation) {
    if (generation != _sourceGeneration || !identical(engine, _engine)) {
      throw const AudioSourceSupersededException();
    }
  }

  void _listenForCacheCompletion(
    PlaybackCacheSource source,
    AudioPlayerEngine engine,
    int generation,
  ) {
    _cacheCompletionSubscription = source.completion.listen((_) {
      if (!_disposed &&
          generation == _sourceGeneration &&
          identical(engine, _engine) &&
          identical(source, _activeCacheSource)) {
        unawaited(playbackCache?.complete(source.key));
      }
    });
  }

  Future<void> _flushPendingCacheInvalidation() async {
    final key = _pendingInvalidationKey;
    _pendingInvalidationKey = null;
    if (key != null) await playbackCache?.invalidate(key);
  }

  Future<void> _flushPendingOfflineInvalidation() async {
    final uri = _pendingOfflineInvalidationUri;
    _pendingOfflineInvalidationUri = null;
    if (uri != null) await offlineAudioResolver?.invalidate(uri);
  }

  @override
  Future<void> play() => _engine.play();

  @override
  Future<void> pause() => _engine.pause();

  @override
  Future<void> stop() => _engine.stop();

  @override
  Future<void> seek(Duration position) => _engine.seek(position);

  void _bindEngine(AudioPlayerEngine engine, int generation) {
    for (final subscription in _engineSubscriptions) {
      unawaited(subscription.cancel());
    }
    _engineSubscriptions = [
      engine.playingStream.listen(
        (value) => _forward(engine, generation, _playing, value),
      ),
      engine.processingStateStream.listen(
        (value) => _forward(engine, generation, _processing, value),
      ),
      engine.positionStream.listen(
        (value) => _forward(engine, generation, _positions, value),
      ),
      engine.durationStream.listen(
        (value) => _forward(engine, generation, _durations, value),
      ),
      engine.errorStream.listen(
        (value) => _forwardError(engine, generation, value),
      ),
    ];
  }

  void _forwardError(AudioPlayerEngine engine, int generation, Object value) {
    if (_disposed ||
        generation != _sourceGeneration ||
        !identical(engine, _engine)) {
      return;
    }
    final active = _activeCacheSource;
    if (_activeOfflineUri != null && _localFailureGeneration != generation) {
      _localFailureGeneration = generation;
      _pendingOfflineInvalidationUri = _activeOfflineUri;
      _pendingOfflineBypassUri = _activeOfflineUri;
    } else if (active?.fromCompleteCache == true &&
        _localFailureGeneration != generation) {
      _localFailureGeneration = generation;
      _pendingInvalidationKey = active!.key;
      _pendingBypassUri = _activeUri;
    }
    _errors.add(value);
  }

  void _forward<T>(
    AudioPlayerEngine engine,
    int generation,
    StreamController<T> controller,
    T value,
  ) {
    if (!_disposed &&
        generation == _sourceGeneration &&
        identical(engine, _engine)) {
      controller.add(value);
    }
  }

  static Future<void> _stopEngine(AudioPlayerEngine engine) async {
    try {
      await engine.stop().timeout(const Duration(seconds: 1));
    } on Object {
      // A fresh authoritative engine must not be blocked by a stuck old source.
    }
  }

  void _retireEngine(AudioPlayerEngine engine) {
    late final Future<void> retirement;
    retirement = engine
        .dispose()
        .timeout(const Duration(seconds: 2))
        .catchError((Object _) {})
        .whenComplete(() => _retiringEngines.remove(retirement));
    _retiringEngines.add(retirement);
    unawaited(retirement);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _sourceGeneration += 1;
    await _cacheCompletionSubscription?.cancel();
    _cacheCompletionSubscription = null;
    for (final subscription in _engineSubscriptions) {
      await subscription.cancel();
    }
    _engineSubscriptions = [];
    await _stopEngine(_engine);
    await _flushPendingOfflineInvalidation();
    await _flushPendingCacheInvalidation();
    await playbackCache?.release();
    try {
      await _engine.dispose().timeout(const Duration(seconds: 2));
    } on Object {
      // Disposal is best-effort after the player has been invalidated.
    }
    await Future.wait(_retiringEngines.toList());
    await playbackCache?.dispose();
    await offlineAudioResolver?.dispose();
    await Future.wait([
      _playing.close(),
      _processing.close(),
      _positions.close(),
      _durations.close(),
      _errors.close(),
    ]);
  }
}

final class AudioSourceSupersededException implements Exception {
  const AudioSourceSupersededException();

  @override
  String toString() => 'The audio source load was superseded.';
}

final class _JustAudioEngine implements AudioPlayerEngine {
  _JustAudioEngine()
    : _player = AudioPlayer(
        handleInterruptions: false,
        audioLoadConfiguration: const AudioLoadConfiguration(
          androidLoadControl: arionAndroidLoadControl,
        ),
      ) {
    _eventSubscription = _player.playbackEventStream.listen(
      (_) {},
      onError: (Object error, StackTrace _) => _errors.add(error),
    );
  }

  final AudioPlayer _player;
  final StreamController<Object> _errors = StreamController.broadcast();
  late final StreamSubscription<PlaybackEvent> _eventSubscription;

  @override
  Stream<bool> get playingStream => _player.playingStream;

  @override
  Stream<AudioProcessingState> get processingStateStream =>
      _player.processingStateStream.map(_mapState);

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Stream<Object> get errorStream => _errors.stream;

  @override
  Future<Duration?> setUrl(Uri uri) => _player.setUrl(uri.toString());

  @override
  Future<Duration?> setAudioSource(AudioSource source) =>
      _player.setAudioSource(source);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> dispose() async {
    await _eventSubscription.cancel();
    await _player.dispose();
    await _errors.close();
  }

  static AudioProcessingState _mapState(ProcessingState state) =>
      switch (state) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      };
}
