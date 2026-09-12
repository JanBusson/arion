import 'dart:async';

typedef PlaybackRecoveryDelay = Future<void> Function(Duration duration);

final class PlaybackRecoveryPolicy {
  const PlaybackRecoveryPolicy({
    required this.retryDelays,
    required this.attemptTimeout,
  });

  static const disabled = PlaybackRecoveryPolicy(
    retryDelays: [],
    attemptTimeout: Duration.zero,
  );

  static const android = PlaybackRecoveryPolicy(
    retryDelays: [
      Duration.zero,
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
    ],
    attemptTimeout: Duration(seconds: 5),
  );

  final List<Duration> retryDelays;
  final Duration attemptTimeout;

  bool get enabled => retryDelays.isNotEmpty;
}

Future<void> defaultPlaybackRecoveryDelay(Duration duration) =>
    Future<void>.delayed(duration);
