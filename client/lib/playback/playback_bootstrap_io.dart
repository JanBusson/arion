import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import 'audio_player_port.dart';
import 'audio_service_system_media_port.dart';
import 'audio_session_interruption_port.dart';
import 'playback_recovery_policy.dart';
import 'playback_session_coordinator.dart';

Future<PlaybackSessionCoordinator> createPlaybackSession(
  AudioPlayerPort Function() audioPlayerFactory,
) async {
  final recoveryPolicy = playbackRecoveryPolicyFor(defaultTargetPlatform);
  if (defaultTargetPlatform != TargetPlatform.android) {
    final session = PlaybackSessionCoordinator(
      createAudioPlayer: audioPlayerFactory,
      recoveryPolicy: recoveryPolicy,
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
    recoveryPolicy: recoveryPolicy,
  );
  await session.initialize();
  return session;
}

PlaybackRecoveryPolicy playbackRecoveryPolicyFor(TargetPlatform platform) =>
    platform == TargetPlatform.android
    ? PlaybackRecoveryPolicy.android
    : PlaybackRecoveryPolicy.disabled;
