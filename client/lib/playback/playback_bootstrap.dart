import 'audio_player_port.dart';
import 'playback_session_coordinator.dart';
import 'playback_bootstrap_stub.dart'
    if (dart.library.io) 'playback_bootstrap_io.dart'
    as platform;

Future<PlaybackSessionCoordinator> createPlaybackSession(
  AudioPlayerPort Function() audioPlayerFactory,
) => platform.createPlaybackSession(audioPlayerFactory);
