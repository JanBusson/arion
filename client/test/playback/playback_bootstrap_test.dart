import 'package:arion_client/playback/playback_bootstrap_io.dart';
import 'package:arion_client/playback/playback_recovery_policy.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enables bounded recovery only for Android native playback', () {
    expect(
      playbackRecoveryPolicyFor(TargetPlatform.android),
      same(PlaybackRecoveryPolicy.android),
    );
    expect(
      playbackRecoveryPolicyFor(TargetPlatform.windows),
      same(PlaybackRecoveryPolicy.disabled),
    );
    expect(
      playbackRecoveryPolicyFor(TargetPlatform.iOS),
      same(PlaybackRecoveryPolicy.disabled),
    );
  });
}
