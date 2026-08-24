import 'dart:async';

import 'package:just_audio/just_audio.dart';

import 'audio_player_port.dart';

final class JustAudioAdapter implements AudioPlayerPort {
  JustAudioAdapter({AudioPlayer? player}) : _player = player ?? AudioPlayer() {
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
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> dispose() async {
    await _eventSubscription.cancel();
    await _errors.close();
    await _player.dispose();
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
