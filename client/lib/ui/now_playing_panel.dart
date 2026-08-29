import 'package:flutter/material.dart';

import '../library/track.dart';
import '../playback/playback_controller.dart';
import 'playback_queue_view.dart';

final class NowPlayingPanel extends StatelessWidget {
  const NowPlayingPanel({required this.controller, super.key});

  final PlaybackController controller;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final track = controller.visibleTrack;
            if (track == null) {
              return const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Text('Select a track to start listening.'),
              );
            }
            final duration = controller.effectiveDuration;
            final maximum = duration.inMilliseconds > 0
                ? duration.inMilliseconds.toDouble()
                : 1.0;
            final value = controller.position.inMilliseconds
                .clamp(0, maximum.toInt())
                .toDouble();
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              controller.isLoadingSelection
                                  ? 'Loading audio\u2026'
                                  : '${track.artist} \u2022 ${track.album}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (controller.error != null)
                        TextButton.icon(
                          key: const Key('playback-retry'),
                          onPressed: controller.retry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                    ],
                  ),
                  if (controller.error != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        controller.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  Wrap(
                    key: const Key('playback-queue-controls'),
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 2,
                    children: [
                      IconButton(
                        key: const Key('playback-previous'),
                        tooltip: 'Previous',
                        onPressed: controller.canGoPrevious
                            ? controller.skipToPrevious
                            : null,
                        icon: const Icon(Icons.skip_previous),
                      ),
                      IconButton.filled(
                        key: const Key('playback-toggle'),
                        tooltip: controller.isCompleted
                            ? 'Replay'
                            : controller.isPlaying
                            ? 'Pause'
                            : 'Play',
                        onPressed: controller.canControlPlayback
                            ? controller.togglePlayback
                            : null,
                        icon: controller.isBuffering
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                controller.isPlaying
                                    ? Icons.pause
                                    : controller.isCompleted
                                    ? Icons.replay
                                    : Icons.play_arrow,
                              ),
                      ),
                      IconButton(
                        key: const Key('playback-next'),
                        tooltip: 'Next',
                        onPressed: controller.canGoNext
                            ? controller.skipToNext
                            : null,
                        icon: const Icon(Icons.skip_next),
                      ),
                      IconButton(
                        key: const Key('playback-repeat'),
                        tooltip: _repeatTooltip(controller.repeatMode),
                        color: controller.repeatMode == PlaybackRepeatMode.off
                            ? null
                            : Theme.of(context).colorScheme.primary,
                        onPressed: controller.hasQueue
                            ? controller.cycleRepeatMode
                            : null,
                        icon: Icon(
                          controller.repeatMode == PlaybackRepeatMode.current
                              ? Icons.repeat_one
                              : Icons.repeat,
                        ),
                      ),
                      IconButton(
                        key: const Key('open-playback-queue'),
                        tooltip:
                            'Open queue (${controller.upcomingEntries.length} upcoming)',
                        onPressed: controller.hasQueue
                            ? () => showPlaybackQueue(context, controller)
                            : null,
                        icon: const Icon(Icons.queue_music),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text(formatDuration(controller.position)),
                      Expanded(
                        child: Slider(
                          key: const Key('playback-seek'),
                          value: value,
                          max: maximum,
                          onChanged: duration > Duration.zero
                              ? (next) => controller.seek(
                                  Duration(milliseconds: next.round()),
                                )
                              : null,
                        ),
                      ),
                      Text(formatDuration(duration)),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  static String _repeatTooltip(PlaybackRepeatMode mode) => switch (mode) {
    PlaybackRepeatMode.off => 'Repeat off',
    PlaybackRepeatMode.all => 'Repeat all',
    PlaybackRepeatMode.current => 'Repeat current',
  };
}
