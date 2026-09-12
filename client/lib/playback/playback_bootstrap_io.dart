import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import 'audio_player_port.dart';
import 'audio_service_system_media_port.dart';
import 'audio_session_interruption_port.dart';
import 'playback_session_coordinator.dart';

Future<PlaybackSessionCoordinator> createPlaybackSession(
  AudioPlayerPort Function() audioPlayerFactory,
) async {
  if (defaultTargetPlatform != TargetPlatform.android) {
    final session = PlaybackSessionCoordinator(
      createAudioPlayer: audioPlayerFactory,
    );
    await session.initialize();
    return session;
  }

  final media = AudioServiceSystemMediaPort();
  await AudioService.init(
    builder: () => media,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'dev.arion.client.playback',
      androidNotificationChannelName: 'Arion playback',
      androidNotificationChannelDescription:
          'Playback controls for the active Arion queue',
      androidStopForegroundOnPause: false,
      fastForwardInterval: Duration(seconds: 10),
      rewindInterval: Duration(seconds: 10),
    ),
  );
  final session = PlaybackSessionCoordinator(
    createAudioPlayer: audioPlayerFactory,
    systemMedia: media,
    audioInterruptions: AudioSessionInterruptionPort(),
  );
  await session.initialize();
  return session;
}
