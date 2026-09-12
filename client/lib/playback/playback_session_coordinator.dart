import 'dart:async';

import 'audio_interruption_port.dart';
import 'audio_player_port.dart';
import 'playback_controller.dart';
import 'playback_recovery_policy.dart';
import 'system_media_port.dart';

typedef PlaybackAudioPlayerFactory = AudioPlayerPort Function();

final class PlaybackSessionCoordinator {
  PlaybackSessionCoordinator({
    required PlaybackAudioPlayerFactory createAudioPlayer,
    SystemMediaPort? systemMedia,
    AudioInterruptionPort? audioInterruptions,
    this.seekIncrement = const Duration(seconds: 10),
    this.recoveryPolicy = PlaybackRecoveryPolicy.disabled,
    PlaybackRecoveryDelay recoveryDelay = defaultPlaybackRecoveryDelay,
  }) : _audioPlayerFactory = createAudioPlayer,
       _systemMedia = systemMedia ?? const NoopSystemMediaPort(),
       _audioInterruptions =
           audioInterruptions ?? const NoopAudioInterruptionPort(),
       _recoveryDelay = recoveryDelay;

  final PlaybackAudioPlayerFactory _audioPlayerFactory;
  final SystemMediaPort _systemMedia;
  final AudioInterruptionPort _audioInterruptions;
  final Duration seekIncrement;
  final PlaybackRecoveryPolicy recoveryPolicy;
  final PlaybackRecoveryDelay _recoveryDelay;

  PlaybackController? _controller;
  StreamSubscription<SystemMediaCommand>? _commandSubscription;
  StreamSubscription<AudioInterruptionKind>? _interruptionSubscription;
  StreamSubscription<void>? _noisySubscription;
  Future<void> _publicationTail = Future.value();
  int _sessionGeneration = 0;
  int _publicationRevision = 0;
  bool _resumeAfterTransientLoss = false;
  bool _handlingInterruption = false;
  bool _initialized = false;
  bool _closed = false;

  PlaybackController? get controller => _controller;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await _audioInterruptions.configureForMusic();
    _commandSubscription = _systemMedia.commands.listen(_handleCommand);
    _interruptionSubscription = _audioInterruptions.interruptions.listen(
      _handleInterruption,
    );
    _noisySubscription = _audioInterruptions.becomingNoisy.listen(
      (_) => _handleBecomingNoisy(),
    );
  }

  Future<PlaybackController?> replaceSession({required bool configured}) async {
    if (_closed) throw StateError('The playback session is closed.');
    final generation = ++_sessionGeneration;
    _resumeAfterTransientLoss = false;
    final oldController = _controller;
    _controller = null;
    if (oldController != null) {
      oldController.removeListener(_controllerChanged);
      await oldController.stopAndReset();
      oldController.dispose();
    }
    await _scheduleClear();
    if (generation != _sessionGeneration || !configured || _closed) {
      return null;
    }
    final nextController = PlaybackController(
      _audioPlayerFactory(),
      recoveryPolicy: recoveryPolicy,
      recoveryDelay: _recoveryDelay,
    );
    _controller = nextController;
    nextController.addListener(_controllerChanged);
    _controllerChanged();
    return nextController;
  }

  void _controllerChanged() {
    final controller = _controller;
    if (controller == null) return;
    if (!_handlingInterruption && !controller.isPlaying) {
      _resumeAfterTransientLoss = false;
    }
    _schedulePublish(controller, _sessionGeneration);
  }

  void _schedulePublish(PlaybackController controller, int generation) {
    final revision = ++_publicationRevision;
    final snapshot = _snapshot(controller);
    _publicationTail = _publicationTail.then((_) async {
      if (_closed ||
          generation != _sessionGeneration ||
          revision != _publicationRevision ||
          !identical(controller, _controller)) {
        return;
      }
      try {
        await _systemMedia
            .publish(snapshot)
            .timeout(const Duration(seconds: 1));
      } on Object {
        // Android media output must never block the playback authority.
      }
    });
  }

  Future<void> _scheduleClear() {
    final revision = ++_publicationRevision;
    _publicationTail = _publicationTail.then((_) async {
      if (_closed || revision != _publicationRevision) return;
      try {
        await _systemMedia.clear().timeout(const Duration(seconds: 1));
      } on Object {
        // Clearing a system surface is best-effort after local invalidation.
      }
    });
    return _publicationTail;
  }

  SystemMediaSnapshot _snapshot(PlaybackController controller) {
    final queue = controller.queueEntries
        .map(
          (entry) => SystemMediaItem(
            id: 'arion-entry-${entry.id}',
            title: entry.track.title,
            artist: entry.track.artist,
            album: entry.track.album,
            duration: entry.track.duration,
            artworkUri: safeSystemArtworkUri(entry.artworkUri),
          ),
        )
        .toList(growable: false);
    return SystemMediaSnapshot(
      queue: queue,
      currentIndex: controller.currentIndex >= 0
          ? controller.currentIndex
          : null,
      processingState: controller.processingState,
      playing: controller.isPlaying,
      position: controller.position,
      repeatMode: switch (controller.repeatMode) {
        PlaybackRepeatMode.off => SystemMediaRepeatMode.none,
        PlaybackRepeatMode.all => SystemMediaRepeatMode.all,
        PlaybackRepeatMode.current => SystemMediaRepeatMode.one,
      },
      canGoPrevious: controller.canGoPrevious,
      canGoNext: controller.canGoNext,
      canPlay: controller.canControlPlayback && !controller.isPlaying,
      canPause: controller.canControlPlayback && controller.isPlaying,
      canSeek: controller.canControlPlayback,
    );
  }

  Future<void> _handleCommand(SystemMediaCommand command) async {
    final controller = _controller;
    if (controller == null) return;
    switch (command.type) {
      case SystemMediaCommandType.play:
        _resumeAfterTransientLoss = false;
        await controller.play();
        return;
      case SystemMediaCommandType.pause:
        _resumeAfterTransientLoss = false;
        await controller.pause();
        return;
      case SystemMediaCommandType.seek:
        if (command.position case final position?) {
          await controller.seek(position);
        }
        return;
      case SystemMediaCommandType.seekForward:
        await controller.seek(controller.position + seekIncrement);
        return;
      case SystemMediaCommandType.seekBackward:
        await controller.seek(controller.position - seekIncrement);
        return;
      case SystemMediaCommandType.previous:
        await controller.skipToPrevious();
        return;
      case SystemMediaCommandType.next:
        await controller.skipToNext();
        return;
      case SystemMediaCommandType.setRepeat:
        if (command.repeatMode case final repeatMode?) {
          controller.setRepeatMode(switch (repeatMode) {
            SystemMediaRepeatMode.none => PlaybackRepeatMode.off,
            SystemMediaRepeatMode.all => PlaybackRepeatMode.all,
            SystemMediaRepeatMode.one => PlaybackRepeatMode.current,
          });
        }
        return;
    }
  }

  Future<void> _handleInterruption(AudioInterruptionKind event) async {
    final controller = _controller;
    if (controller == null) return;
    _handlingInterruption = true;
    try {
      switch (event) {
        case AudioInterruptionKind.transientLoss:
          _resumeAfterTransientLoss = controller.isPlaying;
          if (controller.isPlaying) await controller.pause();
          return;
        case AudioInterruptionKind.transientGain:
          final shouldResume = _resumeAfterTransientLoss;
          _resumeAfterTransientLoss = false;
          if (shouldResume && !controller.isPlaying) await controller.play();
          return;
        case AudioInterruptionKind.permanentLoss:
          _resumeAfterTransientLoss = false;
          if (controller.isPlaying) await controller.pause();
          return;
      }
    } finally {
      _handlingInterruption = false;
    }
  }

  Future<void> _handleBecomingNoisy() async {
    _resumeAfterTransientLoss = false;
    final controller = _controller;
    if (controller != null && controller.isPlaying) {
      _handlingInterruption = true;
      try {
        await controller.pause();
      } finally {
        _handlingInterruption = false;
      }
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _sessionGeneration += 1;
    _publicationRevision += 1;
    _resumeAfterTransientLoss = false;
    await _commandSubscription?.cancel();
    await _interruptionSubscription?.cancel();
    await _noisySubscription?.cancel();
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      controller.removeListener(_controllerChanged);
      await controller.stopAndReset();
      controller.dispose();
    }
    await _systemMedia.clear();
    await _systemMedia.dispose();
    await _audioInterruptions.dispose();
  }
}

Uri? safeSystemArtworkUri(Uri? uri) {
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    pathSegments: uri.pathSegments,
  );
}
