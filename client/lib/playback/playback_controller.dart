import 'dart:async';

import 'package:flutter/foundation.dart';

import '../library/track.dart';
import 'audio_player_port.dart';

enum PlaybackRepeatMode { off, all, current }

final class PlaybackQueueEntry {
  const PlaybackQueueEntry({
    required this.id,
    required this.track,
    required this.audioUri,
  });

  final int id;
  final Track track;
  final Uri audioUri;
}

final class PlaybackController extends ChangeNotifier {
  PlaybackController(
    this._player, {
    this.sourceLoadTimeout = const Duration(seconds: 15),
  }) {
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
        if (_acceptPlayerEvents) _setError();
      }),
    ];
  }

  static const previousRestartThreshold = Duration(seconds: 3);

  final AudioPlayerPort _player;
  final Duration sourceLoadTimeout;
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
  bool _acceptPlayerEvents = false;
  bool _completionArmed = true;
  AudioProcessingState _processingState = AudioProcessingState.idle;
  Duration _position = Duration.zero;
  Duration? _playerDuration;
  String? _error;
  int _sourceGeneration = 0;

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
  bool get isPlaying => _isPlaying;
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

  Future<void> selectAndPlay(Track track, Uri audioUri) =>
      playNow(track, audioUri);

  Future<void> playNow(Track track, Uri audioUri) async {
    final entry = _newEntry(track, audioUri);
    _queue
      ..clear()
      ..add(entry);
    _currentIndex = 0;
    await _loadEntry(entry);
  }

  Future<void> playNext(Track track, Uri audioUri) async {
    final entry = _newEntry(track, audioUri);
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

  Future<void> addToQueue(Track track, Uri audioUri) async {
    final entry = _newEntry(track, audioUri);
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
        _setError();
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
    final generation = ++_sourceGeneration;
    _requestedTrack = entry.track;
    _requestedAudioUri = entry.audioUri;
    _track = null;
    _audioUri = null;
    _acceptPlayerEvents = false;
    _completionArmed = true;
    _isPlaying = false;
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
        _setError();
      }
    }
  }

  Future<void> togglePlayback() async {
    if (!canControlPlayback) {
      return;
    }
    try {
      if (_isPlaying) {
        await _player.pause();
      } else {
        if (isCompleted) {
          await _player.seek(Duration.zero);
          _position = Duration.zero;
          _processingState = AudioProcessingState.ready;
          _completionArmed = true;
        }
        _startPlaying(_sourceGeneration);
      }
    } on Object {
      _setError();
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
      _setError();
    }
  }

  Future<void> retry() async {
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

  void _handleCompletion(int generation) {
    if (!_completionArmed || generation != _sourceGeneration) {
      notifyListeners();
      return;
    }
    _processingState = AudioProcessingState.completed;
    _isPlaying = false;
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
      await _player.seek(Duration.zero);
      if (generation != _sourceGeneration) {
        return;
      }
      _position = Duration.zero;
      _processingState = AudioProcessingState.ready;
      notifyListeners();
      _startPlaying(generation);
    } on Object {
      if (generation == _sourceGeneration) {
        _setError();
      }
    }
  }

  PlaybackQueueEntry _newEntry(Track track, Uri audioUri) =>
      PlaybackQueueEntry(id: _nextEntryId++, track: track, audioUri: audioUri);

  void _startPlaying(int generation) {
    unawaited(
      _player.play().catchError((Object _) {
        if (generation == _sourceGeneration) {
          _setError();
        }
      }),
    );
  }

  void _setError() {
    _acceptPlayerEvents = false;
    _isPlaying = false;
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
