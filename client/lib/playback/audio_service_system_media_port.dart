import 'dart:async';

import 'package:audio_service/audio_service.dart' as audio_service;

import 'audio_player_port.dart';
import 'system_media_port.dart';

final class AudioServiceSystemMediaPort extends audio_service.BaseAudioHandler
    implements SystemMediaPort {
  final StreamController<SystemMediaCommand> _commands =
      StreamController.broadcast();

  @override
  Stream<SystemMediaCommand> get commands => _commands.stream;

  @override
  Future<void> publish(SystemMediaSnapshot snapshot) async {
    final mediaItems = snapshot.queue
        .map(
          (item) => audio_service.MediaItem(
            id: item.id,
            title: item.title,
            artist: item.artist,
            album: item.album,
            duration: item.duration,
            artUri: item.artworkUri,
          ),
        )
        .toList(growable: false);
    queue.add(mediaItems);
    mediaItem.add(
      snapshot.currentIndex == null ? null : mediaItems[snapshot.currentIndex!],
    );

    final controls = <audio_service.MediaControl>[
      if (snapshot.canGoPrevious) audio_service.MediaControl.skipToPrevious,
      if (snapshot.canPause)
        audio_service.MediaControl.pause
      else if (snapshot.canPlay)
        audio_service.MediaControl.play,
      if (snapshot.canGoNext) audio_service.MediaControl.skipToNext,
    ];
    playbackState.add(
      audio_service.PlaybackState(
        processingState: _processingState(snapshot.processingState),
        playing: snapshot.playing,
        controls: controls,
        androidCompactActionIndices: List<int>.generate(
          controls.length,
          (index) => index,
        ),
        systemActions: {
          if (snapshot.canSeek) ...{
            audio_service.MediaAction.seek,
            audio_service.MediaAction.seekForward,
            audio_service.MediaAction.seekBackward,
          },
          if (snapshot.currentItem != null)
            audio_service.MediaAction.setRepeatMode,
        },
        updatePosition: snapshot.position,
        repeatMode: switch (snapshot.repeatMode) {
          SystemMediaRepeatMode.none =>
            audio_service.AudioServiceRepeatMode.none,
          SystemMediaRepeatMode.all => audio_service.AudioServiceRepeatMode.all,
          SystemMediaRepeatMode.one => audio_service.AudioServiceRepeatMode.one,
        },
        queueIndex: snapshot.currentIndex,
      ),
    );
  }

  @override
  Future<void> clear() async {
    queue.add(const []);
    mediaItem.add(null);
    playbackState.add(
      audio_service.PlaybackState(
        processingState: audio_service.AudioProcessingState.idle,
      ),
    );
  }

  @override
  Future<void> play() => _send(SystemMediaCommandType.play);

  @override
  Future<void> pause() => _send(SystemMediaCommandType.pause);

  @override
  Future<void> seek(Duration position) =>
      _send(SystemMediaCommandType.seek, position: position);

  @override
  Future<void> fastForward() => _send(SystemMediaCommandType.seekForward);

  @override
  Future<void> rewind() => _send(SystemMediaCommandType.seekBackward);

  @override
  Future<void> seekForward(bool begin) =>
      begin ? _send(SystemMediaCommandType.seekForward) : Future<void>.value();

  @override
  Future<void> seekBackward(bool begin) =>
      begin ? _send(SystemMediaCommandType.seekBackward) : Future<void>.value();

  @override
  Future<void> skipToPrevious() => _send(SystemMediaCommandType.previous);

  @override
  Future<void> skipToNext() => _send(SystemMediaCommandType.next);

  @override
  Future<void> setRepeatMode(
    audio_service.AudioServiceRepeatMode repeatMode,
  ) => _send(
    SystemMediaCommandType.setRepeat,
    repeatMode: switch (repeatMode) {
      audio_service.AudioServiceRepeatMode.none => SystemMediaRepeatMode.none,
      audio_service.AudioServiceRepeatMode.all => SystemMediaRepeatMode.all,
      audio_service.AudioServiceRepeatMode.one => SystemMediaRepeatMode.one,
      audio_service.AudioServiceRepeatMode.group => SystemMediaRepeatMode.all,
    },
  );

  Future<void> _send(
    SystemMediaCommandType type, {
    Duration? position,
    SystemMediaRepeatMode? repeatMode,
  }) async {
    _commands.add(
      SystemMediaCommand(type, position: position, repeatMode: repeatMode),
    );
  }

  @override
  Future<void> dispose() => _commands.close();

  static audio_service.AudioProcessingState _processingState(
    AudioProcessingState state,
  ) => switch (state) {
    AudioProcessingState.idle => audio_service.AudioProcessingState.idle,
    AudioProcessingState.loading => audio_service.AudioProcessingState.loading,
    AudioProcessingState.buffering =>
      audio_service.AudioProcessingState.buffering,
    AudioProcessingState.ready => audio_service.AudioProcessingState.ready,
    AudioProcessingState.completed =>
      audio_service.AudioProcessingState.completed,
  };
}
