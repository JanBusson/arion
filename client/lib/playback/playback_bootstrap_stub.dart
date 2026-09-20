import 'audio_player_port.dart';
import 'just_audio_adapter.dart';
import 'playback_session_coordinator.dart';

Future<PlaybackSessionCoordinator> createPlaybackSession(
  AudioPlayerPort Function() audioPlayerFactory,
) async {
  final session = PlaybackSessionCoordinator(
    createAudioPlayer: audioPlayerFactory,
  );
  await session.initialize();
  return session;
}

AudioPlayerPort createDefaultAudioPlayer() => JustAudioAdapter();
