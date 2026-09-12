import 'dart:async';

import 'package:flutter/foundation.dart';

import '../library/track.dart';
import 'audio_player_port.dart';
import 'playback_recovery_policy.dart';

enum PlaybackRepeatMode { off, all, current }

final class PlaybackQueueEntry {
  const PlaybackQueueEntry({
    required this.id,
    required this.track,
    required this.audioUri,
    this.artworkUri,
  });

  final int id;
  final Track track;
  final Uri audioUri;
  final Uri? artworkUri;
}

final class PlaybackController extends ChangeNotifier {
  PlaybackController(
    this._player, {
    this.sourceLoadTimeout = const Duration(seconds: 15),
    this.recoveryPolicy = PlaybackRecoveryPolicy.disabled,
    PlaybackRecoveryDelay recoveryDelay = defaultPlaybackRecoveryDelay,
  }) : _recoveryDelay = recoveryDelay {
    _subscriptions = [
      _player.playingStream.listen((value) {
        if (!_acceptPlayerEvents) return;
        _isPlaying = value;
        notifyListeners();
      }),
      _player.processingStateStream.listen((value) {
        if (!_acceptPlayerEvents) return;
        if (value == AudioProcessingState.completed) {
          _handleCompletion(_sourceGeneration);
        } else {
          _processingState = value;
          notifyListeners();
        }
      }),
      _player.positionStream.listen((value) {
        if (!_acceptPlayerEvents) return;
        _position = _clamp(value, Duration.zero, effectiveDuration);
        if (_processingState != AudioProcessingState.completed &&
            _position > Duration.zero) {
          _completionArmed = true;
        }
        notifyListeners();
      }),
      _player.durationStream.listen((value) {
        if (!_acceptPlayerEvents) return;
        if (value != null && value > Duration.zero) {
          _playerDuration = value;
          _position = _clamp(_position, Duration.zero, effectiveDuration);
          notifyListeners();
        }
      }),
      _player.errorStream.listen((_) {
        if (_acceptPlayerEvents) _handlePlayerError();
      }),
    ];
  }

  static const previousRestartThreshold = Duration(seconds: 3);

  final AudioPlayerPort _player;
  final Duration sourceLoadTimeout;
  final PlaybackRecoveryPolicy recoveryPolicy;
  final PlaybackRecoveryDelay _recoveryDelay;
  late final List<StreamSubscription<Object?>> _subscriptions;

  final List<PlaybackQueueEntry> _queue = [];
  int _currentIndex = -1;
  int _nextEntryId = 1;
  PlaybackRepeatMode _repeatMode = PlaybackRepeatMode.off;

  Track? _track;
  Uri? _audioUri;
  Track? _requestedTrack;
  Uri? _requestedAudioUri;
  bool _isPlaying = false;
  bool _playbackRequested = false;
  bool _isReconnecting = false;
  bool _sourceNeedsReload = false;
  bool _acceptPlayerEvents = false;
  bool _completionArmed = true;
  AudioProcessingState _processingState = AudioProcessingState.idle;
  Duration _position = Duration.zero;
  Duration? _playerDuration;
  String? _error;
  int _sourceGeneration = 0;
  int _recoveryGeneration = 0;

  List<PlaybackQueueEntry> get queueEntries =>
      List<PlaybackQueueEntry>.unmodifiable(_queue);
  List<PlaybackQueueEntry> get upcomingEntries => _currentIndex < 0
      ? const []
      : List<PlaybackQueueEntry>.unmodifiable(_queue.skip(_currentIndex + 1));
  PlaybackQueueEntry? get currentEntry =>
      _currentIndex >= 0 && _currentIndex < _queue.length
      ? _queue[_currentIndex]
      : null;
  int get currentIndex => _currentIndex;
  PlaybackRepeatMode get repeatMode => _repeatMode;
  bool get hasQueue => currentEntry != null;

  Track? get track => _track;
  Track? get requestedTrack => _requestedTrack;
  Track? get visibleTrack => currentEntry?.track ?? _track ?? _requestedTrack;
  bool get isPlaying => _isReconnecting ? _playbackRequested : _isPlaying;
  bool get isPlaybackRequested => _playbackRequested;
  bool get isReconnecting => _isReconnecting;
  AudioProcessingState get processingState => _processingState;
  Duration get position => _position;
  String? get error => _error;
  bool get hasSelection => visibleTrack != null;
  bool get isLoadingSelection =>
      _requestedTrack != null && _error == null && _track == null;
  bool get canControlPlayback =>
      _track != null && !isLoadingSelection && _error == null;
  bool get isBuffering =>
      isLoadingSelection ||
      _isReconnecting ||
      _processingState == AudioProcessingState.loading ||
      _processingState == AudioProcessingState.buffering;
  bool get isCompleted => _processingState == AudioProcessingState.completed;
  Duration get effectiveDuration =>
      _playerDuration ?? _track?.duration ?? Duration.zero;
  bool get canGoNext =>
      _currentIndex >= 0 &&
      (_currentIndex < _queue.length - 1 ||
          (_repeatMode == PlaybackRepeatMode.all && _queue.length > 1));
  bool get canGoPrevious =>
      currentEntry != null &&
      (_position > previousRestartThreshold ||
          _currentIndex > 0 ||
          (_repeatMode == PlaybackRepeatMode.all && _queue.length > 1));

  Future<void> selectAndPlay(Track track, Uri audioUri, {Uri? artworkUri}) =>
      playNow(track, audioUri, artworkUri: artworkUri);

  Future<void> playNow(Track track, Uri audioUri, {Uri? artworkUri}) async {
    final entry = _newEntry(track, audioUri, artworkUri);
    _queue
      ..clear()
      ..add(entry);
    _currentIndex = 0;
    await _loadEntry(entry);
  }

  Future<void> playNext(Track track, Uri audioUri, {Uri? artworkUri}) async {
    final entry = _newEntry(track, audioUri, artworkUri);
    if (currentEntry == null) {
      _queue
        ..clear()
        ..add(entry);
      _currentIndex = 0;
      await _loadEntry(entry);
      return;
    }
    _queue.insert(_currentIndex + 1, entry);
    notifyListeners();
  }

  Future<void> addToQueue(Track track, Uri audioUri, {Uri? artworkUri}) async {
    final entry = _newEntry(track, audioUri, artworkUri);
    if (currentEntry == null) {
      _queue
        ..clear()
        ..add(entry);
      _currentIndex = 0;
      await _loadEntry(entry);
      return;
    }
    _queue.add(entry);
    notifyListeners();
  }

  bool removeUpcoming(int entryId) {
    final index = _queue.indexWhere((entry) => entry.id == entryId);
    if (index <= _currentIndex) {
      return false;
    }
    _queue.removeAt(index);
    notifyListeners();
    return true;
  }

  bool moveUpcoming(int entryId, int newUpcomingIndex) {
    final oldIndex = _queue.indexWhere((entry) => entry.id == entryId);
    final upcomingCount = _queue.length - _currentIndex - 1;
    if (oldIndex <= _currentIndex ||
        newUpcomingIndex < 0 ||
        newUpcomingIndex >= upcomingCount) {
      return false;
    }
    final entry = _queue.removeAt(oldIndex);
    _queue.insert(_currentIndex + 1 + newUpcomingIndex, entry);
    notifyListeners();
    return true;
  }

  void setRepeatMode(PlaybackRepeatMode mode) {
    if (_repeatMode == mode) {
      return;
    }
    _repeatMode = mode;
    notifyListeners();
  }

  void cycleRepeatMode() {
    setRepeatMode(switch (_repeatMode) {
      PlaybackRepeatMode.off => PlaybackRepeatMode.all,
      PlaybackRepeatMode.all => PlaybackRepeatMode.current,
      PlaybackRepeatMode.current => PlaybackRepeatMode.off,
    });
  }

  Future<void> skipToNext() async {
    if (!canGoNext) {
      return;
    }
    final target = _currentIndex < _queue.length - 1 ? _currentIndex + 1 : 0;
    await _activateIndex(target);
  }

  Future<void> skipToPrevious() async {
    if (!canGoPrevious) {
      return;
    }
    if (_position > previousRestartThreshold && canControlPlayback) {
      try {
        await _player.seek(Duration.zero);
        _position = Duration.zero;
        _completionArmed = true;
        notifyListeners();
      } on Object {
        _handlePlayerError();
      }
      return;
    }
    final target = _currentIndex > 0 ? _currentIndex - 1 : _queue.length - 1;
    await _activateIndex(target);
  }

  Future<void> _activateIndex(int index) async {
    if (index < 0 || index >= _queue.length) {
      return;
    }
    _currentIndex = index;
    await _loadEntry(_queue[index]);
  }

  Future<void> _loadEntry(PlaybackQueueEntry entry) async {
    _invalidateRecovery(clearReloadRequirement: true);
    final generation = ++_sourceGeneration;
    _requestedTrack = entry.track;
    _requestedAudioUri = entry.audioUri;
    _track = null;
    _audioUri = null;
    _acceptPlayerEvents = false;
    _completionArmed = true;
    _isPlaying = false;
    _playbackRequested = true;
    _position = Duration.zero;
    _playerDuration = null;
    _error = null;
    _processingState = AudioProcessingState.loading;
    notifyListeners();

    try {
      final duration = await _player
          .setUrl(entry.audioUri)
          .timeout(sourceLoadTimeout);
      if (generation != _sourceGeneration || currentEntry?.id != entry.id) {
        return;
      }

      _track = entry.track;
      _audioUri = entry.audioUri;
      _requestedTrack = null;
      _requestedAudioUri = null;
      _acceptPlayerEvents = true;
      _processingState = AudioProcessingState.ready;
      if (duration != null && duration > Duration.zero) {
        _playerDuration = duration;
      }
      notifyListeners();
      _startPlaying(generation);
    } on Object {
      if (generation == _sourceGeneration && currentEntry?.id == entry.id) {
        _setError(sourceNeedsReload: true);
      }
    }
  }

  Future<void> togglePlayback() async {
    if (!canControlPlayback) {
      return;
    }
    await (isPlaying ? pause() : play());
  }

  Future<void> play() async {
    if (!canControlPlayback || isPlaying) {
      return;
    }
    _playbackRequested = true;
    if (_sourceNeedsReload) {
      _beginRecovery();
      return;
    }
    try {
      if (isCompleted) {
        await _player.pause();
        await _player.seek(Duration.zero);
        _position = Duration.zero;
        _processingState = AudioProcessingState.ready;
        _completionArmed = true;
      }
      _startPlaying(_sourceGeneration);
    } on Object {
      _handlePlayerError();
    }
  }

  Future<void> pause() async {
    if (!canControlPlayback ||
        (!_isPlaying && !_isReconnecting && !_playbackRequested)) {
      return;
    }
    final wasRecovering = _isReconnecting || _sourceNeedsReload;
    _playbackRequested = false;
    _invalidateRecovery(clearReloadRequirement: false);
    _isPlaying = false;
    if (wasRecovering) {
      _processingState = AudioProcessingState.ready;
    }
    notifyListeners();
    try {
      await _player.pause();
    } on Object {
      if (!wasRecovering) {
        _setError(sourceNeedsReload: true);
      }
    }
  }

  Future<void> seek(Duration requested) async {
    if (!canControlPlayback) {
      return;
    }
    final target = _clamp(requested, Duration.zero, effectiveDuration);
    try {
      await _player.seek(target);
      _position = target;
      if (target > Duration.zero) {
        _completionArmed = true;
      }
      notifyListeners();
    } on Object {
      _handlePlayerError();
    }
  }

  Future<void> retry() async {
    _invalidateRecovery(clearReloadRequirement: true);
    final entry = currentEntry;
    if (entry != null) {
      await _loadEntry(entry);
      return;
    }
    final selected = _requestedTrack ?? _track;
    final uri = _requestedAudioUri ?? _audioUri;
    if (selected != null && uri != null) {
      await playNow(selected, uri);
    }
  }

  Future<void> stopAndReset() async {
    _sourceGeneration += 1;
    _invalidateRecovery(clearReloadRequirement: true);
    _acceptPlayerEvents = false;
    _completionArmed = true;
    _queue.clear();
    _currentIndex = -1;
    _repeatMode = PlaybackRepeatMode.off;
    _track = null;
    _audioUri = null;
    _requestedTrack = null;
    _requestedAudioUri = null;
    _isPlaying = false;
    _playbackRequested = false;
    _processingState = AudioProcessingState.idle;
    _position = Duration.zero;
    _playerDuration = null;
    _error = null;
    notifyListeners();
    try {
      await _player.stop();
    } on Object {
      // The local session is already invalidated; stopping is best-effort.
    }
  }

  void _handleCompletion(int generation) {
    if (!_completionArmed || generation != _sourceGeneration) {
      notifyListeners();
      return;
    }
    _processingState = AudioProcessingState.completed;
    _isPlaying = false;
    _playbackRequested = false;
    _completionArmed = false;
    notifyListeners();
    switch (_repeatMode) {
      case PlaybackRepeatMode.off:
        if (_currentIndex < _queue.length - 1) {
          unawaited(_activateIndex(_currentIndex + 1));
        }
        return;
      case PlaybackRepeatMode.all:
        if (_queue.isNotEmpty) {
          final target = _currentIndex < _queue.length - 1
              ? _currentIndex + 1
              : 0;
          unawaited(_activateIndex(target));
        }
        return;
      case PlaybackRepeatMode.current:
        unawaited(_restartCurrentAfterCompletion(generation));
        return;
    }
  }

  Future<void> _restartCurrentAfterCompletion(int generation) async {
    if (!canControlPlayback || generation != _sourceGeneration) {
      return;
    }
    try {
      await _player.pause();
      if (generation != _sourceGeneration) {
        return;
      }
      await _player.seek(Duration.zero);
      if (generation != _sourceGeneration) {
        return;
      }
      _position = Duration.zero;
      _processingState = AudioProcessingState.ready;
      _completionArmed = true;
      _playbackRequested = true;
      notifyListeners();
      _startPlaying(generation);
    } on Object {
      if (generation == _sourceGeneration) {
        _handlePlayerError();
      }
    }
  }

  PlaybackQueueEntry _newEntry(Track track, Uri audioUri, Uri? artworkUri) =>
      PlaybackQueueEntry(
        id: _nextEntryId++,
        track: track,
        audioUri: audioUri,
        artworkUri: artworkUri,
      );

  void _startPlaying(int generation) {
    _playbackRequested = true;
    unawaited(
      _player.play().catchError((Object _) {
        if (generation == _sourceGeneration) {
          _handlePlayerError();
        }
      }),
    );
  }

  void _handlePlayerError() {
    if (_canAutomaticallyRecover) {
      _beginRecovery();
      return;
    }
    _setError(sourceNeedsReload: true);
  }

  bool get _canAutomaticallyRecover =>
      recoveryPolicy.enabled &&
      !_isReconnecting &&
      _playbackRequested &&
      _track != null &&
      _audioUri != null &&
      currentEntry != null &&
      !isCompleted;

  void _beginRecovery() {
    final canReloadAfterPause =
        _sourceNeedsReload &&
        _playbackRequested &&
        recoveryPolicy.enabled &&
        !_isReconnecting;
    if (!_canAutomaticallyRecover && !canReloadAfterPause) {
      return;
    }
    final entry = currentEntry;
    if (entry == null || _track == null || _audioUri == null) {
      _setError(sourceNeedsReload: true);
      return;
    }
    final sourceGeneration = _sourceGeneration;
    final recoveryGeneration = ++_recoveryGeneration;
    final resumePosition = _position;
    _acceptPlayerEvents = false;
    _isPlaying = false;
    _isReconnecting = true;
    _sourceNeedsReload = true;
    _error = null;
    _processingState = AudioProcessingState.buffering;
    notifyListeners();
    unawaited(
      _recoverCurrentEntry(
        entry,
        sourceGeneration,
        recoveryGeneration,
        resumePosition,
      ),
    );
  }

  Future<void> _recoverCurrentEntry(
    PlaybackQueueEntry entry,
    int sourceGeneration,
    int recoveryGeneration,
    Duration resumePosition,
  ) async {
    final delays = recoveryPolicy.retryDelays;
    for (var attempt = 0; attempt < delays.length; attempt += 1) {
      try {
        await _recoveryDelay(delays[attempt]);
        if (!_isCurrentRecovery(entry, sourceGeneration, recoveryGeneration)) {
          return;
        }
        final duration = await _player
            .setUrl(entry.audioUri)
            .timeout(recoveryPolicy.attemptTimeout);
        if (!_isCurrentRecovery(entry, sourceGeneration, recoveryGeneration)) {
          return;
        }
        final effective = duration ?? _playerDuration ?? entry.track.duration;
        final restoredPosition = _clamp(
          resumePosition,
          Duration.zero,
          effective,
        );
        await _player.seek(restoredPosition);
        if (!_isCurrentRecovery(entry, sourceGeneration, recoveryGeneration)) {
          return;
        }

        if (duration != null && duration > Duration.zero) {
          _playerDuration = duration;
        }
        _position = restoredPosition;
        _acceptPlayerEvents = true;
        _isReconnecting = false;
        _sourceNeedsReload = false;
        _processingState = AudioProcessingState.ready;
        _error = null;
        notifyListeners();
        if (_playbackRequested) {
          _startPlaying(sourceGeneration);
        }
        return;
      } on Object {
        if (!_isCurrentRecovery(entry, sourceGeneration, recoveryGeneration)) {
          return;
        }
        if (attempt == delays.length - 1) {
          _setError(sourceNeedsReload: true);
          return;
        }
      }
    }
  }

  bool _isCurrentRecovery(
    PlaybackQueueEntry entry,
    int sourceGeneration,
    int recoveryGeneration,
  ) =>
      sourceGeneration == _sourceGeneration &&
      recoveryGeneration == _recoveryGeneration &&
      currentEntry?.id == entry.id &&
      _isReconnecting &&
      _playbackRequested;

  void _invalidateRecovery({required bool clearReloadRequirement}) {
    _recoveryGeneration += 1;
    _isReconnecting = false;
    if (clearReloadRequirement) {
      _sourceNeedsReload = false;
    }
  }

  void _setError({required bool sourceNeedsReload}) {
    _recoveryGeneration += 1;
    _acceptPlayerEvents = false;
    _isPlaying = false;
    _playbackRequested = false;
    _isReconnecting = false;
    _sourceNeedsReload = sourceNeedsReload;
    _processingState = AudioProcessingState.idle;
    _error = 'This track could not be played.';
    notifyListeners();
  }

  static Duration _clamp(Duration value, Duration minimum, Duration maximum) {
    if (value < minimum) {
      return minimum;
    }
    if (maximum > Duration.zero && value > maximum) {
      return maximum;
    }
    return value;
  }

  @override
  void dispose() {
    _sourceGeneration += 1;
    _invalidateRecovery(clearReloadRequirement: true);
    _acceptPlayerEvents = false;
    _queue.clear();
    _currentIndex = -1;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_player.dispose());
    super.dispose();
  }
}
