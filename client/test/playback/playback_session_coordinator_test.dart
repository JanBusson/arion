import 'dart:async';

import 'package:arion_client/playback/audio_interruption_port.dart';
import 'package:arion_client/playback/audio_player_port.dart';
import 'package:arion_client/playback/playback_controller.dart';
import 'package:arion_client/playback/playback_session_coordinator.dart';
import 'package:arion_client/playback/playback_recovery_policy.dart';
import 'package:arion_client/playback/system_media_port.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late RecordingSystemMediaPort media;
  late FakeAudioInterruptionPort interruptions;
  late List<FakeAudioPlayer> players;
  late PlaybackSessionCoordinator session;

  setUp(() async {
    media = RecordingSystemMediaPort();
    interruptions = FakeAudioInterruptionPort();
    players = [];
    session = PlaybackSessionCoordinator(
      createAudioPlayer: () {
        final player = FakeAudioPlayer();
        players.add(player);
        return player;
      },
      systemMedia: media,
      audioInterruptions: interruptions,
    );
    await session.initialize();
  });

  tearDown(() async {
    await session.close();
  });

  test('retains one controller until the configured session changes', () async {
    final controller = (await session.replaceSession(configured: true))!;
    await controller.playNow(sampleTrack(), Uri.parse('http://server/audio/1'));
    await controller.addToQueue(
      sampleTrack(id: '2'),
      Uri.parse('http://server/audio/2'),
    );
    controller.setRepeatMode(PlaybackRepeatMode.current);

    await _settle();

    expect(session.controller, same(controller));
    expect(controller.queueEntries, hasLength(2));
    expect(controller.repeatMode, PlaybackRepeatMode.current);
    expect(players.single.disposed, isFalse);

    final replacement = (await session.replaceSession(configured: true))!;

    expect(replacement, isNot(same(controller)));
    expect(players.first.stopCalls, 1);
    expect(players.first.disposed, isTrue);
    expect(replacement.queueEntries, isEmpty);
    expect(replacement.repeatMode, PlaybackRepeatMode.off);
    expect(media.clearCalls, greaterThanOrEqualTo(2));
  });

  test('projects duplicate queue entries and only safe artwork URLs', () async {
    final controller = (await session.replaceSession(configured: true))!;
    final duplicate = sampleTrack(id: 'same', title: 'Duplicate');
    await controller.playNow(
      duplicate,
      Uri.parse('http://server/audio/same'),
      artworkUri: Uri.parse('http://secret@server/cover/same?token=private'),
    );
    await controller.addToQueue(
      duplicate,
      Uri.parse('http://server/audio/same'),
      artworkUri: Uri.parse('https://server/cover/same?size=large#fragment'),
    );
    controller.setRepeatMode(PlaybackRepeatMode.current);
    players.single.positions.add(const Duration(seconds: 4));
    await _settle();

    final state = media.published.last;
    expect(state.queue.map((item) => item.id).toSet(), hasLength(2));
    expect(state.queue.map((item) => item.title), everyElement('Duplicate'));
    expect(controller.queueEntries.last.artworkUri, isNotNull);
    expect(Uri.parse('https://server/cover/same').userInfo, isEmpty);
    final safeArtwork = Uri.parse(
      'https://server/cover/same?size=large#fragment',
    );
    expect(safeArtwork.scheme, 'https');
    expect(safeArtwork.userInfo, isEmpty);
    expect(
      safeSystemArtworkUri(safeArtwork),
      Uri.parse('https://server/cover/same'),
    );
    expect(state.queue.first.artworkUri, isNull);
    expect(state.queue.last.artworkUri, Uri.parse('https://server/cover/same'));
    expect(state.currentIndex, 0);
    expect(state.position, const Duration(seconds: 4));
    expect(state.repeatMode, SystemMediaRepeatMode.one);
    expect(state.canPause, isTrue);
    expect(state.canGoNext, isTrue);
  });

  test(
    'routes media commands through queue-aware controller operations',
    () async {
      final controller = (await session.replaceSession(configured: true))!;
      await controller.playNow(
        sampleTrack(id: '1'),
        Uri.parse('http://server/audio/1'),
      );
      await controller.addToQueue(
        sampleTrack(id: '2'),
        Uri.parse('http://server/audio/2'),
      );
      players.single.positions.add(const Duration(seconds: 5));
      await _settle();

      media.send(const SystemMediaCommand(SystemMediaCommandType.previous));
      await _settle();
      expect(controller.currentIndex, 0);
      expect(players.single.lastSeek, Duration.zero);

      media.send(const SystemMediaCommand(SystemMediaCommandType.next));
      await _settle();
      expect(controller.currentIndex, 1);

      media.send(
        const SystemMediaCommand(
          SystemMediaCommandType.setRepeat,
          repeatMode: SystemMediaRepeatMode.all,
        ),
      );
      await _settle();
      media.send(const SystemMediaCommand(SystemMediaCommandType.next));
      await _settle();
      expect(controller.currentIndex, 0);

      media.send(
        const SystemMediaCommand(
          SystemMediaCommandType.seek,
          position: Duration(hours: 1),
        ),
      );
      await _settle();
      expect(players.single.lastSeek, controller.effectiveDuration);

      media.send(const SystemMediaCommand(SystemMediaCommandType.pause));
      await _settle();
      expect(controller.isPlaying, isFalse);
      media.send(const SystemMediaCommand(SystemMediaCommandType.play));
      await _settle();
      expect(controller.isPlaying, isTrue);
    },
  );

  test('resumes only playback paused by a transient interruption', () async {
    final controller = (await session.replaceSession(configured: true))!;
    await controller.playNow(sampleTrack(), Uri.parse('http://server/audio/1'));
    await _settle();

    interruptions.sendInterruption(AudioInterruptionKind.transientLoss);
    await _settle();
    expect(controller.isPlaying, isFalse);
    final startsAfterLoss = players.single.playbackStarts;

    interruptions.sendInterruption(AudioInterruptionKind.transientGain);
    await _settle();
    expect(controller.isPlaying, isTrue);
    expect(players.single.playbackStarts, startsAfterLoss + 1);

    await controller.pause();
    final startsWhileOwnerPaused = players.single.playbackStarts;
    interruptions.sendInterruption(AudioInterruptionKind.transientLoss);
    await _settle();
    interruptions.sendInterruption(AudioInterruptionKind.transientGain);
    await _settle();
    expect(players.single.playbackStarts, startsWhileOwnerPaused);
    expect(controller.isPlaying, isFalse);
  });

  test('permanent loss and becoming noisy never auto-resume', () async {
    final controller = (await session.replaceSession(configured: true))!;
    await controller.playNow(sampleTrack(), Uri.parse('http://server/audio/1'));
    await _settle();

    interruptions.sendInterruption(AudioInterruptionKind.permanentLoss);
    await _settle();
    final startsAfterPermanentLoss = players.single.playbackStarts;
    interruptions.sendInterruption(AudioInterruptionKind.transientGain);
    await _settle();
    expect(controller.isPlaying, isFalse);
    expect(players.single.playbackStarts, startsAfterPermanentLoss);

    await controller.play();
    await _settle();
    interruptions.sendBecomingNoisy();
    await _settle();
    final startsAfterNoisy = players.single.playbackStarts;
    interruptions.sendInterruption(AudioInterruptionKind.transientGain);
    await _settle();
    expect(controller.isPlaying, isFalse);
    expect(players.single.playbackStarts, startsAfterNoisy);
    expect(controller.queueEntries, hasLength(1));
  });

  test('late source completion cannot republish a replaced session', () async {
    final load = Completer<Duration?>();
    final firstController = (await session.replaceSession(configured: true))!;
    players.first.setUrlHandler = (_, _) => load.future;
    unawaited(
      firstController.playNow(
        sampleTrack(title: 'Old source'),
        Uri.parse('http://server/audio/old'),
      ),
    );
    await _settle();
    final replacement = await session.replaceSession(configured: true);
    await _settle();
    final publicationCount = media.published.length;

    load.complete(const Duration(minutes: 2));
    await _settle();

    expect(session.controller, same(replacement));
    expect(media.published.length, publicationCount);
    expect(media.published.last.queue, isEmpty);
  });

  test('session replacement cancels delayed playback recovery', () async {
    final recoveryDelay = Completer<void>();
    final recoveryPlayer = FakeAudioPlayer();
    final recoverySession = PlaybackSessionCoordinator(
      createAudioPlayer: () => recoveryPlayer,
      recoveryPolicy: const PlaybackRecoveryPolicy(
        retryDelays: [Duration(seconds: 1)],
        attemptTimeout: Duration(seconds: 1),
      ),
      recoveryDelay: (_) => recoveryDelay.future,
    );
    addTearDown(recoverySession.close);
    await recoverySession.initialize();
    final controller = (await recoverySession.replaceSession(
      configured: true,
    ))!;
    await controller.playNow(sampleTrack(), Uri.parse('http://server/audio/1'));
    recoveryPlayer.errors.add(StateError('network lost'));
    await _settle();
    expect(controller.isReconnecting, isTrue);

    await recoverySession.replaceSession(configured: false);
    recoveryDelay.complete();
    await _settle();

    expect(recoveryPlayer.setUrlCalls, 1);
    expect(recoveryPlayer.disposed, isTrue);
    expect(recoverySession.controller, isNull);
  });

  test('projects reconnecting playback as pause-capable buffering', () async {
    final recoveryDelay = Completer<void>();
    final recoveryPlayer = FakeAudioPlayer();
    final recoveryMedia = RecordingSystemMediaPort();
    final recoverySession = PlaybackSessionCoordinator(
      createAudioPlayer: () => recoveryPlayer,
      systemMedia: recoveryMedia,
      recoveryPolicy: const PlaybackRecoveryPolicy(
        retryDelays: [Duration(seconds: 1)],
        attemptTimeout: Duration(seconds: 1),
      ),
      recoveryDelay: (_) => recoveryDelay.future,
    );
    addTearDown(recoverySession.close);
    await recoverySession.initialize();
    final controller = (await recoverySession.replaceSession(
      configured: true,
    ))!;
    await controller.playNow(sampleTrack(), Uri.parse('http://server/audio/1'));
    recoveryPlayer.positions.add(const Duration(seconds: 12));
    recoveryPlayer.errors.add(StateError('network lost'));
    await _settle();

    final reconnecting = recoveryMedia.published.last;
    expect(reconnecting.processingState, AudioProcessingState.buffering);
    expect(reconnecting.playing, isTrue);
    expect(reconnecting.position, const Duration(seconds: 12));
    expect(reconnecting.canPause, isTrue);
    expect(reconnecting.canPlay, isFalse);

    recoveryMedia.send(const SystemMediaCommand(SystemMediaCommandType.pause));
    await _settle();
    final paused = recoveryMedia.published.last;
    expect(controller.isReconnecting, isFalse);
    expect(paused.playing, isFalse);
    expect(paused.canPause, isFalse);
    expect(paused.canPlay, isTrue);

    recoveryDelay.complete();
  });
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));
