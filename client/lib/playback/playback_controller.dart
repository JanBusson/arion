import 'dart:async';

import 'package:flutter/foundation.dart';

import '../library/track.dart';
import 'audio_player_port.dart';

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
        _processingState = value;
        if (value == AudioProcessingState.completed) {
          _isPlaying = false;
        }
        notifyListeners();
      }),
      _player.positionStream.listen((value) {
        if (!_acceptPlayerEvents) return;
        _position = _clamp(value, Duration.zero, effectiveDuration);
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

  final AudioPlayerPort _player;
  final Duration sourceLoadTimeout;
  late final List<StreamSubscription<Object?>> _subscriptions;

  Track? _track;
  Uri? _audioUri;
  Track? _requestedTrack;
  Uri? _requestedAudioUri;
  bool _isPlaying = false;
  bool _acceptPlayerEvents = false;
  AudioProcessingState _processingState = AudioProcessingState.idle;
  Duration _position = Duration.zero;
  Duration? _playerDuration;
  String? _error;
  int _sourceGeneration = 0;

  Track? get track => _track;
  Track? get requestedTrack => _requestedTrack;
  Track? get visibleTrack => _track ?? _requestedTrack;
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

  Future<void> selectAndPlay(Track track, Uri audioUri) async {
    final generation = ++_sourceGeneration;
    _requestedTrack = track;
    _requestedAudioUri = audioUri;
    _track = null;
    _audioUri = null;
    _acceptPlayerEvents = false;
    _isPlaying = false;
    _position = Duration.zero;
    _playerDuration = null;
    _error = null;
    _processingState = AudioProcessingState.loading;
    notifyListeners();

    try {
      final duration = await _player
          .setUrl(audioUri)
          .timeout(sourceLoadTimeout);
      if (generation != _sourceGeneration) {
        return;
      }

      _track = track;
      _audioUri = audioUri;
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
      if (generation == _sourceGeneration) {
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
      notifyListeners();
    } on Object {
      _setError();
    }
  }

  Future<void> retry() async {
    final selected = _requestedTrack ?? _track;
    final uri = _requestedAudioUri ?? _audioUri;
    if (selected != null && uri != null) {
      await selectAndPlay(selected, uri);
    }
  }

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
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_player.dispose());
    super.dispose();
  }
}
